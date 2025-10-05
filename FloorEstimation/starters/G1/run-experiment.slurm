#!/bin/bash
#SBATCH --export=ALL
#SBATCH --job-name=floor_simulation    # Job name
#SBATCH --output=logs/slurm-%A_%a.out  # Standard output log
#SBATCH --error=logs/slurm-%A_%a.err   # Standard error log
#SBATCH --array=0-4                   # Job array range (adjust as needed)
#SBATCH --time=01:00:00                # Time limit (hh:mm:ss)
#SBATCH --partition=standard           # Partition name
#SBATCH --ntasks=1                     # Number of tasks per job
#SBATCH --cpus-per-task=2              # Number of CPU cores per task
#SBATCH --mem=12G                       # Memory per job

# Load necessary modules (if required)
#module load docker  # Example: Load Docker if needed

export SUDO_ASKPASS=/home/cug/thesis/askpass.sh

# Reset Docker Swarm (safe in single-node local/HPC testing)
sudo -A systemctl restart docker
sleep 7
docker swarm leave --force >/dev/null 2>&1 || true
docker swarm init >/dev/null 2>&1
sleep 5


# Define BYZ_VALUES and REPS
BYZ_VALUES=(0 3)  # Example Byzantine values
REPS=2             # Number of repetitions per BYZ value ,  4 total runs w/ 2 byz

# Calculate BYZ and REP based on SLURM_ARRAY_TASK_ID
BYZ_INDEX=$((SLURM_ARRAY_TASK_ID / REPS))
REP=$((SLURM_ARRAY_TASK_ID % REPS + 1))
BYZ=${BYZ_VALUES[$BYZ_INDEX]}

# Run the starter script with the calculated parameters , Absolute path used because SLURM run in $HOME directory
bash /home/cug/thesis/blockchain-simulations/FloorEstimation/starters/G1/slum_starter.sh $BYZ $REP