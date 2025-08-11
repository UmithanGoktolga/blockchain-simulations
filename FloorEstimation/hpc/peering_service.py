#!/usr/bin/env python3
"""
Peering service for HPC blockchain simulations.
Watches neighbors/robot<i>.json files and hot-reloads static-nodes.json
based on the controller's RAB-eligible neighbor sets.
"""

import json
import os
import subprocess
import time
import sys
from pathlib import Path
import tempfile

class PeeringService:
    def __init__(self, workdir, sif_path, num_nodes=24, base_offset=0, p2p_base=30303):
        self.workdir = Path(workdir)
        self.sif_path = sif_path
        self.num_nodes = num_nodes
        self.base_offset = base_offset
        self.p2p_base = p2p_base
        
        self.neighbors_dir = self.workdir / "neighbors"
        self.nodes_dir = self.workdir / "nodes"
        self.nodekeys_dir = self.workdir / "nodekeys"
        
        # Cache for node public keys
        self.pubkey_cache = {}
        
        # Get host IP
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
        self.host_ip = result.stdout.strip().split()[0]
        
        print(f"PeeringService initialized:")
        print(f"  Working dir: {self.workdir}")
        print(f"  Neighbors dir: {self.neighbors_dir}")
        print(f"  Nodes: {self.num_nodes}")
        print(f"  Host IP: {self.host_ip}")
    
    def get_node_pubkey(self, node_id):
        """Get the public key for a node using bootnode -nodekey"""
        if node_id in self.pubkey_cache:
            return self.pubkey_cache[node_id]
        
        nodekey_file = self.nodekeys_dir / f"nodekey.{node_id}"
        if not nodekey_file.exists():
            print(f"Warning: nodekey file {nodekey_file} not found")
            return None
        
        try:
            # Use bootnode to get public key from private key
            cmd = ['apptainer', 'exec', self.sif_path, 'bootnode', 
                   '-nodekey', str(nodekey_file), '-writeaddress']
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                pubkey = result.stdout.strip()
                self.pubkey_cache[node_id] = pubkey
                return pubkey
            else:
                print(f"Error getting pubkey for node {node_id}: {result.stderr}")
                return None
        except Exception as e:
            print(f"Exception getting pubkey for node {node_id}: {e}")
            return None
    
    def create_enode_url(self, peer_id, ip=None):
        """Create enode URL for a peer"""
        if ip is None:
            ip = self.host_ip
        
        pubkey = self.get_node_pubkey(peer_id)
        if pubkey is None:
            return None
        
        p2p_port = self.p2p_base + self.base_offset + peer_id
        enode = f"enode://{pubkey}@{ip}:{p2p_port}"
        return enode
    
    def parse_neighbors_file(self, neighbors_file):
        """Parse neighbors file - supports dict {peer_id: ip} or list [peer_id,...]"""
        try:
            with open(neighbors_file, 'r') as f:
                data = json.load(f)
            
            neighbors = []
            
            if isinstance(data, dict):
                # Dict format: {peer_id: ip}
                for peer_id_str, ip in data.items():
                    try:
                        peer_id = int(peer_id_str)
                        if 0 <= peer_id < self.num_nodes:
                            neighbors.append((peer_id, ip))
                    except (ValueError, TypeError):
                        continue
            elif isinstance(data, list):
                # List format: [peer_id, ...] (assume host IP)
                for peer_id in data:
                    try:
                        peer_id = int(peer_id)
                        if 0 <= peer_id < self.num_nodes:
                            neighbors.append((peer_id, self.host_ip))
                    except (ValueError, TypeError):
                        continue
            
            return neighbors
            
        except Exception as e:
            print(f"Error parsing {neighbors_file}: {e}")
            return []
    
    def update_static_nodes(self, node_id, neighbors):
        """Update static-nodes.json for a node"""
        static_nodes_file = self.nodes_dir / f"node{node_id}" / "geth" / "static-nodes.json"
        
        # Create enode URLs for neighbors
        enodes = []
        for peer_id, ip in neighbors:
            enode = self.create_enode_url(peer_id, ip)
            if enode:
                enodes.append(enode)
        
        # Write to temporary file first, then move (atomic update)
        try:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, 
                                           dir=static_nodes_file.parent, 
                                           suffix='.tmp') as tmp_file:
                json.dump(enodes, tmp_file, indent=2)
                tmp_file.flush()
                os.fsync(tmp_file.fileno())
            
            # Atomic move
            os.rename(tmp_file.name, static_nodes_file)
            print(f"Updated static-nodes.json for node {node_id} with {len(enodes)} peers")
            
        except Exception as e:
            print(f"Error updating static-nodes.json for node {node_id}: {e}")
            # Clean up temp file if it exists
            try:
                if 'tmp_file' in locals():
                    os.unlink(tmp_file.name)
            except:
                pass
    
    def run(self):
        """Main service loop"""
        print("Starting peering service...")
        
        # Create neighbors directory if it doesn't exist
        self.neighbors_dir.mkdir(parents=True, exist_ok=True)
        
        # Track last modification times
        last_mtimes = {}
        
        while True:
            try:
                # Check for neighbor files
                for i in range(self.num_nodes):
                    neighbors_file = self.neighbors_dir / f"robot{i}.json"
                    
                    if neighbors_file.exists():
                        try:
                            current_mtime = neighbors_file.stat().st_mtime
                            
                            # Check if file has been modified
                            if (neighbors_file not in last_mtimes or 
                                current_mtime > last_mtimes[neighbors_file]):
                                
                                print(f"Processing updated neighbors file: {neighbors_file}")
                                neighbors = self.parse_neighbors_file(neighbors_file)
                                self.update_static_nodes(i, neighbors)
                                last_mtimes[neighbors_file] = current_mtime
                                
                        except Exception as e:
                            print(f"Error processing {neighbors_file}: {e}")
                
                # Sleep before next scan
                time.sleep(1)
                
            except KeyboardInterrupt:
                print("\nPeering service stopped.")
                break
            except Exception as e:
                print(f"Unexpected error in peering service: {e}")
                time.sleep(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 peering_service.py <workdir> [sif_path] [num_nodes] [base_offset]")
        sys.exit(1)
    
    workdir = sys.argv[1]
    sif_path = sys.argv[2] if len(sys.argv) > 2 else "hpc/geth.sif"
    num_nodes = int(sys.argv[3]) if len(sys.argv) > 3 else 24
    base_offset = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    
    service = PeeringService(workdir, sif_path, num_nodes, base_offset)
    service.run()

if __name__ == "__main__":
    main()