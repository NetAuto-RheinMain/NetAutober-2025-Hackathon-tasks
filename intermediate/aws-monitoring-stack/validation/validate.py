import sys
import requests
import time

def check_prometheus(ip):
    print(f"--- Checking Prometheus (http://{ip}:9090) ---")
    try:
        url = f"http://{ip}:9090/api/v1/targets"
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        targets = data.get('data', {}).get('activeTargets', [])
        
        if not targets:
            print("❌ FAILURE: No active targets found in Prometheus.")
            return False

        print(f"Found {len(targets)} active targets:")
        all_up = True
        for target in targets:
            job = target.get('scrapePool')
            health = target.get('health')
            print(f"  > Target: {job} | Health: {health}")
            if health != "up":
                all_up = False
        
        if all_up:
            print("✅ SUCCESS: All Prometheus targets are 'up'.")
            return True
        else:
            print("❌ FAILURE: Not all Prometheus targets are 'up'.")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ FAILURE: Could not connect to Prometheus: {e}")
        return False

def check_loki(ip):
    print(f"\n--- Checking Loki (http://{ip}:3100) ---")
    try:
        # Give Promtail a few seconds to send its first logs
        print("Waiting 15s for logs to arrive in Loki...")
        time.sleep(15)

        url = f"http://{ip}:3100/loki/api/v1/labels"
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        labels = data.get('data', [])
        
        if 'job' in labels:
            print("✅ SUCCESS: Loki API is responding and reports 'job' label.")
            
            # Bonus check: query for actual logs
            query_url = f"http://{ip}:3100/loki/api/v1/query"
            params = {'query': '{job="syslog"}'}
            query_response = requests.get(query_url, params=params, timeout=10)
            query_data = query_response.json()
            
            if query_data.get('data', {}).get('result', []):
                print("✅ SUCCESS: Found actual log streams for job='syslog'.")
                return True
            else:
                print("❌ FAILURE: Loki is up, but no log streams found for job='syslog'.")
                return False
        else:
            print("❌ FAILURE: Loki API did not return expected labels.")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ FAILURE: Could not connect to Loki: {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python validate.py <monitoring_server_ip>")
        sys.exit(1)
        
    server_ip = sys.argv[1]
    
    print(f"Starting validation against server: {server_ip}...\n")
    
    # Retry logic for connecting, as services might be starting
    max_retries = 5
    delay = 10
    
    for attempt in range(max_retries):
        print(f"--- Attempt {attempt + 1}/{max_retries} ---")
        prom_ok = check_prometheus(server_ip)
        loki_ok = False
        if prom_ok: # Only check loki if prometheus is reachable
             loki_ok = check_loki(server_ip)
        
        if prom_ok and loki_ok:
            print("\n==========================")
            print("🎉 Validation Complete: All services are UP and receiving data!")
            print("==========================")
            sys.exit(0)
            
        print(f"\nRetrying in {delay} seconds...")
        time.sleep(delay)

    print("\n==========================")
    print("🔥 Validation Failed after all attempts.")
    print("==========================")
    sys.exit(1)

if __name__ == "__main__":
    main()