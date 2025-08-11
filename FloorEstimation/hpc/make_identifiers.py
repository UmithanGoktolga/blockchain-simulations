#!/usr/bin/env python3
"""
Generate identifiers.txt for blockchain controllers in HPC mode.
This script creates a mapping of robot IDs to host IP addresses.
"""

import sys
import subprocess

def get_host_ip():
    """Get the primary IP address of the host"""
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        return result.stdout.strip().split()[0]
    except subprocess.CalledProcessError:
        # Fallback method
        try:
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} N")
        print("Generates identifiers.txt with N robot entries pointing to host IP")
        sys.exit(1)
    
    try:
        n = int(sys.argv[1])
        if n <= 0:
            raise ValueError("N must be positive")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    host_ip = get_host_ip()
    
    # Generate identifiers in the format expected by controllers
    for i in range(n):
        print(f"{i}\t{host_ip}")

if __name__ == "__main__":
    main()