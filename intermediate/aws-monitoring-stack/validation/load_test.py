import sys
import time
import multiprocessing
import subprocess
import os
import random

# --- Worker Functions ---

def cpu_worker(burn_event, stop_event):
    """
    A process that will either burn 100% CPU or sleep,
    based on the state of the 'burn_event'.
    """
    pid = os.getpid()
    print(f"[CPU Worker {pid}]: Started.")
    try:
        while not stop_event.is_set():
            if burn_event.is_set():
                # High CPU load: busy-wait loop
                _ = 1 * 1 
            else:
                # Low CPU load: sleep to yield the CPU
                time.sleep(0.01)
    except KeyboardInterrupt:
        pass # Handle Ctrl+C
    print(f"[CPU Worker {pid}]: Stopping.")


def memory_worker(chunk_mb, interval_sec, stop_event):
    """
    A process that gradually allocates memory in chunks.
    """
    pid = os.getpid()
    print(f"[MEM Worker {pid}]: Started. Will allocate {chunk_mb}MB every {interval_sec}s.")
    memory_hog = []
    total_allocated = 0
    try:
        while not stop_event.is_set():
            chunk = bytearray(chunk_mb * 1024 * 1024)
            memory_hog.append(chunk)
            total_allocated += chunk_mb
            print(f"[MEM Worker {pid}]: Allocated {chunk_mb}MB. Total RAM held: {total_allocated}MB")
            
            # Sleep until the next interval, checking for stop signal
            sleep_end = time.time() + interval_sec
            while time.time() < sleep_end and not stop_event.is_set():
                time.sleep(0.1)
                
    except MemoryError:
        print(f"[MEM Worker {pid}]: FAILED! Out of memory. Holding {total_allocated}MB.")
        # Keep the process alive to hold the memory
        while not stop_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    print(f"[MEM Worker {pid}]: Stopping. Releasing {total_allocated}MB.")


def log_worker(interval_sec, stop_event):
    """
    A process that continuously generates syslog messages.
    Uses the 'logger' command-line utility.
    """
    pid = os.getpid()
    print(f"[LOG Worker {pid}]: Started. Will log every {interval_sec}s.")
    log_levels = ["INFO", "WARNING", "ERROR"]
    try:
        while not stop_event.is_set():
            # Generate a random log message
            level = random.choice(log_levels)
            message = f"{level}: Dynamic log message from PID {pid}. Value: {random.randint(1000, 9999)}"
            
            # Use 'logger' utility to send to syslog
            try:
                subprocess.run(
                    ["logger", "-t", "LoadTest", message], 
                    check=True,
                    timeout=0.5
                )
            except Exception as e:
                print(f"[LOG Worker {pid}]: Failed to write to logger: {e}")
            
            # Sleep, checking for stop signal
            sleep_end = time.time() + interval_sec
            while time.time() < sleep_end and not stop_event.is_set():
                time.sleep(0.05)

    except KeyboardInterrupt:
        pass
    print(f"[LOG Worker {pid}]: Stopping.")


# --- Main Controller ---

def run_load_test(total_duration_sec):
    print(f"--- Starting Dynamic Load Test for {total_duration_sec} seconds ---")
    
    # Events to control the child processes
    stop_event = multiprocessing.Event()
    cpu_burn_event = multiprocessing.Event()
    
    processes = []
    
    try:
        # 1. Start CPU Workers (one for each core)
        num_cores = multiprocessing.cpu_count()
        print(f"Starting {num_cores} CPU workers...")
        for _ in range(num_cores):
            p = multiprocessing.Process(target=cpu_worker, args=(cpu_burn_event, stop_event))
            p.start()
            processes.append(p)
            
        # 2. Start Memory Worker
        print("Starting 1 Memory worker...")
        p_mem = multiprocessing.Process(target=memory_worker, args=(50, 5, stop_event)) # 50MB every 5s
        p_mem.start()
        processes.append(p_mem)
        
        # 3. Start Log Worker
        print("Starting 1 Log worker...")
        p_log = multiprocessing.Process(target=log_worker, args=(0.5, stop_event)) # Log every 0.5s
        p_log.start()
        processes.append(p_log)
        
        # 4. Run the main control loop
        start_time = time.time()
        while time.time() - start_time < total_duration_sec:
            # CPU WAVE: 20 seconds ON
            print("\n[MAIN]: === Ramping CPU UP! === (20s)")
            cpu_burn_event.set()
            time.sleep(20)
            
            if time.time() - start_time > total_duration_sec:
                break
                
            # CPU WAVE: 10 seconds OFF
            print("\n[MAIN]: === Ramping CPU DOWN. === (10s)")
            cpu_burn_event.clear()
            time.sleep(10)
        
        print("\n[MAIN]: --- Total duration finished. ---")

    except KeyboardInterrupt:
        print("\n[MAIN]: --- Load test interrupted by user. ---")
    
    finally:
        # Stop all child processes
        print("[MAIN]: Sending stop signal to all workers...")
        stop_event.set()
        
        for p in processes:
            p.join(timeout=5) # Wait 5s for graceful stop
            if p.is_alive():
                print(f"[MAIN]: Process {p.pid} did not exit, terminating...")
                p.terminate()
                p.join()
                
        print("[MAIN]: --- Load Test Complete. ---")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 load_test.py <duration_in_seconds>")
        sys.exit(1)
    
    try:
        duration = int(sys.argv[1])
    except ValueError:
        print("Error: Duration must be an integer.")
        sys.exit(1)
        
    run_load_test(duration)

