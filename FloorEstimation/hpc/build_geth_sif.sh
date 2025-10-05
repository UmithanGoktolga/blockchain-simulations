#!/bin/bash
# Build Apptainer SIF from geth.def
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEF="$SCRIPT_DIR/geth.def"
OUT="$SCRIPT_DIR/geth.sif"
module load apptainer 2>/dev/null || true
apptainer build "$OUT" "$DEF"
echo "Built $OUT"



# Try to load apptainer module (common on HPC systems)
if command -v module &> /dev/null; then
    module load apptainer 2>/dev/null || true
fi

# Check if apptainer is available
if ! command -v apptainer &> /dev/null; then
    echo "Error: apptainer command not found. Please install Apptainer or load the module."
    exit 1
fi

# Build the SIF file
if apptainer build "${OUT}" "${OUT}"; then
    echo "Build successful: ${OUT}"
    echo "${OUT}"
    exit 0
else
    echo "Build failed"
    exit 1
fi