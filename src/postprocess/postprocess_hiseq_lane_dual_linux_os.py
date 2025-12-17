#!/usr/bin/env python3
import sys
import os
import subprocess

def main():
    # Check for OS release file
    os_name = "unknown"
    if os.path.isfile("/etc/os-release"):
        with open("/etc/os-release", "r") as f:
            for line in f:
                if line.startswith("ID="):
                    os_name = line.strip().split("=")[1].strip('"')
                    break
    
    print(f"Detected OS: {os_name}")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    args = sys.argv[1:]
    
    if os_name == 'ubuntu':
        print("Run Ubuntu script")
        script_name = "postprocess_hiseq_lane_ubuntu_22_04_test_gzip.py"
        script_path = os.path.join(script_dir, script_name)
        print(f"{script_name} {' '.join(args)}")
        
        cmd = [sys.executable, script_path] + args
        subprocess.run(cmd, check=True)
        
    elif os_name == 'centos':
        print("Run Centos script")
        script_name = "postprocess_hiseq_lane_centos7_test_gzip.py"
        script_path = os.path.join(script_dir, script_name)
        print(f"{script_name} {' '.join(args)}")
        
        cmd = [sys.executable, script_path] + args
        subprocess.run(cmd, check=True)
        
    else:
        print("Unknown OS")

if __name__ == "__main__":
    main()
