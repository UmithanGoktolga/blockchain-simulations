# HPC Mode for Blockchain Simulations

This directory contains the HPC (High Performance Computing) subsystem for running massively parallel blockchain simulations using Apptainer and Slurm.

## Overview

The HPC mode enables running many experiment repetitions in parallel on Slurm using Apptainer containers, while keeping the existing Docker workflow for local development unchanged. Each array index represents one experiment repetition (REPS=1), internally spinning up a local 24-node Geth PoA network with unique port ranges.

## Files

- `geth.def` - Apptainer recipe for Geth + Python environment
- `build_geth_sif.sh` - One-shot SIF builder script
- `start-geth.sh` - Per-repetition network launcher (24 Geth nodes)
- `peering_service.py` - Neighbor→static-nodes hot-reloader
- `array.slurm` - Slurm array job script (80 runs: 4 configs × 20 reps)
- `make_identifiers.py` - Identifiers generator for controllers
- `README-hpc.md` - This documentation

## Quick Start

### 1. Build Container

```bash
cd blockchain-simulations/FloorEstimation
bash hpc/build_geth_sif.sh
```

### 2. Submit to Slurm (Tosun)

**Production run (preferred):**
```bash
sbatch hpc/array.slurm
```

This runs:
- 80 total experiments (byz ∈ {0,2,4,6}, 20 repetitions each)
- Up to 32 concurrent on midst partition
- 16GB memory per task
- Results in `results/experiment_HPC/24rob-<byz>byz/<rep>/`

**Alternative for short_investor partition:**
```bash
sbatch --partition=short_investor --array=0-79%16 hpc/array.slurm
```

### 3. Monitor Progress

```bash
squeue -u $USER
sacct --format=JobID,State,Elapsed,MaxRSS -j <JOBID>
```

Keep MaxRSS < 16G. If healthy, you may increase %32 to %40 on mixed nodes.

## Local Testing (Dry Run)

Test the exact HPC scripts locally with reduced resources:

```bash
cd blockchain-simulations/FloorEstimation

# Build SIF
bash hpc/build_geth_sif.sh

# Set local overrides
export HPC_NUM_NODES=6          # Fewer nodes for low-RAM systems
export HPC_BASE_OFFSET=0        # Simpler ports
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Run single task
sbatch --array=0-0 --mem=8G --cpus-per-task=1 hpc/array.slurm

# Or for local testing without Slurm:
python3 hpc/make_identifiers.py 6 | sed 's/ [0-9.]\+ / 127.0.0.1 /g' | sed 's/ [0-9.]\+$/ 127.0.0.1/' > identifiers.txt
```

**Sanity check:**
```bash
curl -s -X POST http://127.0.0.1:$((8545 + ${HPC_BASE_OFFSET:-0} + 0)) \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"net_peerCount","params":[]}'
```

Expect a hex "0xN" result after the peering service writes static peers.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HPC_NUM_NODES` | 24 | Number of Geth nodes per repetition |
| `HPC_BASE_OFFSET` | 1000×TASK_ID | Port offset for collision avoidance |
| `P2P_BASE` | 30303 | Base P2P port |
| `HTTP_BASE` | 8545 | Base HTTP-RPC port |
| `WS_BASE` | 8546 | Base WebSocket port |
| `NETWORK_ID` | 456719 | Ethereum network ID (matches existing) |

### Port Strategy

For array index A and robot/node index i (0-based):
- **HTTP**: 8545 + 1000×A + i
- **WebSocket**: 8546 + 1000×A + i  
- **P2P**: 30303 + 1000×A + i

This allows up to ~999 parallel array indices on a host without conflicts.

### Array Index → Config Mapping

```bash
byz=(0 2 4 6)
CFG_IDX=$(( SLURM_ARRAY_TASK_ID / 20 ))    # 0..3
REP=$(( SLURM_ARRAY_TASK_ID % 20 + 1 ))    # 1..20
NUMBYZ=${byz[$CFG_IDX]}                    # Byzantine count
```

Examples:
- Task 0: 0 Byzantine, Rep 1
- Task 19: 0 Byzantine, Rep 20  
- Task 20: 2 Byzantine, Rep 1
- Task 79: 6 Byzantine, Rep 20

## Architecture

### HPC Mode vs Docker Mode

| Aspect | Docker Mode | HPC Mode |
|--------|-------------|----------|
| Container | docker-compose | Apptainer SIF |
| Networking | Docker networks | Host networking + unique ports |
| Peering | Helper sockets (9898/9899) | static-nodes.json hot-reload |
| Scaling | Single machine | Massively parallel |
| Development | Local development | Production HPC |

### Workflow

1. **Slurm array job** starts one task per repetition
2. **Apptainer SIF** provides Geth + Python environment  
3. **start-geth.sh** launches 24 Geth nodes with unique ports
4. **peering_service.py** watches `neighbors/robot<i>.json` and updates `static-nodes.json`
5. **ARGoS simulation** runs normally, controllers find blockchain via identifiers.txt
6. **Results collection** copies logs to permanent storage

### Peering Service

The peering service replaces Docker networking by:
- Watching `$SLURM_TMPDIR/ethnet/neighbors/robot<i>.json`
- Accepting either `{peer_id: ip}` or `[peer_id, ...]` formats
- Computing enode URLs via `bootnode -nodekey -writeaddress`
- Writing `static-nodes.json` atomically (`.tmp` → move)
- Hot-reloading on file changes (1s scan interval)

## Integration with Existing Code

### HPC_MODE Toggle

Set `HPC_MODE=1` to skip Docker-specific steps:
- No `docker-compose` commands
- No container attachment
- Keep identical pipeline (same envs, same argos3 call, same collect-logs)

### Controller Changes (Optional)

Controllers can optionally guard legacy socket calls:
```python
if not os.getenv("HPC_MODE"):
    # Legacy helper socket calls (9898/9899/4000)
    pass
```

Not strictly necessary - connection warnings are harmless.

## Troubleshooting

### Common Issues

**Port conflicts:**
- Ensure `HPC_BASE_OFFSET` is unique per concurrent task
- Use `ss -tlnp | grep <port>` to check for conflicts

**Firewall/NAT:**
- Always uses `--nat extip:<host-ip>`
- Prefers static peers over UDP discovery
- Uses `--nodiscover` flag

**Memory limits:**
- Start with %16 concurrent tasks
- Monitor with `sacct --format=MaxRSS`  
- Increase to %32 only when safe

**File permissions:**
- Ensure all scripts in hpc/ are executable
- Check `$SLURM_TMPDIR` write permissions

### Debugging

**Check Geth connectivity:**
```bash
curl -X POST http://<host-ip>:$((8545 + HPC_BASE_OFFSET + i)) \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"net_peerCount","params":[]}'
```

**Check logs:**
```bash
# Slurm logs
tail -f logs/array-<jobid>_<taskid>.out

# Geth logs (if available)
find $SLURM_TMPDIR/ethnet -name "*.log" -exec tail -f {} +
```

**Validate static-nodes.json:**
```bash
find $SLURM_TMPDIR/ethnet/nodes -name "static-nodes.json" -exec cat {} \;
```

## Performance Notes

### Resource Usage
- **Memory**: ~500MB per Geth node + simulation overhead
- **CPU**: Mostly I/O bound, 1 core sufficient
- **Network**: Minimal (localhost communication)
- **Storage**: Use `$SLURM_TMPDIR` for temporary files

### Scaling Guidelines
- **cn18 (512GB)**: Up to 32 concurrent tasks with 24 nodes each
- **256GB nodes**: Up to 16 concurrent tasks recommended  
- **mixed nodes**: Start conservatively, monitor MaxRSS

### I/O Optimization
- All temporary files in `$SLURM_TMPDIR` (local SSD)
- Copy results to permanent storage at end
- Atomic file operations for static-nodes.json

## Differences from Docker Mode

1. **No changes** to consensus parameters (genesis_poa.json, Clique, 15s period)
2. **No changes** to controller logic (except optional HPC_MODE guards)
3. **No changes** to smart contracts or experiment parameters
4. **Different networking**: Host ports instead of Docker networks
5. **Different peering**: File-based instead of socket-based
6. **Different scaling**: Array jobs instead of single container