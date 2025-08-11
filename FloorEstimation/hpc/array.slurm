#!/bin/bash
#SBATCH -p midst
#SBATCH --array=0-79%32
#SBATCH --mem=16G
#SBATCH -c 1
#SBATCH -o logs/%x-%j_%a.out
#SBATCH -e logs/%x-%j_%a.err
#SBATCH --time=4:00:00

# HPC Slurm array job for massively parallel blockchain simulations
# Each array index = one experiment repetition (REPS=1)
# 80 total runs: byz ∈ {0,2,4,6}, 20 repetitions each

set -e

# Environment hygiene for reproducibility
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1  
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

# HPC configuration
export HPC_NUM_NODES=24
export HPC_BASE_OFFSET=$((1000 * SLURM_ARRAY_TASK_ID))

# Map array index to experimental configuration
byz=(0 2 4 6)
CFG_IDX=$((SLURM_ARRAY_TASK_ID / 20))  # 0..3
REP=$((SLURM_ARRAY_TASK_ID % 20 + 1))  # 1..20
NUMBYZ=${byz[$CFG_IDX]}
NUM1=24

echo "=========================================="
echo "SLURM Array Job - Blockchain Simulation"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Configuration: $NUM1 robots, $NUMBYZ Byzantine"
echo "Repetition: $REP"
echo "Base offset: $HPC_BASE_OFFSET"
echo "Working directory: $SLURM_TMPDIR"
echo "=========================================="

# Navigate to experiment directory
cd $SLURM_SUBMIT_DIR

# Build SIF file if missing
SIF_FILE="hpc/geth.sif"
if [ ! -f "$SIF_FILE" ]; then
    echo "Building SIF file..."
    bash hpc/build_geth_sif.sh
fi

# Prepare working directory
WORKDIR="$SLURM_TMPDIR/ethnet"
mkdir -p "$WORKDIR" "$WORKDIR/neighbors"

echo "Prepared working directory: $WORKDIR"

# Generate identifiers.txt for controllers
IDENTIFIERS_FILE="$WORKDIR/identifiers.txt"
python3 hpc/make_identifiers.py $NUM1 > "$IDENTIFIERS_FILE"
echo "Generated identifiers file: $IDENTIFIERS_FILE"

# Source experiment configuration and override settings
source experimentconfig.sh

# Override configuration for this repetition
export NUM1=$NUM1
export NUMBYZANTINE=$NUMBYZ
export REPS=1
export EXPERIMENTFOLDER="$SLURM_SUBMIT_DIR"

# Set up paths for HPC mode
export SIF="$SLURM_SUBMIT_DIR/$SIF_FILE"
export GENESIS_JSON="$SLURM_SUBMIT_DIR/../../argos-blockchain/geth/files/genesis.json"

# Check if we have the PoA genesis, otherwise use regular genesis
POA_GENESIS="$SLURM_SUBMIT_DIR/../../argos-blockchain/geth/files/genesis_poa.json"
if [ -f "$POA_GENESIS" ]; then
    export GENESIS_JSON="$POA_GENESIS"
fi

echo "Using genesis file: $GENESIS_JSON"

# Start geth network in background
echo "Starting geth network..."
cd "$WORKDIR"
"$SLURM_SUBMIT_DIR/hpc/start-geth.sh" &
GETH_PID=$!

# Start peering service in background
echo "Starting peering service..."
python3 "$SLURM_SUBMIT_DIR/hpc/peering_service.py" "$WORKDIR" "$SIF" $HPC_NUM_NODES $HPC_BASE_OFFSET &
PEERING_PID=$!

# Wait for geth network to initialize
echo "Waiting for geth network to initialize..."
sleep 30

# Return to experiment directory
cd "$SLURM_SUBMIT_DIR"

# Update experimentconfig.sh temporarily for this run
TEMP_CONFIG="$WORKDIR/experimentconfig_hpc.sh"
cp experimentconfig.sh "$TEMP_CONFIG"

# Override paths and settings for HPC mode
cat >> "$TEMP_CONFIG" << EOF

# HPC Mode Overrides
export NUM1=$NUM1
export NUMBYZANTINE=$NUMBYZ
export REPS=1
export BLOCKCHAINPATH="$WORKDIR"

# Point to our identifiers file
export IDENTIFIERS_PATH="$IDENTIFIERS_FILE"
EOF

# Source the modified config
source "$TEMP_CONFIG"

# Ensure logs directory exists
mkdir -p logs

echo "Running ARGoS experiment..."
echo "Configuration: $NUM1 robots, $NUMBYZ Byzantine, repetition $REP"

# Run the experiment (without Docker - direct ARGoS)
if argos3 -z -c $ARGOSFILE; then
    echo "ARGoS experiment completed successfully"
else
    echo "ARGoS experiment failed"
    EXPERIMENT_EXIT_CODE=$?
fi

echo "Collecting logs..."

# Create results directory structure
RESULT_DIR="results/experiment_${SLURM_JOB_NAME:-hpc}/24rob-${NUMBYZ}byz/$REP"
mkdir -p "$RESULT_DIR"

# Copy logs from working directory
if [ -d logs ]; then
    cp -r logs/* "$RESULT_DIR/" 2>/dev/null || true
fi

# Copy geth logs
for i in $(seq 0 $((NUM1-1))); do
    if [ -f "$WORKDIR/geth.$i.log" ]; then
        mkdir -p "$RESULT_DIR/$((i+1))"
        cp "$WORKDIR/geth.$i.log" "$RESULT_DIR/$((i+1))/"
    fi
done

# Copy configuration files
cp "$TEMP_CONFIG" "$RESULT_DIR/experimentconfig.sh"
cp loop_functions/loop_params.py "$RESULT_DIR/" 2>/dev/null || true
cp controllers/control_params.py "$RESULT_DIR/" 2>/dev/null || true

echo "Results stored in: $RESULT_DIR"

# Cleanup background processes
echo "Cleaning up..."
if kill -0 $PEERING_PID 2>/dev/null; then
    kill $PEERING_PID || true
fi

if kill -0 $GETH_PID 2>/dev/null; then
    kill $GETH_PID || true
    wait $GETH_PID 2>/dev/null || true
fi

echo "Array task $SLURM_ARRAY_TASK_ID completed."
exit ${EXPERIMENT_EXIT_CODE:-0}