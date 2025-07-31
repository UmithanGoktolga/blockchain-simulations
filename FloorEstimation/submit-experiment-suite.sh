#!/bin/bash
# SLURM Experiment Suite Runner
# Runs experiments for 0, 3, and 6 Byzantine robots with 3 repetitions each
# This validates the scenarios mentioned in the problem statement

source experimentconfig.sh

EXPERIMENT_ID="G1"
NUM_REPS=3
BYZANTINE_COUNTS=(0 3 6)

echo "=========================================="
echo "SLURM Blockchain Simulation Suite"
echo "Experiment ID: $EXPERIMENT_ID"
echo "Repetitions per configuration: $NUM_REPS"
echo "Byzantine robot counts: ${BYZANTINE_COUNTS[@]}"
echo "=========================================="

# Create output directory for SLURM logs
mkdir -p slurm_output

# Submit jobs for each Byzantine robot configuration
for byz_count in "${BYZANTINE_COUNTS[@]}"; do
    echo "Submitting jobs for $byz_count Byzantine robots..."
    
    job_id=$(sbatch --array=1-$NUM_REPS \
                   --job-name="blockchain-sim-${byz_count}byz" \
                   --output="slurm_output/blockchain_sim_${byz_count}byz_%A_%a.out" \
                   --error="slurm_output/blockchain_sim_${byz_count}byz_%A_%a.err" \
                   run-experiment.sh $byz_count $EXPERIMENT_ID | awk '{print $4}')
    
    echo "  Job ID: $job_id (Array: 1-$NUM_REPS)"
    
    # Optional: Add dependency to prevent resource conflicts
    # Uncomment the next line if you want jobs to run sequentially
    # DEPENDENCY_FLAG="--dependency=afterany:$job_id"
done

echo ""
echo "All jobs submitted! Monitor progress with:"
echo "  squeue -u \$USER"
echo ""
echo "Check results in:"
echo "  \$EXPERIMENTFOLDER/results/data/experiment_$EXPERIMENT_ID/"
echo ""
echo "Expected folder structure:"
for byz_count in "${BYZANTINE_COUNTS[@]}"; do
    echo "  24rob-${byz_count}/<MonthDay_HourMin>/rep_[1-3]/"
done