#!/usr/bin/env bash
#SBATCH -J geth-net
#SBATCH -p midst
#SBATCH --array=0-79%32
#SBATCH --mem=16G
#SBATCH -c 1
#SBATCH -o logs/%x-%j_%a.out
#SBATCH -e logs/%x-%j_%a.err

set -euo pipefail
mkdir -p logs

# Thread hygiene
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Repo layout
ROOT="$(pwd)/blockchain-simulations"
FLOOR="$ROOT/FloorEstimation"
HPC="$FLOOR/hpc"

# Defaults (can be overridden from env)
export SIF="${SIF:-$HPC/geth.sif}"
export GENESIS_JSON="${GENESIS_JSON:-$ROOT/argos-blockchain/geth/files/genesis_poa.json}"
export HPC_NUM_NODES="${HPC_NUM_NODES:-24}"
export HPC_BASE_OFFSET="${HPC_BASE_OFFSET:-$(( 1000 * ${SLURM_ARRAY_TASK_ID:-0} ))}"
export NETWORK_ID="${NETWORK_ID:-456719}"
export P2P_BASE="${P2P_BASE:-30303}"
export HTTP_BASE="${HTTP_BASE:-8545}"
export WS_BASE="${WS_BASE:-8546}"
export HPC_MODE=1

# Build SIF if missing
if [ ! -f "$SIF" ]; then
  echo "[array] building SIF → $SIF"
  bash "$HPC/build_geth_sif.sh"
fi

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

# Start geth swarm (24 nodes by default) and peering service
bash "$HPC/start-geth.sh" &
GETH_LAUNCH_PID=$!
python3 "$HPC/peering_service.py" &
PEER_PID=$!

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
