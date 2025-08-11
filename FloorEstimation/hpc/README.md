# HPC Subsystem for Massively Parallel Blockchain Simulations

This directory contains the HPC infrastructure for running blockchain-based robot swarm experiments in parallel on Slurm clusters using Apptainer (Singularity). Each array job runs one experiment repetition with a local 24-node Geth PoA network.

## Overview

The HPC mode runs many experiment repetitions in parallel while keeping the existing Docker workflow for local development unchanged. Each Slurm array task:

1. Spins up a local 24-node Geth PoA network (one node per robot)
2. Uses a lightweight peering service to update `static-nodes.json` based on neighbor sets
3. Runs one ARGoS simulation repetition (`REPS=1`)
4. Collects logs and results automatically

## Files

### Core Components

- **`geth.def`** - Apptainer recipe (Ubuntu 22.04 + geth + Python tools)
- **`build_geth_sif.sh`** - One-shot SIF builder script
- **`start-geth.sh`** - Per-repetition network launcher (24 geth nodes)
- **`peering_service.py`** - Hot-reloads `static-nodes.json` from neighbor files
- **`array.slurm`** - Slurm array job for 80 repetitions (4 configs × 20 reps)
- **`make_identifiers.py`** - Generates `identifiers.txt` for controllers

### Configuration

Default settings (can be overridden via environment):

- `HPC_NUM_NODES=24` - Number of geth nodes per repetition
- `HPC_BASE_OFFSET=1000*SLURM_ARRAY_TASK_ID` - Port offset for isolation
- Ports: P2P=30303+offset+i, HTTP=8545+offset+i, WS=8546+offset+i
- Network ID: 456719 (matches existing setup)
- Genesis: Clique PoA with 15s block period

## Quick Start

### 1. Local Testing (Dry Run)

Test the HPC scripts locally without Slurm:

```bash
# Build the SIF file
cd FloorEstimation/hpc
./build_geth_sif.sh

# Test network launcher (in a temporary directory)
mkdir -p /tmp/test_hpc
export SLURM_TMPDIR=/tmp/test_hpc
export SLURM_ARRAY_TASK_ID=0
./start-geth.sh &

# Test peering service
python3 peering_service.py /tmp/test_hpc hpc/geth.sif 24 0 &

# Test identifiers generator
python3 make_identifiers.py 24
```

### 2. Slurm Cluster (Production)

Submit the array job for 80 repetitions:

```bash
cd FloorEstimation
mkdir -p logs  # Required for Slurm output

# Submit array job
sbatch hpc/array.slurm

# Monitor progress
squeue -u $USER
sacct -j JOBID

# Check results
ls -la results/experiment_hpc/24rob-*byz/
```

## Experimental Configuration

The array job maps 80 tasks to experimental conditions:

- **Byzantine nodes**: 0, 2, 4, 6 (4 configurations)
- **Repetitions**: 20 per configuration
- **Mapping**: 
  - Tasks 0-19: 0 Byzantine nodes, reps 1-20
  - Tasks 20-39: 2 Byzantine nodes, reps 1-20  
  - Tasks 40-59: 4 Byzantine nodes, reps 1-20
  - Tasks 60-79: 6 Byzantine nodes, reps 1-20

## Port Allocation

Each array task uses unique port ranges to avoid conflicts:

- Base offset: `1000 * SLURM_ARRAY_TASK_ID`
- Node i ports:
  - P2P: `30303 + base_offset + i`
  - HTTP: `8545 + base_offset + i` 
  - WebSocket: `8546 + base_offset + i`

Examples:
- Task 0: ports 30303-30326, 8545-8568, 8546-8569
- Task 1: ports 31303-31326, 9545-9568, 9546-9569

## Peering Service

The peering service watches `$SLURM_TMPDIR/ethnet/neighbors/robot<i>.json` files written by controllers and updates each node's `static-nodes.json` accordingly.

Supported neighbor file formats:

1. **Dictionary**: `{"0": "192.168.1.10", "5": "192.168.1.11"}`
2. **List**: `[0, 5, 12]` (assumes host IP)

The service generates enode URLs using deterministic nodekeys and performs atomic updates.

## Resource Requirements

### Default (per task)
- **Memory**: 16 GB
- **CPU**: 1 core
- **Time**: 4 hours
- **Partition**: `midst` (Tosun cn18 nodes)

### Concurrent Limits
- **Maximum parallel**: 32 tasks (`--array=0-79%32`)
- Supports cn18 nodes (512 GB) or 256 GB nodes

## Directory Structure

```
FloorEstimation/hpc/
├── geth.def                 # Apptainer recipe
├── build_geth_sif.sh        # SIF builder
├── geth.sif                 # Built container (generated)
├── start-geth.sh            # Network launcher
├── peering_service.py       # Neighbor hot-reload service
├── array.slurm              # Slurm array job
├── make_identifiers.py      # Identifiers generator
└── README.md                # This file

# Runtime (per task)
$SLURM_TMPDIR/ethnet/
├── nodes/node{0..23}/geth/  # Geth datadirs
├── nodekeys/nodekey.{0..23} # Node private keys
├── neighbors/robot{0..23}.json  # Written by controllers
├── geth.{0..23}.log         # Geth logs
└── identifiers.txt          # Robot ID → IP mapping
```

## Results Collection

Results are automatically collected to:
```
results/experiment_$SLURM_JOB_NAME/24rob-{0,2,4,6}byz/{1..20}/
├── experimentconfig.sh      # Configuration used
├── loop_params.py           # Loop function parameters  
├── control_params.py        # Controller parameters
├── {1..24}/geth.*.log       # Geth logs per node
└── [other ARGoS logs]       # Standard experiment logs
```

## Troubleshooting

### Common Issues

1. **SIF build fails**: Check Apptainer installation and permissions
2. **Port conflicts**: Verify `HPC_BASE_OFFSET` calculation
3. **Genesis mismatch**: Ensure `genesis_poa.json` exists with correct chain ID
4. **Node startup**: Check geth logs in `$SLURM_TMPDIR/ethnet/`

### Debug Commands

```bash
# Check running nodes
ps aux | grep geth

# View geth logs  
tail -f $SLURM_TMPDIR/ethnet/geth.0.log

# Test container
apptainer exec hpc/geth.sif geth version

# Check neighbors
ls -la $SLURM_TMPDIR/ethnet/neighbors/
cat $SLURM_TMPDIR/ethnet/neighbors/robot0.json

# Verify static-nodes
cat $SLURM_TMPDIR/ethnet/nodes/node0/geth/static-nodes.json
```

## Compatibility

- **Slurm**: Compatible with standard Slurm installations
- **Apptainer**: Requires Apptainer/Singularity 1.0+
- **Operating System**: Linux (tested on CentOS/RHEL/Ubuntu)
- **Architecture**: x86_64

## Local Development

The existing Docker workflow remains unchanged. Use this HPC mode only for large-scale parallel experiments on clusters.

For local development, continue using:
```bash
cd FloorEstimation
source experimentconfig.sh
./starter -r -s
```