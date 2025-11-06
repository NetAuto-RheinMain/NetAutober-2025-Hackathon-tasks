# Intermediate Task

The entire process, from provisioning infrastructure to deploying services and validating them, can be almost fully automated.
This solution will provision two AWS EC2 instances:

  * `monitoring-server`: Hosts Prometheus, Loki, and Grafana via Docker Compose.
  * `monitored-client`: Hosts Node Exporter and Promtail, which send metrics and logs to the server.

-----

## 📦 Project Structure

For this to work, organize your files as follows:

```
aws-monitoring-stack/
├── ansible/
│   ├── main.yml
│   ├── ansible.cfg
│   ├── templates/
│   │   ├── docker-compose.yml.j2
│   │   ├── grafana-datasource.yml.j2
│   │   ├── loki-config.yml.j2
│   │   ├── prometheus.yml.j2
│   │   └── promtail-config.yml.j2
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── inventory.tpl
│   ├── ssh-key
│   └── ssh-key.pub
├── validation/
│   └── load_test.py
│   └── validate.py
├── create_ssh-secret.sh
├── run_automation.sh
├── run_destroy.sh
└── run_loadtest.sh
```

-----

### Prerequisites

1.  **AWS Account:** Credentials configured locally (e.g., via `aws configure`).
```sh
sudo apt install aws-cli
pip3 install --upgrade awscli
aws configure
```
2.  **Tools:** `terraform`, `ansible`, `python3` (with `pip`), `ssh-keygen`.
3.  **SSH Key:** Create an SSH key pair for this project.
    ```bash
    # Run this in the 'terraform/' directory
    cd terraform
    ssh-keygen -t rsa -b 4096 -f ssh-key -N ""
    chmod 400 ssh-key
    cd ..
    # This creates 'ssh-key' (private) and 'ssh-key.pub' (public)
    ```

-----

### 1\. 🌍 Terraform (Provision VMs)

These files will create the two Ubuntu VMs, a security group, and an SSH key pair. Critically, it will **auto-generate the Ansible inventory file**.

#### `terraform/variables.tf`

```terraform
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name for the EC2 Key Pair"
  type        = string
  default     = "monitoring-stack-key"
}
```

#### `terraform/main.tf`

```terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# Security Group to allow SSH, Grafana, Prometheus, Loki, Node Exporter
resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow SSH and monitoring ports"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: Open to all. Restrict to your IP in production.
  }
  
  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Loki
  ingress {
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Node Exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "monitoring-sg"
  }
}

# SSH Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = file("${path.module}/ssh-key.pub")
}

# Monitoring Server Instance
resource "aws_instance" "monitoring_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  tags = {
    Name = "monitoring-server"
  }
}

# Monitored Client Instance
resource "aws_instance" "monitored_client" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  tags = {
    Name = "monitored-client"
  }
}

# --- THIS IS THE KEY AUTOMATION STEP ---
# Generate an Ansible inventory file from Terraform output
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    monitoring_server_ip = aws_instance.monitoring_server.public_ip
    monitored_client_ip  = aws_instance.monitored_client.public_ip
    ssh_key_path         = abspath("${path.module}/ssh-key")
  })
  filename = "../ansible/inventory.ini"
}

# Template for the inventory file
resource "local_file" "inventory_template" {
  content = <<EOF
[monitoring_server]
server ansible_host=${monitoring_server_ip}

[monitored_client]
client ansible_host=${monitored_client_ip}

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=${ssh_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
  filename = "${path.module}/inventory.tpl"
  # This file is just a template, it's not used directly
}
```

#### `terraform/outputs.tf`

```terraform
output "monitoring_server_ip" {
  description = "Public IP of the monitoring server"
  value       = aws_instance.monitoring_server.public_ip
}

output "monitored_client_ip" {
  description = "Public IP of the monitored client"
  value       = aws_instance.monitored_client.public_ip
}
```

#### `terraform/inventory.tpl`
```ini
[monitoring_server]
server ansible_host=${monitoring_server_ip}

[monitored_client]
client ansible_host=${monitored_client_ip}

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=${ssh_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```


-----

### 2\. 🤖 Ansible (Install & Configure)

This part installs Docker/Docker Compose on the server and the exporters on the client.

#### `ansible/ansible.cfg`

```ini
[defaults]
inventory = inventory.ini
host_key_checking = False
deprecation_warnings = False
```

#### `ansible/main.yml`

```yaml
---
- name: 1. Setup Monitoring Server
  hosts: monitoring_server
  become: yes
  tasks:
    - name: Wait for system to be ready
      ansible.builtin.wait_for_connection:
        delay: 10
        timeout: 60

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
      
    - name: Install prerequisite packages
      ansible.builtin.apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
          - python3-pip
        state: present

    - name: Install Docker
      ansible.builtin.shell: |
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
      args:
        creates: /usr/bin/docker

    - name: Add ubuntu user to docker group
      ansible.builtin.user:
        name: ubuntu
        groups: docker
        append: yes

    - name: Create monitoring config directory
      ansible.builtin.file:
        path: /opt/monitoring
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Create prometheus config directory
      ansible.builtin.file:
        path: /opt/monitoring/prometheus
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Create grafana provisioning directory
      ansible.builtin.file:
        path: /opt/monitoring/grafana_provisioning/datasources
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Template Prometheus config
      ansible.builtin.template:
        src: templates/prometheus.yml.j2
        dest: /opt/monitoring/prometheus/prometheus.yml
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Template Loki config
      ansible.builtin.template:
        src: templates/loki-config.yml.j2
        dest: /opt/monitoring/loki-config.yml
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Template Grafana datasource
      ansible.builtin.template:
        src: templates/grafana-datasource.yml.j2
        dest: /opt/monitoring/grafana_provisioning/datasources/datasources.yml
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Template Docker Compose file
      ansible.builtin.template:
        src: templates/docker-compose.yml.j2
        dest: /opt/monitoring/docker-compose.yml
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Start the monitoring stack
      ansible.builtin.shell: "docker compose -f /opt/monitoring/docker-compose.yml up -d"
      args:
        chdir: /opt/monitoring
      become: yes # Run as ubuntu user

- name: 2. Setup Monitored Client
  hosts: monitored_client
  become: yes
  vars:
    node_exporter_version: "1.8.1"
    promtail_version: "3.0.0"
  tasks:
    - name: Wait for system to be ready
      ansible.builtin.wait_for_connection:
        delay: 10
        timeout: 60

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes

    - name: Install unzip
      ansible.builtin.apt:
        name: unzip
        state: present

    - name: Create user for node_exporter
      ansible.builtin.user:
        name: node_exporter
        shell: /bin/false
        system: yes
        create_home: no

    # --- Node Exporter ---
    - name: Download and unarchive Node Exporter
      ansible.builtin.unarchive:
        src: "https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
        dest: /tmp/
        remote_src: yes
        
    - name: Move node_exporter binary
      ansible.builtin.copy:
        src: "/tmp/node_exporter-{{ node_exporter_version }}.linux-amd64/node_exporter"
        dest: /usr/local/bin/node_exporter
        mode: '0755'
        owner: node_exporter
        group: node_exporter
        remote_src: yes

    - name: Create node_exporter systemd service
      ansible.builtin.copy:
        dest: /etc/systemd/system/node_exporter.service
        content: |
          [Unit]
          Description=Node Exporter
          Wants=network-online.target
          After=network-online.target

          [Service]
          User=node_exporter
          Group=node_exporter
          Type=simple
          ExecStart=/usr/local/bin/node_exporter

          [Install]
          WantedBy=multi-user.target

    - name: Start and enable node_exporter
      ansible.builtin.systemd:
        name: node_exporter
        state: started
        enabled: yes
        daemon_reload: yes

    # --- Promtail ---
    - name: Download and unzip Promtail
      ansible.builtin.unarchive:
        src: "https://github.com/grafana/loki/releases/download/v{{ promtail_version }}/promtail-linux-amd64.zip"
        dest: /tmp/
        remote_src: yes

    - name: Move promtail binary
      ansible.builtin.copy:
        src: /tmp/promtail-linux-amd64
        dest: /usr/local/bin/promtail
        mode: '0755'
        remote_src: yes

    - name: Create promtail config directory
      ansible.builtin.file:
        path: /etc/promtail
        state: directory

    - name: Template Promtail config
      ansible.builtin.template:
        src: templates/promtail-config.yml.j2
        dest: /etc/promtail/config.yml

    - name: Create promtail systemd service
      ansible.builtin.copy:
        dest: /etc/systemd/system/promtail.service
        content: |
          [Unit]
          Description=Promtail
          Wants=network-online.target
          After=network-online.target

          [Service]
          Type=simple
          ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/config.yml

          [Install]
          WantedBy=multi-user.target

    - name: Start and enable promtail
      ansible.builtin.systemd:
        name: promtail
        state: started
        enabled: yes
        daemon_reload: yes

```

-----

### 3\. 📜 Ansible Templates (Service Configs)

These files are templates that Ansible will populate with the correct IP addresses.

#### `ansible/templates/docker-compose.yml.j2`

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.47.2
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - /opt/monitoring/prometheus:/etc/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'

  loki:
    image: grafana/loki:3.0.0
    container_name: loki
    restart: unless-stopped
    ports:
      - "3100:3100"
    volumes:
      - /opt/monitoring/loki-config.yml:/etc/loki/local-config.yaml
    command:
      - '-config.file=/etc/loki/local-config.yaml'

  grafana:
    image: grafana/grafana:10.2.0
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - /opt/monitoring/grafana_provisioning:/etc/grafana/provisioning
```

#### `ansible/templates/prometheus.yml.j2`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['{{ hostvars['client']['ansible_host'] }}:9100']
```

#### `ansible/templates/loki-config.yml.j2`

(This is a basic, standard Loki config)

```yaml
# Corrected config for Loki 3.0
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/boltdb-shipper-active
    cache_location: /tmp/loki/boltdb-shipper-cache
    cache_ttl: 24h
  filesystem:
    directory: /tmp/loki/chunks

compactor:
  working_directory: /tmp/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem

limits_config:
  allow_structured_metadata: false 

  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 15
  ingestion_burst_size_mb: 20
```

#### `ansible/templates/grafana-datasource.yml.j2`

(This auto-provisions the datasources in Grafana\!)

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
  
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true
```

#### `ansible/templates/promtail-config.yml.j2`

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://{{ hostvars['server']['ansible_host'] }}:3100/loki/api/v1/push

scrape_configs:
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/syslog
```

-----

### 4\. 🐍 Python (Validation)

This script checks the Prometheus and Loki APIs to confirm they are receiving data.

#### `validation/validate.py`

```python
import sys
import requests
import time

def check_prometheus(ip):
    print(f"--- Checking Prometheus (http://{ip}:9090) ---")
    try:
        url = f"http://{ip}:9090/api/v1/targets"
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        targets = data.get('data', {}).get('activeTargets', [])
        
        if not targets:
            print("❌ FAILURE: No active targets found in Prometheus.")
            return False

        print(f"Found {len(targets)} active targets:")
        all_up = True
        for target in targets:
            job = target.get('scrapePool')
            health = target.get('health')
            print(f"  > Target: {job} | Health: {health}")
            if health != "up":
                all_up = False
        
        if all_up:
            print("✅ SUCCESS: All Prometheus targets are 'up'.")
            return True
        else:
            print("❌ FAILURE: Not all Prometheus targets are 'up'.")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ FAILURE: Could not connect to Prometheus: {e}")
        return False

def check_loki(ip):
    print(f"\n--- Checking Loki (http://{ip}:3100) ---")
    try:
        # Give Promtail a few seconds to send its first logs
        print("Waiting 15s for logs to arrive in Loki...")
        time.sleep(15)

        url = f"http://{ip}:3100/loki/api/v1/labels"
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        labels = data.get('data', [])
        
        if 'job' in labels:
            print("✅ SUCCESS: Loki API is responding and reports 'job' label.")
            
            # Bonus check: query for actual logs
            query_url = f"http://{ip}:3100/loki/api/v1/query"
            params = {'query': '{job="syslog"}'}
            query_response = requests.get(query_url, params=params, timeout=10)
            query_data = query_response.json()
            
            if query_data.get('data', {}).get('result', []):
                print("✅ SUCCESS: Found actual log streams for job='syslog'.")
                return True
            else:
                print("❌ FAILURE: Loki is up, but no log streams found for job='syslog'.")
                return False
        else:
            print("❌ FAILURE: Loki API did not return expected labels.")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ FAILURE: Could not connect to Loki: {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python validate.py <monitoring_server_ip>")
        sys.exit(1)
        
    server_ip = sys.argv[1]
    
    print(f"Starting validation against server: {server_ip}...\n")
    
    # Retry logic for connecting, as services might be starting
    max_retries = 5
    delay = 10
    
    for attempt in range(max_retries):
        print(f"--- Attempt {attempt + 1}/{max_retries} ---")
        prom_ok = check_prometheus(server_ip)
        loki_ok = False
        if prom_ok: # Only check loki if prometheus is reachable
             loki_ok = check_loki(server_ip)
        
        if prom_ok and loki_ok:
            print("\n==========================")
            print("🎉 Validation Complete: All services are UP and receiving data!")
            print("==========================")
            sys.exit(0)
            
        print(f"\nRetrying in {delay} seconds...")
        time.sleep(delay)

    print("\n==========================")
    print("🔥 Validation Failed after all attempts.")
    print("==========================")
    sys.exit(1)

if __name__ == "__main__":
    main()
```

-----

### 5\. 🚀 Automation (The Master Scripts)

These scripts tie everything together.

#### `run_automation.sh`

```bash
#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

echo "--- 1. Provisioning Infrastructure with Terraform ---"
cd terraform
terraform init
terraform apply -auto-approve
# Get the server IP from terraform output
SERVER_IP=$(terraform output -raw monitoring_server_ip)
cd ..

echo ""
echo "--- 2. Waiting 30s for VMs to initialize SSH ---"
sleep 30

echo ""
echo "--- 3. Configuring Services with Ansible ---"
cd ansible
ansible-playbook -i inventory.ini main.yml
cd ..

echo ""
echo "--- 4. Validating the Deployment ---"
cd validation
pip install -q requests
python3 validate.py $SERVER_IP
cd ..

echo ""
echo "============================================================="
echo "✅🚀 Deployment Successful!"
echo ""
echo "You can now access Grafana at: http://${SERVER_IP}:3000"
echo "(Login: admin / admin)"
echo "============================================================="
```

#### `run_destroy.sh`

(For cleaning up all AWS resources)

```bash
#!/bin/bash
set -e

read -p "Are you sure you want to destroy all AWS resources? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Destroy cancelled."
    exit 1
fi

echo "--- Destroying AWS Resources with Terraform ---"
cd terraform
terraform destroy -auto-approve

echo "--- Cleaning up local files ---"
rm -f ssh-key ssh-key.pub
rm -f ../ansible/inventory.ini
rm -f .terraform.lock.hcl
rm -rf .terraform
cd ..

echo "✅ Cleanup complete."
```

### 6\. 🏃‍♂️ How to Run

1.  Make the scripts executable:
    ```bash
    chmod +x run_automation.sh
    chmod +x run_destroy.sh
    ```
2.  Run the automation script:
    ```bash
    ./run_automation.sh
    ```
3.  Wait 5-10 minutes for everything to provision and configure.
4.  The script will finish by running the Python validation.

### 7\. 📊 Visualize 

1.  Get the Grafana IP from the `run_automation.sh` output.
2.  Open your browser to `http://<SERVER_IP>:3000`.
3.  Log in with username `admin` and password `admin`.
4.  **Check Metrics (Prometheus):**
      * Click the "Explore" (compass) icon on the left.
      * At the top, the "Prometheus" datasource should be selected.
      * In the query box, type `up` and run the query. You should see `up{job="node_exporter"}` and `up{job="prometheus"}` both with a value of 1.
      * Try another query like `node_cpu_seconds_total`.
5.  **Check Logs (Loki):**
      * In Explore, switch the datasource to "Loki".
      * In the query box, type `{job="syslog"}` and run the query.
      * You should see all the `syslog` entries from your `monitored-client` VM.
  
### 8. Test the Environment

`validation/run_test.py`
```python
import sys
import time
import multiprocessing
import subprocess
import os
import random

# --- Worker Functions ---

def cpu_worker(burn_event, stop_event):
    """
    A process that will either burn 100% CPU or sleep,
    based on the state of the 'burn_event'.
    """
    pid = os.getpid()
    print(f"[CPU Worker {pid}]: Started.")
    try:
        while not stop_event.is_set():
            if burn_event.is_set():
                # High CPU load: busy-wait loop
                _ = 1 * 1 
            else:
                # Low CPU load: sleep to yield the CPU
                time.sleep(0.01)
    except KeyboardInterrupt:
        pass # Handle Ctrl+C
    print(f"[CPU Worker {pid}]: Stopping.")


def memory_worker(chunk_mb, interval_sec, stop_event):
    """
    A process that gradually allocates memory in chunks.
    """
    pid = os.getpid()
    print(f"[MEM Worker {pid}]: Started. Will allocate {chunk_mb}MB every {interval_sec}s.")
    memory_hog = []
    total_allocated = 0
    try:
        while not stop_event.is_set():
            chunk = bytearray(chunk_mb * 1024 * 1024)
            memory_hog.append(chunk)
            total_allocated += chunk_mb
            print(f"[MEM Worker {pid}]: Allocated {chunk_mb}MB. Total RAM held: {total_allocated}MB")
            
            # Sleep until the next interval, checking for stop signal
            sleep_end = time.time() + interval_sec
            while time.time() < sleep_end and not stop_event.is_set():
                time.sleep(0.1)
                
    except MemoryError:
        print(f"[MEM Worker {pid}]: FAILED! Out of memory. Holding {total_allocated}MB.")
        # Keep the process alive to hold the memory
        while not stop_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    print(f"[MEM Worker {pid}]: Stopping. Releasing {total_allocated}MB.")


def log_worker(interval_sec, stop_event):
    """
    A process that continuously generates syslog messages.
    Uses the 'logger' command-line utility.
    """
    pid = os.getpid()
    print(f"[LOG Worker {pid}]: Started. Will log every {interval_sec}s.")
    log_levels = ["INFO", "WARNING", "ERROR"]
    try:
        while not stop_event.is_set():
            # Generate a random log message
            level = random.choice(log_levels)
            message = f"{level}: Dynamic log message from PID {pid}. Value: {random.randint(1000, 9999)}"
            
            # Use 'logger' utility to send to syslog
            try:
                subprocess.run(
                    ["logger", "-t", "LoadTest", message], 
                    check=True,
                    timeout=0.5
                )
            except Exception as e:
                print(f"[LOG Worker {pid}]: Failed to write to logger: {e}")
            
            # Sleep, checking for stop signal
            sleep_end = time.time() + interval_sec
            while time.time() < sleep_end and not stop_event.is_set():
                time.sleep(0.05)

    except KeyboardInterrupt:
        pass
    print(f"[LOG Worker {pid}]: Stopping.")


# --- Main Controller ---

def run_load_test(total_duration_sec):
    print(f"--- Starting Dynamic Load Test for {total_duration_sec} seconds ---")
    
    # Events to control the child processes
    stop_event = multiprocessing.Event()
    cpu_burn_event = multiprocessing.Event()
    
    processes = []
    
    try:
        # 1. Start CPU Workers (one for each core)
        num_cores = multiprocessing.cpu_count()
        print(f"Starting {num_cores} CPU workers...")
        for _ in range(num_cores):
            p = multiprocessing.Process(target=cpu_worker, args=(cpu_burn_event, stop_event))
            p.start()
            processes.append(p)
            
        # 2. Start Memory Worker
        print("Starting 1 Memory worker...")
        p_mem = multiprocessing.Process(target=memory_worker, args=(50, 5, stop_event)) # 50MB every 5s
        p_mem.start()
        processes.append(p_mem)
        
        # 3. Start Log Worker
        print("Starting 1 Log worker...")
        p_log = multiprocessing.Process(target=log_worker, args=(0.5, stop_event)) # Log every 0.5s
        p_log.start()
        processes.append(p_log)
        
        # 4. Run the main control loop
        start_time = time.time()
        while time.time() - start_time < total_duration_sec:
            # CPU WAVE: 20 seconds ON
            print("\n[MAIN]: === Ramping CPU UP! === (20s)")
            cpu_burn_event.set()
            time.sleep(20)
            
            if time.time() - start_time > total_duration_sec:
                break
                
            # CPU WAVE: 10 seconds OFF
            print("\n[MAIN]: === Ramping CPU DOWN. === (10s)")
            cpu_burn_event.clear()
            time.sleep(10)
        
        print("\n[MAIN]: --- Total duration finished. ---")

    except KeyboardInterrupt:
        print("\n[MAIN]: --- Load test interrupted by user. ---")
    
    finally:
        # Stop all child processes
        print("[MAIN]: Sending stop signal to all workers...")
        stop_event.set()
        
        for p in processes:
            p.join(timeout=5) # Wait 5s for graceful stop
            if p.is_alive():
                print(f"[MAIN]: Process {p.pid} did not exit, terminating...")
                p.terminate()
                p.join()
                
        print("[MAIN]: --- Load Test Complete. ---")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 load_test.py <duration_in_seconds>")
        sys.exit(1)
    
    try:
        duration = int(sys.argv[1])
    except ValueError:
        print("Error: Duration must be an integer.")
        sys.exit(1)
        
    run_load_test(duration)
```

`run_loadtest.sh`
```sh
#!/bin/bash
set -e

# Default duration in seconds if no argument is given
DEFAULT_DURATION=60
DURATION=${1:-$DEFAULT_DURATION}

echo "--- Preparing for load test for $DURATION seconds ---"

# --- Get VM Details ---
echo "Getting client IP from Terraform..."
KEY_PATH="terraform/ssh-key"
CLIENT_IP=$(terraform -chdir=terraform output -raw monitored_client_ip)
SCRIPT_PATH="validation/load_test.py"
REMOTE_PATH="/tmp/load_test.py"

if [ -z "$CLIENT_IP" ]; then
    echo "Error: Could not get client IP from Terraform. Is the stack deployed?"
    exit 1
fi

echo "Client IP found: $CLIENT_IP"

# --- Copy Script to Server ---
echo "Copying load test script to $CLIENT_IP..."
scp -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SCRIPT_PATH ubuntu@$CLIENT_IP:$REMOTE_PATH

# --- Run Script on Server ---
echo ""
echo "=========================================================="
echo "🚀 STARTING LOAD TEST on $CLIENT_IP for $DURATION seconds"
echo " WATCH YOUR GRAFANA DASHBOARD NOW!"
echo "=========================================================="
echo ""

ssh -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$CLIENT_IP "python3 $REMOTE_PATH $DURATION"

echo ""
echo "=========================================================="
echo "✅ Load test complete."
echo "Check Grafana for the spike."
echo "=========================================================="
```

```bash
chmod +x run_loadtest.sh
```

#### 2.  **Open your Grafana Dashboard:**

      * Go to `http://<YOUR-SERVER-IP>:3000`.
      * Log in (admin/admin).
      * Go to the **Explore** view.
      * Select the **Prometheus** datasource.
      * In the query box, type this PromQL query to see CPU usage:
        ```promql
        # This query shows CPU usage percentage by core
        100 - (avg by (instance, cpu) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)
            * Set the auto-refresh in the top-right to **5 seconds**.

### 3\. What to Watch in Grafana

  * **1. CPU Wave (Prometheus):**

      * **Query:** `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)`
      * **What you'll see:** The CPU usage will jump to 100% for 20 seconds, then drop to near 0% for 10 seconds, then repeat. It will look like a square wave.

  * **2. Memory Stair-Step (Prometheus):**

      * **Query:** `node_memory_MemAvailable_bytes{instance=~".*client.*"}` (or just `node_memory_MemAvailable_bytes` and find the client)
      * **What you'll see:** The "Available Memory" will **decrease** in sharp 50MB steps every 5 seconds, creating a "stair-step down" pattern. When the test ends, it will jump back up as the memory is released.

  * **3. Log Stream (Loki):**

      * **Query:** `{job="syslog"} |~ "LoadTest"`
      * **What you'll see:** A new log line will appear every 0.5 seconds, with `LoadTest` as the tag. You'll see the "INFO", "WARNING", and "ERROR" messages appearing as they are generated. This confirms Promtail is scraping and Loki is ingesting your logs in real-time.

#### 4.  **Run the Load Test:**
Run the script from your project root. You can pass a duration (in seconds) or it will default to 60.

```bash
# Run for the default 60 seconds
./run_loadtest.sh

# Or, run for 2 minutes (120 seconds)
./run_loadtest.sh 120

```