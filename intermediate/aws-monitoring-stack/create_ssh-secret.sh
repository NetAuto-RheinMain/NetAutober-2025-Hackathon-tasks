#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

echo "--- 0. Create SSH-Key ---"
cd terraform
ssh-keygen -t rsa -b 4096 -f ssh-key -N ""
chmod 400 ssh-key
cd ..