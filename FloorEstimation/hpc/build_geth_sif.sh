#!/bin/bash
# Build Apptainer SIF from geth.def
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF_PATH="${SCRIPT_DIR}/geth.sif"
DEF_PATH="${SCRIPT_DIR}/geth.def"

echo "Building Apptainer SIF: ${SIF_PATH}"

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
if apptainer build "${SIF_PATH}" "${DEF_PATH}"; then
    echo "Build successful: ${SIF_PATH}"
    echo "${SIF_PATH}"
    exit 0
else
    echo "Build failed"
    exit 1
fi