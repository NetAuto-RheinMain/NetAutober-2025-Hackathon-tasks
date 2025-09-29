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
# Containerlab
# ------------------------------------------------------------------------------
echo "🛰 Installing Containerlab..."
bash -c "$(curl -sL https://get.containerlab.dev)"
containerlab version

# ------------------------------------------------------------------------------
# Ansible
# ------------------------------------------------------------------------------
echo "⚙️ Installing Ansible..."
sudo apt-get install -y ansible
ansible --version

# ------------------------------------------------------------------------------
# Custom Ansible Collection (SR Linux plugin)
# ------------------------------------------------------------------------------
echo "📚 Installing SR Linux Ansible Collection into project directory..."
mkdir -p /workspaces/.ansible/collections/ansible_collections/nokia
git clone https://github.com/NetOpsChic/srlinux-ansible-collection.git /workspaces/.ansible/collections/ansible_collections/nokia/srlinux

# Create ansible.cfg pointing to both local and global collection paths
cat <<EOF > /workspaces/ansible.cfg
[defaults]
collections_path = .:~/.ansible/collections
host_key_checking = False
retry_files_enabled = False
EOF

# Verify collection is visible
ANSIBLE_CONFIG=/workspaces/ansible.cfg ansible-galaxy collection list | grep srlinux || true

# ------------------------------------------------------------------------------
# Python dependencies
echo "🐍 Installing Python packages..."
pip3 install --upgrade pip --break-system-packages
pip3 install requests netmiko pytest --break-system-packages

# ------------------------------------------------------------------------------
# ✅ Final verification
# ------------------------------------------------------------------------------
echo "🔍 Verifying installs..."
terraform -version
containerlab version
ansible --version
python3 --version
pip3 show requests netmiko | grep "Name" || true

echo "✅ Beginner devcontainer setup complete and verified!"
