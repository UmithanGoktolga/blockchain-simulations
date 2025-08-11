#!/usr/bin/env python3
"""
Generate identifiers.txt for HPC blockchain simulations.
Usage: python3 hpc/make_identifiers.py N > identifiers.txt
"""

import sys
import subprocess


def get_host_ip():
    """Get the host IP address."""
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        return result.stdout.strip().split()[0]
    except subprocess.CalledProcessError:
        return '127.0.0.1'


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 hpc/make_identifiers.py N", file=sys.stderr)
        print("Example: python3 hpc/make_identifiers.py 24", file=sys.stderr)
        sys.exit(1)
    
    try:
        n = int(sys.argv[1])
    except ValueError:
        print("Error: N must be an integer", file=sys.stderr)
        sys.exit(1)
    
    if n <= 0:
        print("Error: N must be positive", file=sys.stderr)
        sys.exit(1)
    
    host_ip = get_host_ip()
    
    print("# robotID IP IP_DOCKER")
    for i in range(n):
        print(f"{i} {host_ip} {host_ip}")


if __name__ == '__main__':
    main()