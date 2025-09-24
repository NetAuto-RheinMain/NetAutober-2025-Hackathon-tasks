#!/usr/bin/env bash
set -eux

echo "🔧 Updating system..."
sudo apt-get update -y
sudo apt-get install -y \
  unzip jq curl wget python3-pip git \
  software-properties-common gnupg lsb-release \
  apt-transport-https ca-certificates

# ------------------------------------------------------------------------------
# Terraform
# ------------------------------------------------------------------------------
TERRAFORM_VERSION=1.9.8
echo "🌍 Installing Terraform ${TERRAFORM_VERSION}..."
curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o /tmp/terraform.zip
sudo unzip -o /tmp/terraform.zip -d /usr/local/bin
rm -f /tmp/terraform.zip
terraform -version

# ------------------------------------------------------------------------------
# AWS CLI
# ------------------------------------------------------------------------------
echo "☁️ Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip
aws --version

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------
echo "🐳 Installing Docker..."
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable docker || true
docker --version
docker compose version

# ------------------------------------------------------------------------------
# Podman
# ------------------------------------------------------------------------------
echo "🍺 Installing Podman..."
. /etc/os-release
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -L "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | sudo apt-key add -
sudo apt-get update -y
sudo apt-get install -y podman podman-compose
podman --version
podman-compose version

# ------------------------------------------------------------------------------
# Ansible
# ------------------------------------------------------------------------------
echo "⚙️ Installing Ansible..."
sudo apt-get install -y ansible
ansible --version

# ------------------------------------------------------------------------------
# Python dependencies
# ------------------------------------------------------------------------------
echo "🐍 Installing Python packages..."
pip3 install --upgrade pip
pip3 install boto3 docker podman-py requests

# ------------------------------------------------------------------------------
# ✅ Final verification
# ------------------------------------------------------------------------------
echo "🔍 Verifying installs..."
terraform -version
aws --version
docker --version
docker compose version
podman --version
ansible --version
python3 --version
pip3 show boto3 docker podman-py | grep "Name" || true

echo "✅ Intermediate devcontainer setup complete and verified!"
