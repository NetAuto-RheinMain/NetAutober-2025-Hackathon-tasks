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