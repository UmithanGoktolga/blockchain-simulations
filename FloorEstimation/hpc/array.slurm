#!/bin/bash
#SBATCH -p midst
#SBATCH --array=0-79%32
#SBATCH --mem=16G
#SBATCH -c 1
#SBATCH -o logs/%x-%j_%a.out
#SBATCH -e logs/%x-%j_%a.err

# HPC array job script for blockchain simulations
# One repetition per array index

set -e

# Environment hygiene
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

# Array index to config mapping
byz=(0 2 4 6)
CFG_IDX=$(( SLURM_ARRAY_TASK_ID / 20 ))
REP=$(( SLURM_ARRAY_TASK_ID % 20 + 1 ))
NUMBYZ=${byz[$CFG_IDX]}
NUM1=24

echo "=== HPC Blockchain Simulation ==="
echo "Array Task ID: ${SLURM_ARRAY_TASK_ID}"
echo "Config Index: ${CFG_IDX}"
echo "Repetition: ${REP}"
echo "Byzantine nodes: ${NUMBYZ}"
echo "Total nodes: ${NUM1}"
echo "Node: $(hostname)"
echo "==============================="

# HPC configuration
export HPC_MODE=1
export HPC_NUM_NODES=${NUM1}
export HPC_BASE_OFFSET=$(( 1000 * SLURM_ARRAY_TASK_ID ))

# Working directory
WORKDIR="${SLURM_TMPDIR}/ethnet"
export SLURM_TMPDIR="${SLURM_TMPDIR}"

# Get script directory (hpc/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "Script directory: ${SCRIPT_DIR}"
echo "Experiment directory: ${EXPERIMENT_DIR}"
echo "Working directory: ${WORKDIR}"

# Build SIF if missing
SIF_PATH="${SCRIPT_DIR}/geth.sif"
export SIF="${SIF_PATH}"  # Export for child scripts
if [[ ! -f "${SIF_PATH}" ]]; then
    echo "Building Apptainer SIF..."
    cd "${SCRIPT_DIR}"
    bash build_geth_sif.sh
    cd "${EXPERIMENT_DIR}"
fi

# Prepare working directory
echo "Preparing working directory..."
mkdir -p "${WORKDIR}"
mkdir -p logs

# Validate prerequisites
if [[ ! -f "${EXPERIMENT_DIR}/experimentconfig.sh" ]]; then
    echo "Error: experimentconfig.sh not found in ${EXPERIMENT_DIR}"
    exit 1
fi

if [[ ! -f "${EXPERIMENT_DIR}/experiments/fast-floor.x.argos" ]]; then
    echo "Warning: ARGoS template file not found, experiment may fail"
fi

# Source experiment configuration
cd "${EXPERIMENT_DIR}"
source experimentconfig.sh

# Override configuration for HPC
export NUM1=${NUM1}
export NUMBYZANTINE=${NUMBYZ}
export REPS=1
export EXPERIMENTFOLDER="${EXPERIMENT_DIR}"

# Generate identifiers.txt for controllers
echo "Generating identifiers.txt..."
python3 hpc/make_identifiers.py ${HPC_NUM_NODES} > "${WORKDIR}/identifiers.txt"

# Copy identifiers to experiment folder so controllers can find it
cp "${WORKDIR}/identifiers.txt" "${EXPERIMENT_DIR}/"

# Function to cleanup background processes
cleanup() {
    echo "Cleaning up background processes..."
    if [[ -n "${GETH_PID}" ]]; then
        kill -TERM "${GETH_PID}" 2>/dev/null || true
    fi
    if [[ -n "${PEERING_PID}" ]]; then
        kill -TERM "${PEERING_PID}" 2>/dev/null || true
    fi
    wait
}

trap cleanup EXIT SIGTERM SIGINT

# Launch Geth network in background
echo "Starting Geth network..."
bash "${SCRIPT_DIR}/start-geth.sh" &
GETH_PID=$!

# Give Geth nodes time to start
sleep 10

# Launch peering service in background
echo "Starting peering service..."
python3 "${SCRIPT_DIR}/peering_service.py" &
PEERING_PID=$!

# Give peering service time to start
sleep 5

# Update ARGoS configuration for HPC
echo "Updating ARGoS configuration..."
sed -e "s|REALTIME|$REALTIME|g"\
    -e "s|NUMROBOTS|$NUMROBOTS|g"\
    -e "s|WHEELNOISE|$WHEELNOISE|g"\
    -e "s|CON1|$CON1|g"\
    -e "s|MYLOOP|$MYLOOP|g"\
    -e "s|LENGTH|$LENGTH|g"\
    -e "s|NUM1|$NUM1|g"\
    -e "s|STARTDIM|$STARTDIM|g"\
    -e "s|TPS|$TPS|g"\
    -e "s|RABRANGE|$RABRANGE|g"\
    -e "s|NUMBYZANTINE|$NUMBYZANTINE|g"\
    -e "s|EXPERIMENTFOLDER|$EXPERIMENTFOLDER|g"\
    -e "s|FLOORFILE|$FLOORFILE|g"\
    -e "s|ARGOSFOLDER|$ARGOSFOLDER|g"\
    -e "s|ARENADIMH|$ARENADIMH|g"\
    -e "s|ARENADIM|$ARENADIM|g"\
  $ARGOSTEMPLATE > $ARGOSFILE

# Run experiment
echo "Running ARGoS experiment..."
argos3 -z -c $ARGOSFILE

echo "ARGoS experiment completed"

# Collect logs
echo "Collecting logs..."
EXP="HPC"
RESULTS_DIR="${EXPERIMENT_DIR}/results/experiment_${EXP}/24rob-${NUMBYZ}byz/${REP}"
mkdir -p "${RESULTS_DIR}"

# Copy logs from working directory
if [[ -d "${WORKDIR}" ]]; then
    cp -r "${WORKDIR}"/* "${RESULTS_DIR}/" 2>/dev/null || true
fi

# Copy standard logs
if [[ -d "logs" ]]; then
    cp -r logs/* "${RESULTS_DIR}/" 2>/dev/null || true
fi

echo "Results stored in: ${RESULTS_DIR}"
echo "HPC simulation completed successfully"