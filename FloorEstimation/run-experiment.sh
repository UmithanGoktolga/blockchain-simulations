#!/bin/bash
#SBATCH --job-name=blockchain-sim
#SBATCH --output=slurm_output/blockchain_sim_%A_%a.out
#SBATCH --error=slurm_output/blockchain_sim_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G

# SLURM Blockchain Simulation Runner
# This script uses SLURM job arrays to run multiple repetitions in parallel
# 
# Usage:
#   sbatch --array=1-10 run-experiment.sh [num_byzantine_robots] [experiment_id]
#   
# Example:
#   sbatch --array=1-3 run-experiment.sh 0 G1    # 3 reps with 0 Byzantine robots
#   sbatch --array=1-3 run-experiment.sh 3 G1    # 3 reps with 3 Byzantine robots
#   sbatch --array=1-3 run-experiment.sh 6 G1    # 3 reps with 6 Byzantine robots

source experimentconfig.sh

# Create output directory for SLURM logs
mkdir -p slurm_output

# Get parameters
NUM_BYZANTINE=${1:-0}           # Number of Byzantine robots (default: 0)
EXPERIMENT_ID=${2:-"G1"}        # Experiment identifier (default: G1)

echo "=========================================="
echo "SLURM Job Information:"
echo "  Job ID: $SLURM_JOB_ID"
echo "  Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "  Node: $SLURMD_NODENAME"
echo "=========================================="

# Run the experiment with the current array task ID as repetition number
./run_experiment.sh "$NUM_BYZANTINE" "$EXPERIMENT_ID" "$SLURM_ARRAY_TASK_ID"

echo "SLURM array task $SLURM_ARRAY_TASK_ID completed."