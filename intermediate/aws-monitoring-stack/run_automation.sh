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
echo "--- 2. Waiting 300 seconds for VMs to initialize SSH ---"
sleep 30
echo "--- 2.1. 30 seconds ---"
sleep 30
echo "--- 2.1. 60 seconds ---"
sleep 30
echo "--- 2.1. 90 seconds ---"
sleep 30
echo "--- 2.1. 120 seconds ---"
sleep 30
echo "--- 2.1. 150 seconds ---"
sleep 30
echo "--- 2.1. 180 seconds ---"
sleep 30
echo "--- 2.1. 210 seconds ---"
sleep 30
echo "--- 2.1. 240 seconds ---"
sleep 30
echo "--- 2.1. 270 seconds ---"
sleep 30
echo "--- 2.1. 300 seconds ---"

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