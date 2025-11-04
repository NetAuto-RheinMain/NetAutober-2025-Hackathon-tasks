This is a comprehensive, multi-step infrastructure task. I can provide a complete guide with all the necessary code and configuration files to accomplish this.

Here is a step-by-step walkthrough to build your entire monitoring stack.

### 📋 Prerequisites

Before you begin, make sure you have the following installed on your local machine:

  * An **AWS account** with an IAM user and access keys configured.
  * **Terraform CLI**
  * **Ansible**
  * **Python 3** (with the `requests` library: `pip install requests`)
  * An **AWS EC2 Key Pair** for SSH access. You must create this in the AWS console first.

-----

### 1\. Provision AWS Ubuntu VM with Terraform

First, we'll create a project directory and define our infrastructure using Terraform. This will set up one EC2 instance and a security group to allow all the necessary traffic.

**Project Structure:**

```
monitoring-project/
├── main.tf
├── variables.tf
└── outputs.tf
```

#### `variables.tf`

Define your SSH key name here.

```hcl
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium" # Recommended for running the full stack
}

variable "key_name" {
  description = "Name of your AWS EC2 Key Pair for SSH"
  type        = string
  default     = "your-key-name" # <-- IMPORTANT: Change this
}
```

#### `main.tf`

This file defines the provider, security group, and the EC2 instance.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# 1. Define Security Group to allow necessary ports
resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow traffic for monitoring stack"

  # SSH access from your IP (replace with your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # <-- WARNING: For demo only. Lock this to your IP.
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
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

  # Loki
  ingress {
    from_port   = 3100
    to_port     = 3100
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

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Find the latest Ubuntu 22.04 AMI
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
  owners = ["099720109477"] # Canonical's AWS account
}

# 3. Create the EC2 Instance
resource "aws_instance" "monitoring_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  tags = {
    Name = "Monitoring-Server"
  }
}
```

#### `outputs.tf`

This will print the public IP of your server after it's created.

```hcl
output "public_ip" {
  description = "Public IP address of the monitoring server"
  value       = aws_instance.monitoring_server.public_ip
}
```

**To Deploy:**

1.  Run `terraform init` to initialize the provider.
2.  Run `terraform apply` and type `yes` to provision the resources.
3.  Note the `public_ip` from the output.

-----

### 2\. Configure Server with Ansible

Now we'll use Ansible to configure the server. This single playbook will:

1.  Install Docker & Docker Compose.
2.  Install and set up Node Exporter as a service.
3.  Install and set up Promtail as a service.
4.  Copy over the Docker Compose and config files for the monitoring stack.
5.  Launch the monitoring stack.

#### Create Ansible Files

In the same project directory, create these files:

**`inventory`**
Create an inventory file. Replace `<YOUR-SERVER-IP>` with the IP from `terraform output`.

```ini
[monitoring_server]
<YOUR-SERVER-IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/your-key-file.pem
```

> **Note:** Replace `~/.ssh/your-key-file.pem` with the path to the private key for the `key_name` you used in Terraform.

**`ansible.cfg`**
This tells Ansible to use your inventory file.

```ini
[defaults]
inventory = inventory
remote_user = ubuntu
host_key_checking = False
```

**`promtail-config.yml`** (This will be copied to the server)
This config tells Promtail to send logs to Loki (which will be at `localhost:3100`) and which log files to read.

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
- job_name: system
  static_configs:
  - targets:
      - localhost
    labels:
      job: syslog
      __path__: /var/log/syslog
```

**`playbook.yml`**
This is the main Ansible playbook that does all the configuration.

```yaml
---
- name: Configure Monitoring Server
  hosts: monitoring_server
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install prerequisite packages
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - software-properties-common
          - python3-pip
        state: present

    # --- 1. Install Docker ---
    - name: Add Docker GPG key
      apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add Docker repository
      apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable
        state: present

    - name: Install Docker
      apt:
        name: docker-ce
        state: present

    - name: Install Docker Compose
      pip:
        name: docker-compose
        executable: pip3

    - name: Add ubuntu user to docker group
      user:
        name: ubuntu
        groups: docker
        append: yes

    # --- 2. Install Node Exporter ---
    - name: Download and unarchive Node Exporter
      unarchive:
        src: https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
        dest: /tmp/
        remote_src: yes

    - name: Move Node Exporter binary
      copy:
        src: /tmp/node_exporter-1.7.0.linux-amd64/node_exporter
        dest: /usr/local/bin/node_exporter
        mode: '0755'
        remote_src: yes

    - name: Create Node Exporter systemd service
      copy:
        dest: /etc/systemd/system/node_exporter.service
        content: |
          [Unit]
          Description=Node Exporter
          Wants=network-online.target
          After=network-online.target
          [Service]
          User=nobody
          ExecStart=/usr/local/bin/node_exporter
          [Install]
          WantedBy=multi-user.target

    - name: Start and enable Node Exporter service
      systemd:
        name: node_exporter
        state: started
        enabled: yes
        daemon_reload: yes

    # --- 3. Install Promtail ---
    - name: Download and unarchive Promtail
      unarchive:
        src: https://github.com/grafana/loki/releases/download/v2.9.3/promtail-linux-amd64.zip
        dest: /tmp/
        remote_src: yes

    - name: Move Promtail binary
      copy:
        src: /tmp/promtail-linux-amd64
        dest: /usr/local/bin/promtail
        mode: '0755'
        remote_src: yes

    - name: Create Promtail config directory
      file:
        path: /etc/promtail
        state: directory

    - name: Copy Promtail config
      copy:
        src: promtail-config.yml
        dest: /etc/promtail/config.yml

    - name: Create Promtail systemd service
      copy:
        dest: /etc/systemd/system/promtail.service
        content: |
          [Unit]
          Description=Promtail
          Wants=network-online.target
          After=network-online.target
          [Service]
          User=root
          ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/config.yml
          [Install]
          WantedBy=multi-user.target

    - name: Start and enable Promtail service
      systemd:
        name: promtail
        state: started
        enabled: yes
        daemon_reload: yes
```

**Run the Playbook:**
Make sure you can SSH to your server first, then run:

```bash
ansible-playbook playbook.yml
```

This will take a few minutes. When it finishes, your server will have Docker, Node Exporter, and Promtail running.

-----

### 3\. Deploy Monitoring Stack (Docker Compose)

The final configuration step is to deploy Prometheus, Loki, and Grafana. We'll add this to our Ansible setup.

Create a new directory `monitoring_stack` and add these files:

**`monitoring_stack/docker-compose.yml`**

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    networks:
      - monitoring-net

  loki:
    image: grafana/loki:latest
    container_name: loki
    ports:
      - "3100:3100"
    command:
      - '-config.file=/etc/loki/local-config.yaml'
    networks:
      - monitoring-net

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus
      - loki
    networks:
      - monitoring-net

networks:
  monitoring-net:
    driver: bridge
```

**`monitoring_stack/prometheus.yml`**
This config tells Prometheus to scrape itself and, most importantly, our **Node Exporter** running on the host.

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      # We use 'host.docker.internal' to allow the container
      # to reach the Node Exporter service running on the host machine.
      - targets: ['host.docker.internal:9100']
```

**Update `playbook.yml`**
Add these final tasks to the *end* of your `playbook.yml`:

```yaml
    # ... (all previous tasks)

    # --- 4. Deploy Monitoring Stack ---
    - name: Create monitoring directory on server
      file:
        path: /home/ubuntu/monitoring_stack
        state: directory

    - name: Copy Docker Compose and Prometheus config
      copy:
        src: monitoring_stack/
        dest: /home/ubuntu/monitoring_stack/

    - name: Add host.docker.internal to /etc/hosts for prometheus
      lineinfile:
        path: /etc/hosts
        line: '172.17.0.1 host.docker.internal' # 172.17.0.1 is the default docker bridge IP
        create: yes

    - name: Launch Monitoring Stack with Docker Compose
      command:
        cmd: docker-compose -f /home/ubuntu/monitoring_stack/docker-compose.yml up -d
        chdir: /home/ubuntu/monitoring_stack/
```

**Run the Playbook Again:**
Ansible is idempotent, so it's safe to run again. It will skip all the completed tasks and just apply the new ones.

```bash
ansible-playbook playbook.yml
```

After this, your full stack is running\!

  * **Node Exporter:** `http://<YOUR-SERVER-IP>:9100`
  * **Prometheus:** `http://<YOUR-SERVER-IP>:9090`
  * **Loki:** `http://<YOUR-SERVER-IP>:3100`
  * **Grafana:** `http://<YOUR-SERVER-IP>:3000`

-----

### 4\. Validate with Python

You can run these simple Python scripts from your local machine to confirm the APIs are responding.

**`validate.py`** (Replace `<YOUR-SERVER-IP>` with your public IP)

```python
import requests
import sys

SERVER_IP = "<YOUR-SERVER-IP>"
PROMETHEUS_URL = f"http://{SERVER_IP}:9090"
LOKI_URL = f"http://{SERVER_IP}:3100"

def validate_prometheus():
    print("Validating Prometheus...")
    try:
        # Query for all 'up' metrics
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': 'up'})
        response.raise_for_status() # Raise error for bad responses
        
        data = response.json()
        if data['status'] == 'success':
            targets = data['data']['result']
            print(f"  [SUCCESS] Prometheus API is up. Found {len(targets)} targets.")
            
            for target in targets:
                job = target['metric']['job']
                instance = target['metric']['instance']
                status = target['value'][1]
                
                if job == 'node_exporter' and status == '1':
                    print(f"  [SUCCESS] Node Exporter job '{instance}' is UP.")
                    return True
            print("  [FAILURE] Node Exporter job not found or is down.")
            return False
        else:
            print("  [FAILURE] Prometheus API returned non-success status.")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"  [FAILURE] Could not connect to Prometheus: {e}")
        return False

def validate_loki():
    print("\nValidating Loki...")
    try:
        # Query for all known labels
        response = requests.get(f"{LOKI_URL}/loki/api/v1/labels")
        response.raise_for_status()
        
        data = response.json()
        if data['status'] == 'success':
            labels = data['data']
            print(f"  [SUCCESS] Loki API is up. Found labels: {labels}")
            if 'job' in labels and 'syslog' in requests.get(f"{LOKI_URL}/loki/api/v1/label/job/values").json()['data']:
                 print("  [SUCCESS] Found 'syslog' job in Loki.")
                 return True
            print("  [FAILURE] 'syslog' job not found in Loki labels.")
            return False
        else:
            print("  [FAILURE] Loki API returned non-success status.")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"  [FAILURE] Could not connect to Loki: {e}")
        return False

if __name__ == "__main__":
    print(f"--- Validating Monitoring Stack at {SERVER_IP} ---")
    prom_ok = validate_prometheus()
    loki_ok = validate_loki()
    
    if prom_ok and loki_ok:
        print("\n✅ All services validated successfully!")
    else:
        print("\n❌ Validation failed.")
        sys.exit(1)
```

**Run it:**

```bash
python3 validate.py
```

You should see success messages for both Prometheus and Loki.

-----

### 5\. Visualize in Grafana

This is the final, manual step.

1.  **Access Grafana:** Open your browser and go to `http://<YOUR-SERVER-IP>:3000`.
2.  **Log In:** Use the credentials `admin` / `admin`.

#### Add Prometheus Data Source

1.  Click the **"Connections"** icon (plug) on the left menu.
2.  Click **"Data sources"**.
3.  Click **"Add data source"** and select **Prometheus**.
4.  In the "HTTP" section, set the URL to `http://prometheus:9090`.
      * *Why `http://prometheus:9090`?* Because Grafana is running in the same Docker network as Prometheus, it can find it by its service name (`prometheus`).
5.  Click **"Save & test"**. You should see a green "Data source is working" message.

#### Add Loki Data Source

1.  Go back to **"Connections"** \> **"Data sources"**.
2.  Click **"Add data source"** and select **Loki**.
3.  In the "HTTP" section, set the URL to `http://loki:3100`.
4.  Click **"Save & test"**. You should see a green "Data source is working" message.

#### Import a Node Exporter Dashboard

1.  Click the **"Dashboards"** icon (four squares) on the left menu.
2.  Click **"New"** in the top right, then select **"Import"**.
3.  In the "Import via grafana.com" box, enter the dashboard ID **`1860`**. This is a very popular "Node Exporter Full" dashboard.
4.  Click **"Load"**.
5.  On the next screen, at the bottom, select your **Prometheus** data source from the dropdown.
6.  Click **"Import"**.

You will immediately see a full dashboard populated with all the system metrics (CPU, RAM, disk, network, etc.) from your Ubuntu VM.

#### View Logs with Loki

1.  Click the **"Explore"** icon (compass) on the left menu.
2.  At the top, select your **Loki** data source from the dropdown.
3.  In the "Log browser" query field, type `{job="syslog"}` and press Shift+Enter.
4.  You will see the live log stream from your server's `/var/log/syslog` file.

You have now successfully built and validated a complete monitoring stack\!

-----

Would you like a deeper dive into a specific part, such as writing custom Grafana dashboards or setting up alerting with Alertmanager?