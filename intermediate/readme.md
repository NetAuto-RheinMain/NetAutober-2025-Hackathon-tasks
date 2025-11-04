This is a fantastic and very common project for setting up a modern monitoring environment. The entire process, from provisioning infrastructure to deploying services and validating them, can be almost fully automated.

I'll provide you with the complete set of files and a master script to run the entire workflow. This solution will provision two AWS EC2 instances:

  * `monitoring-server`: Hosts Prometheus, Loki, and Grafana via Docker Compose.
  * `monitored-client`: Hosts Node Exporter and Promtail, which send metrics and logs to the server.

-----

### 📦 Project Structure

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
│   └── ssh-key.pub  (You must create this)
├── validation/
│   └── validate.py
└── run_automation.sh
└── run_destroy.sh
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

    - name: Install Docker Compose
      ansible.builtin.pip:
        name: docker-compose
        state: present

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
      ansible.builtin.shell: "docker-compose -f /opt/monitoring/docker-compose.yml up -d"
      args:
        chdir: /opt/monitoring
      become: no # Run as ubuntu user

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
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  max_transfer_retries: 0

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/boltdb-shipper-active
    cache_location: /tmp/loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /tmp/loki/chunks

compactor:
  working_directory: /tmp/loki/compactor
  shared_store: filesystem

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

ruler:
  alertmanager_url: http://localhost:9093
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
  
  