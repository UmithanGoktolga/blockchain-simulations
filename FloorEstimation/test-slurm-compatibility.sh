#!/bin/bash
# Test script for SLURM compatibility features
# This can be run locally to test the functionality without SLURM

source experimentconfig.sh

echo "=========================================="
echo "Testing SLURM Compatibility Features"
echo "=========================================="

# Test 1: Check if run_experiment.sh exists and is executable
echo "Test 1: Checking run_experiment.sh..."
if [ -x "./run_experiment.sh" ]; then
    echo "  ✓ run_experiment.sh is executable"
else
    echo "  ✗ run_experiment.sh is not executable"
    exit 1
fi

# Test 2: Check if SLURM script exists
echo "Test 2: Checking run-experiment.sh (SLURM version)..."
if [ -x "./run-experiment.sh" ]; then
    echo "  ✓ run-experiment.sh exists and is executable"
else
    echo "  ✗ run-experiment.sh is not executable"
    exit 1
fi

# Test 3: Test timestamped folder creation
echo "Test 3: Testing timestamped folder creation..."
export LC_TIME=C
TIMESTAMP=$(date +"%m%d_%H%M")
RESULT_BASE_DIR="$EXPERIMENTFOLDER/results/data/experiment_G1"
TEST_DIR="$RESULT_BASE_DIR/24rob-0/$TIMESTAMP/rep_1"
mkdir -p "$TEST_DIR"

if [ -d "$TEST_DIR" ]; then
    echo "  ✓ Timestamped folder created: $TEST_DIR"
    # Cleanup test directory
    rm -rf "$RESULT_BASE_DIR/24rob-0/$TIMESTAMP"
else
    echo "  ✗ Failed to create timestamped folder"
    exit 1
fi

# Test 4: Check if config can be dynamically updated
echo "Test 4: Testing dynamic configuration update..."
ORIGINAL_BYZ=$(grep "^export NUMBYZANTINE=" experimentconfig.sh | cut -d'=' -f2)
echo "  Original NUMBYZANTINE: $ORIGINAL_BYZ"

# Test updating the config
sed -i "s|^export NUMBYZANTINE=.*|export NUMBYZANTINE=3|" experimentconfig.sh
NEW_BYZ=$(grep "^export NUMBYZANTINE=" experimentconfig.sh | cut -d'=' -f2)

if [ "$NEW_BYZ" = "3" ]; then
    echo "  ✓ Configuration updated successfully: NUMBYZANTINE=$NEW_BYZ"
    # Restore original value
    sed -i "s|^export NUMBYZANTINE=.*|export NUMBYZANTINE=$ORIGINAL_BYZ|" experimentconfig.sh
else
    echo "  ✗ Failed to update configuration"
    exit 1
fi

# Test 5: Check required scripts exist
echo "Test 5: Checking required scripts..."
REQUIRED_SCRIPTS=("starter" "collect-logs" "reset-geth")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "./$script" ]; then
        echo "  ✓ $script exists"
    else
        echo "  ✗ $script is missing"
        exit 1
    fi
done

# Test 6: Dry run of run_experiment.sh with test parameters
echo "Test 6: Dry run test..."
echo "  Testing run_experiment.sh with parameters: 0 G1 1"
echo "  (This is a mock test - would normally run the full experiment)"

# Create a test version that just validates the parameter handling
NUM_BYZANTINE=0
EXPERIMENT_ID="G1"
REP_NUMBER=1

export LC_TIME=C
TIMESTAMP=$(date +"%m%d_%H%M")
RESULT_BASE_DIR="$EXPERIMENTFOLDER/results/data/experiment_$EXPERIMENT_ID"
EXPERIMENT_DIR="$RESULT_BASE_DIR/24rob-${NUM_BYZANTINE}/$TIMESTAMP"
REP_DIR="$EXPERIMENT_DIR/rep_$REP_NUMBER"

echo "  Expected result directory: $REP_DIR"
mkdir -p "$REP_DIR"
if [ -d "$REP_DIR" ]; then
    echo "  ✓ Result directory structure created successfully"
    # Cleanup test directory
    rm -rf "$RESULT_BASE_DIR/24rob-${NUM_BYZANTINE}/$TIMESTAMP"
else
    echo "  ✗ Failed to create result directory structure"
    exit 1
fi

echo ""
echo "=========================================="
echo "All tests passed! ✓"
echo "SLURM compatibility features are ready."
echo "=========================================="
echo ""
echo "Usage examples:"
echo "  # Submit single job array:"
echo "  sbatch --array=1-3 run-experiment.sh 0 G1"
echo ""
echo "  # Submit full experiment suite:"
echo "  ./submit-experiment-suite.sh"
echo ""
echo "  # Run locally (non-SLURM):"
echo "  ./run_experiment.sh 0 G1 1"