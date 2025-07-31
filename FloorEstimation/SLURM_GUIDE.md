# SLURM Compatibility Guide

This document explains the SLURM integration features for running blockchain simulations on HPC clusters.

## Overview

The SLURM compatibility update introduces:
- **Parallel Repetition Execution**: Uses `sbatch --array` for efficient job management
- **Timestamped Result Folders**: Prevents data collisions across multiple runs
- **Better Cleanup Handling**: Ensures reproducible experiments on HPC nodes
- **Dynamic Configuration**: Byzantine robot count can be specified at runtime

## File Structure

```
├── run-experiment.sh          # SLURM job script (sbatch compatible)
├── run_experiment.sh          # Core experiment runner
├── submit-experiment-suite.sh # Helper for running complete experiment suites
├── test-slurm-compatibility.sh # Test script for validation
└── slurm_output/             # Directory for SLURM output logs (auto-created)
```

## Result Folder Structure

Results are now organized with timestamps to prevent collisions:

```
results/data/experiment_G1/
├── 24rob-0/
│   └── 0731_1946/        # MonthDay_HourMin timestamp
│       ├── rep_1/
│       ├── rep_2/
│       └── rep_3/
├── 24rob-3/
│   └── 0731_1947/
│       ├── rep_1/
│       ├── rep_2/
│       └── rep_3/
└── 24rob-6/
    └── 0731_1948/
        ├── rep_1/
        ├── rep_2/
        └── rep_3/
```

## Usage Examples

### 1. Single SLURM Job Array

Submit 3 repetitions for 0 Byzantine robots:
```bash
sbatch --array=1-3 run-experiment.sh 0 G1
```

Submit 5 repetitions for 3 Byzantine robots:
```bash
sbatch --array=1-5 run-experiment.sh 3 G1
```

### 2. Complete Experiment Suite

Run the full validation suite (0, 3, 6 Byzantine robots with 3 reps each):
```bash
./submit-experiment-suite.sh
```

### 3. Local Testing (Non-SLURM)

Run a single experiment locally:
```bash
./run_experiment.sh 0 G1 1
```

### 4. Monitor Jobs

Check job status:
```bash
squeue -u $USER
```

View job output:
```bash
tail -f slurm_output/blockchain_sim_0byz_*.out
```

## Configuration

### SLURM Resource Requirements

Default settings in `run-experiment.sh`:
- **Time**: 2 hours (`--time=02:00:00`)
- **CPUs**: 4 cores (`--cpus-per-task=4`)
- **Memory**: 8GB (`--mem=8G`)

Adjust these based on your experiment requirements and cluster resources.

### Environment Variables

The following variables can be customized in `experimentconfig.sh`:
- `NUMBYZANTINE`: Number of Byzantine robots (can be overridden at runtime)
- `REPS`: Default number of repetitions
- `NUM1`: Total number of robots (usually 24)
- `TIMELIMIT`: Experiment timeout in minutes

## Cleanup Features

Each experiment run automatically:
1. Kills any existing ARGoS and Python processes
2. Stops and removes Docker containers
3. Cleans up temporary files
4. Recreates the logging directory

This ensures:
- No resource conflicts between jobs
- Reproducible experiments
- Clean state for each repetition

## Validation

Test the setup before submitting jobs:
```bash
./test-slurm-compatibility.sh
```

This validates:
- Script permissions and existence
- Timestamped folder creation
- Dynamic configuration updates
- Directory structure creation

## Troubleshooting

### Common Issues

1. **Permission denied**: Ensure all scripts are executable
   ```bash
   chmod +x run-experiment.sh run_experiment.sh submit-experiment-suite.sh
   ```

2. **Docker not found**: The cleanup function gracefully handles missing Docker

3. **Path issues**: All paths are relative to the FloorEstimation directory

4. **SLURM array variables**: `$SLURM_ARRAY_TASK_ID` is automatically used for repetition numbering

### Log Files

- SLURM output: `slurm_output/blockchain_sim_*.out`
- SLURM errors: `slurm_output/blockchain_sim_*.err`
- Experiment data: `results/data/experiment_*/24rob-*/*/rep_*/`

## Performance Notes

- Job arrays run repetitions in parallel, reducing total wall time
- Each job uses independent resources, preventing interference
- Timestamped folders ensure no data corruption from simultaneous runs
- Cleanup routines prevent resource exhaustion on compute nodes