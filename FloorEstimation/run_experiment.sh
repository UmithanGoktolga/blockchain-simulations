#!/bin/bash
# SLURM-compatible experiment runner with job array support
# Usage: ./run-experiment.sh [num_byzantine_robots] [experiment_id] [repetition_number]

source experimentconfig.sh

# Set ulimit for file descriptors
ulimit -n 16000

# Get parameters (for SLURM job array compatibility)
NUM_BYZANTINE=${1:-$NUMBYZANTINE}  # Byzantine robot count (can be overridden)
EXPERIMENT_ID=${2:-"G1"}           # Experiment identifier
REP_NUMBER=${3:-$SLURM_ARRAY_TASK_ID}  # Repetition number (from SLURM array or default)

# If not running under SLURM, default to repetition 1
if [ -z "$REP_NUMBER" ]; then
    REP_NUMBER=1
fi

echo "=========================================="
echo "Starting experiment:"
echo "  Byzantine robots: $NUM_BYZANTINE"
echo "  Experiment ID: $EXPERIMENT_ID"
echo "  Repetition: $REP_NUMBER"
echo "=========================================="

# Create timestamped result folder structure
export LC_TIME=C
TIMESTAMP=$(date +"%m%d_%H%M")  # MonthDay_HourMin format
RESULT_BASE_DIR="$EXPERIMENTFOLDER/results/data/experiment_$EXPERIMENT_ID"
EXPERIMENT_DIR="$RESULT_BASE_DIR/${NUM1}rob-${NUM_BYZANTINE}/$TIMESTAMP"
REP_DIR="$EXPERIMENT_DIR/rep_$REP_NUMBER"

# Ensure result directories exist
mkdir -p "$REP_DIR"
echo "Results will be stored in: $REP_DIR"

# Cleanup function for proper resource management
cleanup() {
    echo "Cleaning up resources..."
    
    # Kill any running processes
    killall argos3 2>/dev/null || true
    killall python3 2>/dev/null || true
    
    # Clean up docker containers if they exist
    if command -v docker &> /dev/null; then
        echo "Stopping and removing Docker containers..."
        docker ps -q --filter "name=${SWARMNAME}" | xargs -r docker stop
        docker ps -aq --filter "name=${SWARMNAME}" | xargs -r docker rm
    fi
    
    # Clean up temporary files
    rm -rf logs
    rm -rf /tmp/blockchain_temp_* 2>/dev/null || true
    
    echo "Cleanup completed."
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Perform cleanup at start
cleanup

# Recreate the temporary logging folder
mkdir -p logs

# Update configuration with current Byzantine count
sed -i "s|^export NUMBYZANTINE=.*|export NUMBYZANTINE=${NUM_BYZANTINE}|" experimentconfig.sh

# Create config file for Python controllers
python_config_file="controllers/config.py"
echo "num_byzantine=${NUM_BYZANTINE}" > $python_config_file
echo "byzantine_swarm_style=${BYZANTINESWARMSTYLE}" >> $python_config_file

# Generate floor if needed (uncomment for Exp. 2)
# python3 experiments/generate_floor/generate_floor.py 

# Restart docker containers and blockchain setup
echo "Resetting blockchain and Docker containers..."
./starter -r

# Wait for the system to be ready
echo "Waiting for system to be ready..."
sleep $SLEEPTIME

# Run the experiment
echo "Starting ARGoS simulation..."
timeout ${TIMELIMIT}m argos3 -z -c $ARGOSFILE

# Wait a moment for processes to finish
sleep 5

# Collect logged data with proper directory structure
echo "Collecting experiment data..."
bash collect-logs "$EXPERIMENT_ID/${NUM1}rob-${NUM_BYZANTINE}/${TIMESTAMP}" "$REP_DIR"

echo "Experiment completed successfully!"
echo "Data stored in: $REP_DIR"
