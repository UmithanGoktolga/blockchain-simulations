#!/bin/bash
# Per-repetition network launcher for HPC mode
# Starts 24 geth nodes with unique port ranges

set -e

# Default configuration (can be overridden by environment)
SIF="${SIF:-hpc/geth.sif}"
GENESIS_JSON="${GENESIS_JSON:-../../argos-blockchain/geth/files/genesis_poa.json}"
HPC_NUM_NODES="${HPC_NUM_NODES:-24}"
HPC_BASE_OFFSET="${HPC_BASE_OFFSET:-$((1000 * ${SLURM_ARRAY_TASK_ID:-0}))}"
P2P_BASE="${P2P_BASE:-30303}"
HTTP_BASE="${HTTP_BASE:-8545}"
WS_BASE="${WS_BASE:-8546}"
NETWORK_ID="${NETWORK_ID:-456719}"

# Working directory
WORKDIR="${SLURM_TMPDIR:-/tmp}/ethnet"
NODES_DIR="$WORKDIR/nodes"
NODEKEYS_DIR="$WORKDIR/nodekeys"
NEIGHBORS_DIR="$WORKDIR/neighbors"

# Host IP for external connections
HOST_IP=$(hostname -I | awk '{print $1}')

echo "Starting HPC geth network:"
echo "  Nodes: $HPC_NUM_NODES"
echo "  Base offset: $HPC_BASE_OFFSET" 
echo "  Host IP: $HOST_IP"
echo "  Working dir: $WORKDIR"
echo "  Genesis: $GENESIS_JSON"

# Create working directories
mkdir -p "$NODES_DIR" "$NODEKEYS_DIR" "$NEIGHBORS_DIR"

# Function to generate deterministic nodekey
generate_nodekey() {
    local node_id=$1
    local keyfile="$NODEKEYS_DIR/nodekey.$node_id"
    
    if [ ! -f "$keyfile" ]; then
        echo "Generating nodekey for node $node_id"
        apptainer exec "$SIF" bootnode -genkey "$keyfile"
    fi
}

# Function to initialize geth datadir
init_geth_node() {
    local node_id=$1
    local datadir="$NODES_DIR/node$node_id/geth"
    local sentinel="$datadir/.initialized"
    
    if [ ! -f "$sentinel" ]; then
        echo "Initializing geth datadir for node $node_id"
        mkdir -p "$datadir"
        
        # Copy nodekey
        cp "$NODEKEYS_DIR/nodekey.$node_id" "$datadir/nodekey"
        
        # Initialize with genesis
        apptainer exec "$SIF" geth \
            --datadir "$datadir" \
            init "$GENESIS_JSON"
        
        # Mark as initialized
        touch "$sentinel"
    fi
}

# Function to start a geth node
start_geth_node() {
    local node_id=$1
    local datadir="$NODES_DIR/node$node_id/geth"
    
    # Calculate unique ports
    local p2p_port=$((P2P_BASE + HPC_BASE_OFFSET + node_id))
    local http_port=$((HTTP_BASE + HPC_BASE_OFFSET + node_id))
    local ws_port=$((WS_BASE + HPC_BASE_OFFSET + node_id))
    
    echo "Starting node $node_id on ports: P2P=$p2p_port, HTTP=$http_port, WS=$ws_port"
    
    # Start geth in background
    apptainer exec "$SIF" geth \
        --datadir "$datadir" \
        --networkid "$NETWORK_ID" \
        --port "$p2p_port" \
        --http \
        --http.addr "0.0.0.0" \
        --http.port "$http_port" \
        --http.api "eth,net,web3,personal,admin,miner" \
        --http.corsdomain "*" \
        --ws \
        --ws.addr "0.0.0.0" \
        --ws.port "$ws_port" \
        --ws.api "eth,net,web3,personal,admin,miner" \
        --nat "extip:$HOST_IP" \
        --nodiscover \
        --verbosity 2 \
        --syncmode full \
        --allow-insecure-unlock \
        --mine \
        --miner.gasprice 1 \
        --lightkdf \
        > "$WORKDIR/geth.$node_id.log" 2>&1 &
    
    # Store PID for cleanup
    echo $! > "$WORKDIR/geth.$node_id.pid"
}

# Cleanup function
cleanup() {
    echo "Cleaning up geth processes..."
    for i in $(seq 0 $((HPC_NUM_NODES - 1))); do
        if [ -f "$WORKDIR/geth.$i.pid" ]; then
            local pid=$(cat "$WORKDIR/geth.$i.pid")
            if kill -0 "$pid" 2>/dev/null; then
                echo "Killing geth node $i (PID: $pid)"
                kill "$pid" || true
            fi
            rm -f "$WORKDIR/geth.$i.pid"
        fi
    done
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT EXIT

# Check if SIF file exists
if [ ! -f "$SIF" ]; then
    echo "Error: SIF file $SIF not found. Run build_geth_sif.sh first."
    exit 1
fi

# Check if genesis file exists
if [ ! -f "$GENESIS_JSON" ]; then
    echo "Error: Genesis file $GENESIS_JSON not found."
    exit 1
fi

# Generate nodekeys and initialize nodes
for i in $(seq 0 $((HPC_NUM_NODES - 1))); do
    generate_nodekey "$i"
    init_geth_node "$i"
done

# Start all geth nodes
for i in $(seq 0 $((HPC_NUM_NODES - 1))); do
    start_geth_node "$i"
    sleep 1  # Brief delay between starts
done

echo "All $HPC_NUM_NODES geth nodes started. Waiting..."

# Wait for all background processes
wait