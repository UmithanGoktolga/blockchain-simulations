#!/bin/bash
# filepath: /home/cug/thesis/blockchain-simulations/FloorEstimation/starters/G1/starter.sh
export SUDO_ASKPASS=/home/cug/thesis/askpass.sh



# Load experiment configuration
source experimentconfig.sh
export EXPERIMENTFOLDER=/home/cug/thesis/blockchain-simulations/FloorEstimation

#DATAFOLDER="$EXPERIMENTFOLDER/results/data"

# Accept parameters from Slurm job array
BYZ_COUNT=$1  # Number of Byzantine robots
REP=$2        # Repetition number

# Create a timestamped folder for this run
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

#RUN_FOLDER="${DATAFOLDER}/BYZ_${BYZ_COUNT}_REP_${REP}_${TIMESTAMP}"

set -x  # Enable debugging

RUN_FOLDER="${EXPERIMENTFOLDER}/results/data/BYZ_${BYZ_COUNT}_REP_${REP}_${TIMESTAMP}"
echo "RUN_FOLDER=${RUN_FOLDER}"
mkdir -p "${RUN_FOLDER}"

# Configure the experiment
config() {
    sed -i "s|^export ${1}=.*|export ${1}=${2}|" experimentconfig.sh
}

# Update the configuration for this run
config "NUMBYZANTINE" "${BYZ_COUNT}"
config "REPS" "1"  # Only one repetition per Slurm job
config "NOTES" "\"Run with BYZ_COUNT=${BYZ_COUNT}, REP=${REP}\""

for REP in $(seq 1 ${REPS}); do
    echo "Running experiment repetition ${REP}"
    . starter -r -s
    bash collect-logs "${EXP}/${CFG}" "${RUN_FOLDER}/${REP}"
    echo "Logs collected for repetition ${REP}"
    sleep 10
done

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf "${RUN_FOLDER}/temp"


echo "Experiment completed for BYZ_COUNT=${BYZ_COUNT}, REP=${REP}"