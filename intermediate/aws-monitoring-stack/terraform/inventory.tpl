[monitoring_server]
server ansible_host=${monitoring_server_ip}

[monitored_client]
client ansible_host=${monitored_client_ip}

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=${ssh_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'