#!/bin/bash
# Build Apptainer SIF file from geth.def

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF_FILE="$SCRIPT_DIR/geth.sif"
DEF_FILE="$SCRIPT_DIR/geth.def"

# Try to load apptainer module (common on HPC systems)
if command -v module &> /dev/null; then
    module load apptainer 2>/dev/null || true
fi

# Check if apptainer is available
if ! command -v apptainer &> /dev/null; then
    echo "Error: apptainer not found. Please install Apptainer or load the module." >&2
    exit 1
fi

# Check if definition file exists
if [ ! -f "$DEF_FILE" ]; then
    echo "Error: Definition file $DEF_FILE not found." >&2
    exit 1
fi

echo "Building SIF file: $SIF_FILE"
echo "From definition: $DEF_FILE"

# Build the SIF file
if apptainer build "$SIF_FILE" "$DEF_FILE"; then
    echo "Success: $SIF_FILE"
    echo "$SIF_FILE"
else
    echo "Error: Failed to build SIF file." >&2
    exit 1
fi