#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

echo "--- 0. Create SSH-Key ---"
cd terraform
ssh-keygen -t rsa -b 4096 -f ssh-key -N ""
chmod 400 ssh-key
cd ..

echo "--- 1. Provisioning Infrastructure with Terraform ---"
cd terraform
terraform init
terraform apply -auto-approve
# Get the server IP from terraform output
SERVER_IP=$(terraform output -raw monitoring_server_ip)
cd ..

echo ""
echo "--- 2. Waiting 900 seconds for VMs to initialize SSH ---"
sleep 900

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