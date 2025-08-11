#!/bin/bash
# Per-repetition Geth network launcher for HPC
set -e

# Default environment variables
SIF="${SIF:-hpc/geth.sif}"
GENESIS_JSON="${GENESIS_JSON:-../../argos-blockchain/geth/files/genesis_poa.json}"
HPC_NUM_NODES="${HPC_NUM_NODES:-24}"
HPC_BASE_OFFSET="${HPC_BASE_OFFSET:-$(( 1000 * ${SLURM_ARRAY_TASK_ID:-0} ))}"
P2P_BASE="${P2P_BASE:-30303}"
HTTP_BASE="${HTTP_BASE:-8545}"
WS_BASE="${WS_BASE:-8546}"
NETWORK_ID="${NETWORK_ID:-456719}"

# Working directory
WORKDIR="${SLURM_TMPDIR:-/tmp}/ethnet"

echo "Starting Geth network with ${HPC_NUM_NODES} nodes"
echo "Base offset: ${HPC_BASE_OFFSET}"
echo "Working directory: ${WORKDIR}"

# Create working directory structure
mkdir -p "${WORKDIR}"/{nodes,nodekeys,neighbors}

# Get host IP for NAT
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Host IP: ${HOST_IP}"

# Generate node keys deterministically
echo "Generating node keys..."
for i in $(seq 0 $((HPC_NUM_NODES-1))); do
    keyfile="${WORKDIR}/nodekeys/nodekey.${i}"
    if [[ ! -f "${keyfile}" ]]; then
        # Use apptainer to run bootnode for key generation
        apptainer exec "${SIF}" bootnode -genkey "${keyfile}"
    fi
done

# Function to cleanup Geth processes
cleanup() {
    echo "Cleaning up Geth processes..."
    for pid in "${geth_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    wait
    echo "Cleanup complete"
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Array to store process IDs
declare -a geth_pids=()

# Initialize and start Geth nodes
echo "Initializing and starting Geth nodes..."
for i in $(seq 0 $((HPC_NUM_NODES-1))); do
    # Calculate unique ports
    P2P_PORT=$((P2P_BASE + HPC_BASE_OFFSET + i))
    HTTP_PORT=$((HTTP_BASE + HPC_BASE_OFFSET + i))
    WS_PORT=$((WS_BASE + HPC_BASE_OFFSET + i))
    
    # Node directory
    NODE_DIR="${WORKDIR}/nodes/node${i}"
    DATADIR="${NODE_DIR}/geth"
    
    # Create node directory
    mkdir -p "${NODE_DIR}"
    
    # Copy nodekey
    mkdir -p "${DATADIR}"
    cp "${WORKDIR}/nodekeys/nodekey.${i}" "${DATADIR}/nodekey"
    
    # Initialize genesis only once (check for sentinel file)
    INIT_SENTINEL="${NODE_DIR}/.geth_initialized"
    if [[ ! -f "${INIT_SENTINEL}" ]]; then
        echo "Initializing node ${i}..."
        apptainer exec "${SIF}" geth init \
            --datadir "${DATADIR}" \
            "${GENESIS_JSON}"
        touch "${INIT_SENTINEL}"
    fi
    
    # Launch Geth node
    echo "Starting Geth node ${i} (P2P:${P2P_PORT}, HTTP:${HTTP_PORT}, WS:${WS_PORT})"
    apptainer exec "${SIF}" geth \
        --datadir "${DATADIR}" \
        --networkid "${NETWORK_ID}" \
        --port "${P2P_PORT}" \
        --http \
        --http.port "${HTTP_PORT}" \
        --http.addr "0.0.0.0" \
        --http.api "web3,eth,net,personal,admin" \
        --ws \
        --ws.port "${WS_PORT}" \
        --ws.addr "0.0.0.0" \
        --ws.api "web3,eth,net,personal,admin" \
        --nat "extip:${HOST_IP}" \
        --nodiscover \
        --maxpeers 50 \
        --verbosity 3 \
        --nousb \
        --allow-insecure-unlock \
        --unlock "0" \
        --password <(echo "") \
        &
    
    geth_pids+=($!)
    
    # Small delay between node starts
    sleep 0.5
done

echo "All ${HPC_NUM_NODES} Geth nodes started"
echo "Process IDs: ${geth_pids[*]}"

# Wait for all processes
wait