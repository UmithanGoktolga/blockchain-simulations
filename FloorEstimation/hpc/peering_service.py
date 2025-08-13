#!/usr/bin/env python3
"""
Peering service for HPC blockchain simulations.
Watches neighbors/robot<i>.json files and hot-reloads static-nodes.json.
"""

import json
import os
import subprocess
import time
import sys
from pathlib import Path


def get_host_ip():
    """Get the host IP address."""
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        return result.stdout.strip().split()[0]
    except subprocess.CalledProcessError:
        return '127.0.0.1'


def get_enode_address(nodekey_path):
    """Get the public key/enode address for a given nodekey file."""
    try:
        # Try using bootnode from container if available
        result = subprocess.run([
            'apptainer', 'exec', os.environ.get('SIF', 'hpc/geth.sif'),
            'bootnode', '-nodekey', nodekey_path, '-writeaddress'
        ], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback: try direct bootnode command
        try:
            result = subprocess.run([
                'bootnode', '-nodekey', nodekey_path, '-writeaddress'
            ], capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"Error getting enode address for {nodekey_path}: {e}")
            return None


def build_enode_url(peer_id, host_ip, p2p_base, base_offset):
    """Build enode URL for a peer."""
    nodekey_path = f"{WORKDIR}/nodekeys/nodekey.{peer_id}"
    if not os.path.exists(nodekey_path):
        return None
    
    public_key = get_enode_address(nodekey_path)
    if not public_key:
        return None
    
    p2p_port = p2p_base + base_offset + peer_id
    return f"enode://{public_key}@{host_ip}:{p2p_port}"


def parse_neighbors_file(filepath):
    """Parse neighbors file - handle both dict and list formats."""
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        
        if isinstance(data, dict):
            # Format: {peer_id: ip, ...}
            return [(int(peer_id), ip) for peer_id, ip in data.items()]
        elif isinstance(data, list):
            # Format: [peer_id, ...]
            host_ip = get_host_ip()
            return [(int(peer_id), host_ip) for peer_id in data]
        else:
            print(f"Warning: Unexpected format in {filepath}")
            return []
    except (json.JSONDecodeError, FileNotFoundError, ValueError) as e:
        print(f"Error parsing {filepath}: {e}")
        return []


def update_static_nodes(robot_id, peers, p2p_base, base_offset):
    """Update static-nodes.json for a specific robot."""
    static_nodes_path = f"{WORKDIR}/nodes/node{robot_id}/geth/static-nodes.json"
    
    # Build enode URLs for peers
    enodes = []
    for peer_id, peer_ip in peers:
        enode = build_enode_url(peer_id, peer_ip, p2p_base, base_offset)
        if enode:
            enodes.append(enode)
    
    # Write to temporary file then move (atomic operation)
    temp_path = static_nodes_path + '.tmp'
    try:
        os.makedirs(os.path.dirname(static_nodes_path), exist_ok=True)
        with open(temp_path, 'w') as f:
            json.dump(enodes, f, indent=2)
        os.rename(temp_path, static_nodes_path)
        print(f"Updated static-nodes.json for robot {robot_id} with {len(enodes)} peers")
    except Exception as e:
        print(f"Error updating static-nodes.json for robot {robot_id}: {e}")
        if os.path.exists(temp_path):
            os.remove(temp_path)


def main():
    global WORKDIR
    
    # Configuration from environment
    WORKDIR = os.environ.get('SLURM_TMPDIR', '/tmp') + '/ethnet'
    HPC_NUM_NODES = int(os.environ.get('HPC_NUM_NODES', '24'))
    HPC_BASE_OFFSET = int(os.environ.get('HPC_BASE_OFFSET', str(1000 * int(os.environ.get('SLURM_ARRAY_TASK_ID', '0')))))
    P2P_BASE = int(os.environ.get('P2P_BASE', '30303'))
    
    neighbors_dir = f"{WORKDIR}/neighbors"
    
    print(f"Starting peering service")
    print(f"Working directory: {WORKDIR}")
    print(f"Watching neighbors in: {neighbors_dir}")
    print(f"Number of nodes: {HPC_NUM_NODES}")
    print(f"Base offset: {HPC_BASE_OFFSET}")
    
    # Track file modification times
    file_mtimes = {}
    
    try:
        while True:
            # Check for neighbor files
            if os.path.exists(neighbors_dir):
                for i in range(HPC_NUM_NODES):
                    neighbors_file = f"{neighbors_dir}/robot{i}.json"
                    
                    if os.path.exists(neighbors_file):
                        try:
                            current_mtime = os.path.getmtime(neighbors_file)
                            
                            # Check if file has changed
                            if neighbors_file not in file_mtimes or file_mtimes[neighbors_file] != current_mtime:
                                file_mtimes[neighbors_file] = current_mtime
                                
                                # Parse neighbors and update static-nodes.json
                                peers = parse_neighbors_file(neighbors_file)
                                if peers:
                                    update_static_nodes(i, peers, P2P_BASE, HPC_BASE_OFFSET)
                        except OSError as e:
                            print(f"Error checking {neighbors_file}: {e}")
            
            # Sleep between scans
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("Peering service stopped")
    except Exception as e:
        print(f"Peering service error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()