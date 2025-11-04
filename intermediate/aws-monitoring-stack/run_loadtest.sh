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
