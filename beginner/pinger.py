import paramiko
import time




# IP address of the DESTINATION router (as seen from the source router)
DESTINATION_ROUTER_IP = '192.168.1.2' # Example: The IP of the link
PING_PACKET_COUNT = 5

# --------------------------

def run_srl_ping(host, port, user, password, destination_ip, count):
    """
    Connects to an SR Linux router via SSH and executes a ping command.
    """
    print(f"Attempting to connect to {user}@{host}:{port}...")
    
    ssh_client = paramiko.SSHClient()
    # Automatically add host key (convenient for labs, less secure for prod)
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        ssh_client.connect(hostname=host,
                           port=port,
                           username=user,
                           password=password,
                           timeout=10,
                           allow_agent=False,
                           look_for_keys=False)
        
        print(f"Successfully connected to {host}:{port}")
        
        # Construct the ping command for SR Linux
        command = f"ping {destination_ip} count {count}"
        print(f"Executing command: '{command}'\n")
        
        # Execute the command
        stdin, stdout, stderr = ssh_client.exec_command(command)
        
        # Wait for the command to complete (ping needs time)
        # A simple sleep is often easiest for short commands.
        # For 5 packets at 1s interval, 6-7s should be enough.
        time.sleep(count + 2) 
        
        # Read the output
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')
        
        print("--- Ping Results ---")
        if output:
            print(output)
        else:
            print("[No standard output received]")
            
        if error:
            print("\n--- Errors ---")
            print(error)

    except paramiko.AuthenticationException:
        print(f"Authentication failed for {user}@{host}:{port}. Check username/password.")
    except paramiko.SSHException as e:
        print(f"SSH connection error: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    finally:
        # Ensure the connection is closed
        if ssh_client.get_transport() and ssh_client.get_transport().is_active():
            print(f"\nClosing connection to {host}:{port}")
            ssh_client.close()

if __name__ == "__main__":
    # Before running, make sure paramiko is installed:
    # pip install paramiko
    # --- User Configuration ---
    # !! Update these variables to match your Containerlab setup !!
    data = [
        {"src_ip": "clab-topo-srlHamburg", "src_port": 22, "username": "admin", "password": "admin", "dst1":"30.1.1.2","dst2":"10.1.1.1"},
        {"src_ip": "clab-topo-srlFrankfurt", "src_port": 22, "username": "admin", "password": "admin", "dst1":"30.1.1.1","dst2":"20.1.1.2"},
        {"src_ip": "clab-topo-srlCologne", "src_port": 22, "username": "admin", "password": "admin", "dst1":"10.1.1.2","dst2":"20.1.1.1"},
    ]
    for d in data:
        run_srl_ping(d["src_ip"],d["src_port"],d["username"],d["password"],d["dst1"],PING_PACKET_COUNT)
        run_srl_ping(d["src_ip"],d["src_port"],d["username"],d["password"],d["dst2"],PING_PACKET_COUNT)