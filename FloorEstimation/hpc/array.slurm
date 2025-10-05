#!/usr/bin/env bash
#SBATCH -J geth-net
# #SBATCH -p midst                           # uncomment on Tosun
#SBATCH --array=0-79%32
#SBATCH --mem=12G
#SBATCH -c 1
#SBATCH -o logs/%x-%j_%a.out
#SBATCH -e logs/%x-%j_%a.err

set -euoxo pipefail

# -------- resolve repo paths from where sbatch was invoked (NOT spool) --------
BASE_DIR="${SLURM_SUBMIT_DIR:-$PWD}"        # e.g., .../blockchain-simulations/FloorEstimation
FLOOR="$(realpath "$BASE_DIR")"
HPC="$FLOOR/hpc"
ROOT="$(realpath "$FLOOR/..")"
LOG_DIR="$FLOOR/logs"
mkdir -p "$LOG_DIR"

# Thread hygiene
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Defaults (override via env if needed)
export SIF="${SIF:-$HPC/geth.sif}"
export GENESIS_JSON="${GENESIS_JSON:-$ROOT/argos-blockchain/geth/files/genesis_poa.json}"
export HPC_NUM_NODES="${HPC_NUM_NODES:-5}"    # Changed from 12 to 5 to match our config
export HPC_BASE_OFFSET="${HPC_BASE_OFFSET:-$(( 1000 * ${SLURM_ARRAY_TASK_ID:-0} ))}"
export NETWORK_ID="${NETWORK_ID:-456719}"
export P2P_BASE="${P2P_BASE:-30303}"
export HTTP_BASE="${HTTP_BASE:-8545}"
export WS_BASE="${WS_BASE:-8546}"
export HPC_MODE=1
export GETH_HOST=${GETH_HOST:-127.0.0.1}
export GETH_HTTP_PORT=${HTTP_BASE}
export GETH_WS_PORT=${WS_BASE}


# Modules (no-op if not available)
module load apptainer 2>/dev/null || true

# Build SIF if missing (use absolute paths)
if [ ! -f "$SIF" ]; then
  echo "[array] building SIF → $SIF"
  bash "$HPC/build_geth_sif.sh"
fi

# Work in the submit dir so relative paths (e.g., experiments/, logs/) make sense
cd "$FLOOR"


# Prepare per-task working dirs on fast tmp
export WORKDIR="${SLURM_TMPDIR:-/tmp}/ethnet"
mkdir -p "$WORKDIR" "$WORKDIR/nodes" "$WORKDIR/nodekeys" "$WORKDIR/neighbors"

# Map array index → (BYZ, REP)
byz=(0 2 4 6)
CFG_IDX=$(( SLURM_ARRAY_TASK_ID / 20 ))     # 0..3
REP=$(( SLURM_ARRAY_TASK_ID % 20 + 1 ))     # 1..20
NUMBYZ="${byz[$CFG_IDX]}"
NUM1="${HPC_NUM_NODES}"

# Host IP
HOST_IP=$(hostname -I | awk '{print $1}')
echo "[array] host_ip=$HOST_IP  task_id=$SLURM_ARRAY_TASK_ID  cfg=$NUMBYZ  rep=$REP"

# Generate identifiers.txt where controllers expect it
pushd "$FLOOR" >/dev/null
python3 "$HPC/make_identifiers.py" "$HPC_NUM_NODES" > identifiers.txt

# Start geth swarm (5 nodes by default) and peering service
echo "[array] Starting geth swarm..."
bash "$HPC/start-geth.sh"

# Give geth more time to initialize before starting peering service
sleep 10

python3 "$HPC/peering_service.py" &
PEER_PID=$!

# Wait for the RPC to respond with better error handling
echo '[array] waiting for geth JSON-RPC on :8545'
for i in {1..300}; do
  if curl -fsS -H "Content-Type: application/json" \
       -X POST --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
       http://127.0.0.1:8545 >/dev/null 2>&1; then
    echo "[array] JSON-RPC ready"
    break
  fi
  
  # Check if geth process is still running
  if ! kill -0 $GETH_LAUNCH_PID 2>/dev/null; then
    echo "[array] ERROR: Geth process died unexpectedly" >&2
    exit 1
  fi
  
  # Show progress every 30 seconds
  if [ $((i % 30)) -eq 0 ]; then
    echo "[array] Still waiting for geth... attempt $i/300"
  fi
  
  sleep 1
done

if [ "$i" -ge 300 ]; then
  echo "[array] ERROR: JSON-RPC never came up after 300 attempts" >&2
  echo "[array] Checking geth logs..."
  if [ -f "$WORKDIR/logs/node0.log" ]; then
    echo "[array] Last 20 lines of geth log:"
    tail -20 "$WORKDIR/logs/node0.log"
  fi
  exit 1
fi

# ---- Run a single ARGoS repetition (REPS=1) w/o Docker ----
# Prepare experiment env
source "$FLOOR/experimentconfig.sh" || true
# Force required knobs
export NUM1="$NUM1"
export NUMBYZANTINE="$NUMBYZ"
export REPS=1

# Ensure ARGoS file is set; fall back if not
ARGOSFILE="${ARGOSFILE:-$FLOOR/experiments/fast-floor.argos}"
SLEEPTIME="${SLEEPTIME:-2}"

echo "[array] starting ARGoS: $ARGOSFILE"
sleep "$SLEEPTIME"
argos3 -z -c "$ARGOSFILE"

# Collect logs/results from WORKDIR + logs/
RESULTS_DIR="$FLOOR/results/experiment_${EXP:-default}/24rob-${NUMBYZ}byz/${REP}"
mkdir -p "$RESULTS_DIR"
[ -d "$WORKDIR" ] && cp -r "$WORKDIR"/* "$RESULTS_DIR"/ 2>/dev/null || true
[ -d "$FLOOR/logs" ] && cp -r "$FLOOR/logs"/* "$RESULTS_DIR"/ 2>/dev/null || true

echo "[array] results → $RESULTS_DIR"

# Cleanup processes
trap "kill $GETH_LAUNCH_PID $PEER_PID 2>/dev/null || true" EXIT
wait $GETH_LAUNCH_PID || true
wait $PEER_PID || true

popd >/dev/null
echo "[array] done."
