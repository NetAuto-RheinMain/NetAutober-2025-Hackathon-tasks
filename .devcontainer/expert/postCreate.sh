#!/usr/bin/env bash
set -eux

echo "🔧 Updating system..."
sudo apt-get update -y

echo "📦 Installing core packages..."
sudo apt-get install -y unzip jq yq curl python3-pip software-properties-common gnupg lsb-release apt-transport-https ca-certificates

# Terraform
TERRAFORM_VERSION=1.9.8
echo "🌍 Installing Terraform ${TERRAFORM_VERSION}..."
curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o /tmp/terraform.zip
sudo unzip -o /tmp/terraform.zip -d /usr/local/bin
rm -f /tmp/terraform.zip
terraform -version

# AWS CLI
echo "☁️ Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip
aws --version

# kubectl
KUBECTL_VERSION=v1.30.0
echo "🔑 Installing kubectl ${KUBECTL_VERSION}..."
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
kubectl version --client

# Helm
echo "⎈ Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
sudo chmod +x /usr/local/bin/helm
sudo chown root:root /usr/local/bin/helm
helm version

# k3d (lightweight k3s in Docker, great for Codespaces)
echo "🐋 Installing k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
k3d version

# Create a default k3d cluster (single server, no agents)
echo "🚀 Creating k3d cluster..."
k3d cluster create dev --wait
kubectl cluster-info
kubectl get nodes

# Ansible
echo "⚙️ Installing Ansible..."
sudo apt-get install -y ansible
ansible --version

echo "📚 Installing Ansible collections..."
ansible-galaxy collection install kubernetes.core

# Python deps
echo "🐍 Installing Python packages..."
pip3 install --upgrade pip --break-system-packages
pip3 install boto3 kubernetes kubernetes-validate --break-system-packages

# ✅ Final confirmation
echo "🔍 Verifying installs..."
terraform -version
aws --version
kubectl version --client
helm version
k3d version
ansible --version
python3 --version
pip3 show boto3 kubernetes

echo "✅ Devcontainer setup complete and verified!"
