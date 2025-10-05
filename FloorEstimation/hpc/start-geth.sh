#!/usr/bin/env bash
# start-geth.sh — start a local multi-node geth network WITHOUT bootnode.
# Peering is via node0's enode written into static-nodes.json for followers.

set -euo pipefail

# --------- Inputs / defaults ----------
MAINFOLDER="${MAINFOLDER:-$HOME/thesis/blockchain-simulations}"
SIF="${SIF:-$(dirname "$0")/geth.sif}"
WORKDIR="${WORKDIR:-/tmp/ethnet}"
NETWORK_ID="${NETWORK_ID:-456719}"

# Base ports (p2p/http will increment per node)
P2P_BASE="${P2P_BASE:-30303}"     # geth --port
HTTP_BASE="${HTTP_BASE:-8545}"    # geth --http.port

# Swarm size
NUM_NODES="${HPC_NUM_NODES:-24}"

# Advertised IP (used in enode and NAT). Usually your LAN IP.
HOST_IP="${HOST_IP:-$(hostname -I | awk '{print $1}')}"

# Genesis file (POA)
GENESIS_JSON="${GENESIS_JSON:-$(realpath "$(dirname "$0")/../..")/argos-blockchain/geth/files/genesis_poa.json}"

# Expose HTTP on followers? (0 = only node0 has HTTP; 1 = all nodes expose HTTP)
FOLLOWER_HTTP="${FOLLOWER_HTTP:-1}"

# DEBUG: Print all configuration values
echo "[DEBUG] ========== BLOCKCHAIN STARTUP CONFIGURATION =========="
echo "[DEBUG] NUM_NODES: $NUM_NODES"
echo "[DEBUG] WORKDIR: $WORKDIR" 
echo "[DEBUG] NETWORK_ID: $NETWORK_ID"
echo "[DEBUG] P2P_BASE: $P2P_BASE"
echo "[DEBUG] HTTP_BASE: $HTTP_BASE"
echo "[DEBUG] HOST_IP: $HOST_IP"
echo "[DEBUG] FOLLOWER_HTTP: $FOLLOWER_HTTP"
echo "[DEBUG] SIF: $SIF"
echo "[DEBUG] GENESIS_JSON: $GENESIS_JSON"
echo "[DEBUG] ======================================================="

# --------- Helpers ----------
exe() {
  if [[ -n "${SIF:-}" && -f "${SIF}" ]]; then
    # Use array to properly handle arguments with spaces
    apptainer exec "$SIF" "$@"
  else
    "$@"
  fi
}

wait_for_ipc() {
  local ipc="$1" timeout="${2:-90}" t=0
  echo "[DEBUG] wait_for_ipc: Starting to wait for IPC socket: $ipc"
  echo "[DEBUG] wait_for_ipc: Timeout set to $timeout seconds"
  
  while [[ ! -S "$ipc" && $t -lt $((2*timeout)) ]]; do
    echo "[DEBUG] wait_for_ipc: Attempt $t - IPC socket not ready, waiting..."
    sleep 0.5; ((t++))
  done
  
  if [[ -S "$ipc" ]]; then
    echo "[DEBUG] wait_for_ipc: SUCCESS - IPC socket is ready: $ipc"
    return 0
  else
    echo "[DEBUG] wait_for_ipc: ERROR - Timed out waiting for IPC $ipc after $timeout seconds"
    return 1
  fi
}

wait_for_http() {
  local url="$1" timeout="${2:-60}" t=0
  echo "[DEBUG] wait_for_http: Starting to wait for HTTP endpoint: $url"
  echo "[DEBUG] wait_for_http: Timeout set to $timeout seconds"
  
  while ! curl -fsS -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
           "$url" >/dev/null 2>&1; do
    echo "[DEBUG] wait_for_http: Attempt $t - HTTP endpoint not ready, waiting..."
    sleep 1; ((t++))
    if [[ $t -ge $timeout ]]; then
      echo "[DEBUG] wait_for_http: ERROR - Timed out waiting for HTTP $url after $timeout seconds"
      return 1
    fi
  done
  
  echo "[DEBUG] wait_for_http: SUCCESS - HTTP endpoint is ready: $url"
  return 0
}

mk_datadir() {
  local node_id="$1"
  mkdir -p "$WORKDIR/nodes/$node_id/keystore"
  
  # Copy pre-generated keystore for this node
  # For node 0 (miner), use keystore 5 which corresponds to the first authorized signer
  # For other nodes, use their node ID as keystore ID
  local keystore_id=$node_id
  if [ "$node_id" -eq 0 ]; then
    keystore_id=5
  fi
  
  local keystore_src="$MAINFOLDER/argos-blockchain/geth/files/keystores/$keystore_id"
  if [[ -d "$keystore_src" ]]; then
    echo "[DEBUG] Copying keystore $keystore_id from $keystore_src to $WORKDIR/nodes/$node_id/keystore/"
    cp -r "$keystore_src/"* "$WORKDIR/nodes/$node_id/keystore/" 2>/dev/null || true
  else
    echo "[WARN] No pre-generated keystore found at $keystore_src"
  fi
}

init_genesis_if_needed() {
  local node_id="$1"
  local d="$WORKDIR/nodes/$node_id"
  echo "[DEBUG] Checking genesis for node $node_id at $d"
  echo "[DEBUG] Genesis file: $GENESIS_JSON"
  echo "[DEBUG] Genesis file exists: $(test -f "$GENESIS_JSON" && echo "YES" || echo "NO")"
  
  if [[ ! -f "$d/geth/chaindata/CURRENT" ]]; then
    echo "[DEBUG] Node $node_id: No existing chaindata, initializing with genesis"
    if [[ -n "${SIF:-}" && -f "${SIF}" ]]; then
      echo "[DEBUG] Node $node_id: Using apptainer to init genesis"
      apptainer exec "$SIF" geth --datadir "$d" init "$GENESIS_JSON"
    else
      echo "[DEBUG] Node $node_id: Using native geth to init genesis"
      geth --datadir "$d" init "$GENESIS_JSON"
    fi
  else
    echo "[DEBUG] Node $node_id: Existing chaindata found, skipping genesis init"
    echo "[DEBUG] Node $node_id: Existing chaindata contents:"
    ls -la "$d/geth/chaindata/" 2>/dev/null | head -5 || echo "Cannot list chaindata"
  fi
}

LOGDIR="$WORKDIR/logs"
mkdir -p "$WORKDIR/nodes" "$LOGDIR"
for node_id in $(seq 0 $((NUM_NODES-1))); do mk_datadir "$node_id"; done

# --------- Node 0 (bootstrap) ----------
BOOT_P2P="$P2P_BASE"
BOOT_HTTP="$HTTP_BASE"
BOOT_DIR="$WORKDIR/nodes/0"
BOOT_IPC="$BOOT_DIR/geth.ipc"

init_genesis_if_needed 0

echo "[geth] starting node0 p2p=$BOOT_P2P http=$BOOT_HTTP natip=$HOST_IP"
if [[ -n "${SIF:-}" && -f "${SIF}" ]]; then
  echo "[DEBUG] About to start node0 with apptainer..."
  apptainer exec "$SIF" geth \
    --datadir "$BOOT_DIR" \
    --networkid "$NETWORK_ID" \
    --port "$BOOT_P2P" \
    --nat "extip:$HOST_IP" \
    --http \
    --http.addr "0.0.0.0" \
    --http.port "$BOOT_HTTP" \
    --http.api "eth,net,web3,txpool,admin,miner,clique" \
    --miner.etherbase 0x036d6b4da0b4eeb9d312e958c2937d9016765f50 \
    --mine \
    --allow-insecure-unlock \
    --unlock "0x036d6b4da0b4eeb9d312e958c2937d9016765f50" \
    --password <(echo "") \
    --authrpc.port 8551 \
    --syncmode full \
    --verbosity 3 \
    --ipcpath "$BOOT_IPC" \
    --nodiscover \
    --nousb \
    >"$LOGDIR/node0.log" 2>&1 &
  NODE0_PID=$!
  echo "[DEBUG] Node0 started with PID=$NODE0_PID"
else
  echo "[DEBUG] About to start node0 with native geth..."
  geth \
    --datadir "$BOOT_DIR" \
    --networkid "$NETWORK_ID" \
    --port "$BOOT_P2P" \
    --nat "extip:$HOST_IP" \
    --http \
    --http.addr "0.0.0.0" \
    --http.port "$BOOT_HTTP" \
    --http.api "eth,net,web3,txpool,admin,miner,clique" \
    --miner.etherbase 0x036d6b4da0b4eeb9d312e958c2937d9016765f50 \
    --mine \
    --allow-insecure-unlock \
    --unlock "0x036d6b4da0b4eeb9d312e958c2937d9016765f50" \
    --password <(echo "") \
    --authrpc.port 8551 \
    --syncmode full \
    --verbosity 3 \
    --ipcpath "$BOOT_IPC" \
    --nodiscover \
    --nousb \
    >"$LOGDIR/node0.log" 2>&1 &
    --verbosity 3 \
    --ipcpath "$BOOT_IPC" \
    --nodiscover \
    --nousb \
    >"$LOGDIR/node0.log" 2>&1 &
    --verbosity 3 \
    --ipcpath "$BOOT_IPC" \
    --nodiscover \
    --nousb \
    >"$LOGDIR/node0.log" 2>&1 &
  NODE0_PID=$!
  echo "[DEBUG] Node0 started with PID=$NODE0_PID"
fi

echo "[DEBUG] Node0 startup command completed, proceeding to wait functions..."

# Give node0 a moment to fully initialize before checking for IPC
echo "[DEBUG] Waiting 5 seconds for node0 to fully initialize..."
sleep 5

# Wait for readiness (IPC then HTTP)
echo "[DEBUG] About to call wait_for_ipc with: $BOOT_IPC"
echo "[DEBUG] Checking if IPC file exists before wait: $(ls -la $BOOT_IPC 2>/dev/null || echo 'NOT FOUND')"
wait_for_ipc "$BOOT_IPC" 120
echo "[DEBUG] IPC wait completed successfully"

echo "[DEBUG] About to call wait_for_http with: http://127.0.0.1:${BOOT_HTTP}"
wait_for_http "http://127.0.0.1:${BOOT_HTTP}" 60
echo "[DEBUG] HTTP wait completed successfully"

# Start mining on node0 (needed for Clique POA to seal blocks) via HTTP RPC
echo "[DEBUG] Starting Clique mining on node0 via HTTP RPC..."
MINER_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"miner_start","params":[],"id":1}' \
  "http://127.0.0.1:${BOOT_HTTP}")
echo "[DEBUG] Miner start result: $MINER_RESULT"

echo "[DEBUG] About to start enode retrieval section"

# Read enode via HTTP API instead of IPC to avoid apptainer command-line issues
echo "[DEBUG] Attempting to retrieve enode from node0 via HTTP API..."
echo "[DEBUG] Using curl to get enode from http://127.0.0.1:${BOOT_HTTP}"

# Get the full JSON response first for debugging
JSON_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  "http://127.0.0.1:${BOOT_HTTP}")

echo "[DEBUG] Full JSON response: $JSON_RESPONSE"

# Extract enode with better error handling
RAW_ENODE=$(echo "$JSON_RESPONSE" | grep -o '"enode://[^"]*"' | tr -d '"' || echo "")

if [[ -z "$RAW_ENODE" ]]; then
  echo "[DEBUG] ERROR: Failed to extract enode from JSON response"
  echo "[DEBUG] Trying alternative extraction method..."
  RAW_ENODE=$(echo "$JSON_RESPONSE" | sed -n 's/.*"enode":"\([^"]*\)".*/\1/p' || echo "")
fi

if [[ -z "$RAW_ENODE" ]]; then
  echo "[DEBUG] FATAL: Could not retrieve enode from node0"
  exit 1
fi

echo "[DEBUG] Raw enode retrieved: $RAW_ENODE"

ENODE=$(echo "$RAW_ENODE" \
  | sed -E "s/@\[::\]/@$HOST_IP/; s/@127\.0\.0\.1/@$HOST_IP/; s/\?discport=[0-9]+/?discport=$BOOT_P2P/; t; s/$/?discport=$BOOT_P2P/")

echo "[DEBUG] Processed enode: $ENODE"
echo "[geth] node0 enode: $ENODE"

# --------- Followers (1..N-1) ----------
echo "[DEBUG] Starting follower node setup for nodes 1 to $((NUM_NODES-1))"
for i in $(seq 1 $((NUM_NODES-1))); do
  echo "[DEBUG] Setting up follower node $i"
  d="$WORKDIR/nodes/$i"
  echo "[DEBUG] Node $i: datadir = $d"
  init_genesis_if_needed "$i"
  mkdir -p "$d/geth"
  printf '[\n  "%s"\n]\n' "$ENODE" > "$d/geth/static-nodes.json"
  echo "[DEBUG] Node $i: created static-nodes.json with enode: $ENODE"
done

echo "[DEBUG] Starting follower node processes"
for i in $(seq 1 $((NUM_NODES-1))); do
  echo "[DEBUG] Processing follower node $i"
  P2P=$((P2P_BASE + i))
  DIR="$WORKDIR/nodes/$i"
  IPC="$DIR/geth.ipc"
  
  echo "[DEBUG] Node $i: P2P_PORT=$P2P, DIR=$DIR, IPC=$IPC"

  # HTTP on followers only if requested
  if [[ "$FOLLOWER_HTTP" == "1" ]]; then
    HTTP=$((HTTP_BASE + i))
    AUTHRPC_PORT=$((8551 + i))
    echo "[DEBUG] Node $i: FOLLOWER_HTTP=1, HTTP_PORT=$HTTP, AUTHRPC_PORT=$AUTHRPC_PORT"
    echo "[geth] starting node $i p2p=$P2P http=$HTTP authrpc=$AUTHRPC_PORT"
    
    if [[ -n "${SIF:-}" && -f "${SIF}" ]]; then
      echo "[DEBUG] Node $i: Using apptainer with SIF=$SIF"
      echo "[DEBUG] Node $i: About to execute apptainer command..."
      apptainer exec "$SIF" geth \
        --datadir "$DIR" \
        --networkid "$NETWORK_ID" \
        --port "$P2P" \
        --nat "extip:$HOST_IP" \
        --http \
        --http.addr "0.0.0.0" \
        --http.port "$HTTP" \
        --http.api "eth,net,web3,txpool" \
        --authrpc.port "$AUTHRPC_PORT" \
        --syncmode full \
        --verbosity 2 \
        --nodiscover \
        --ipcpath "$IPC" \
        --nousb \
        >"$LOGDIR/node$i.log" 2>&1 &
      NODE_PID=$!
      echo "[DEBUG] Node $i: Started with PID=$NODE_PID"
    else
      echo "[DEBUG] Node $i: Using native geth (no container)"
      geth \
        --datadir "$DIR" \
        --networkid "$NETWORK_ID" \
        --port "$P2P" \
        --nat "extip:$HOST_IP" \
        --http \
        --http.addr "0.0.0.0" \
        --http.port "$HTTP" \
        --http.api "eth,net,web3,txpool" \
        --authrpc.port "$AUTHRPC_PORT" \
        --syncmode full \
        --verbosity 2 \
        --nodiscover \
        --ipcpath "$IPC" \
        --nousb \
        >"$LOGDIR/node$i.log" 2>&1 &
      NODE_PID=$!
      echo "[DEBUG] Node $i: Started with PID=$NODE_PID"
    fi
  else
    AUTHRPC_PORT=$((8551 + i))
    echo "[DEBUG] Node $i: FOLLOWER_HTTP=0, no HTTP endpoint, AUTHRPC_PORT=$AUTHRPC_PORT"
    echo "[geth] starting node $i p2p=$P2P (no HTTP) authrpc=$AUTHRPC_PORT"
    
    if [[ -n "${SIF:-}" && -f "${SIF}" ]]; then
      echo "[DEBUG] Node $i: Using apptainer with SIF=$SIF (no HTTP)"
      apptainer exec "$SIF" geth \
        --datadir "$DIR" \
        --networkid "$NETWORK_ID" \
        --port "$P2P" \
        --nat "extip:$HOST_IP" \
        --authrpc.port "$AUTHRPC_PORT" \
        --syncmode full \
        --verbosity 2 \
        --nodiscover \
        --ipcpath "$IPC" \
        --nousb \
        >"$LOGDIR/node$i.log" 2>&1 &
      NODE_PID=$!
      echo "[DEBUG] Node $i: Started with PID=$NODE_PID (no HTTP)"
    else
      echo "[DEBUG] Node $i: Using native geth (no container, no HTTP)"
      geth \
        --datadir "$DIR" \
        --networkid "$NETWORK_ID" \
        --port "$P2P" \
        --nat "extip:$HOST_IP" \
        --authrpc.port "$AUTHRPC_PORT" \
        --syncmode full \
        --verbosity 2 \
        --nodiscover \
        --ipcpath "$IPC" \
        --nousb \
        >"$LOGDIR/node$i.log" 2>&1 &
      NODE_PID=$!
      echo "[DEBUG] Node $i: Started with PID=$NODE_PID (no HTTP)"
    fi
  fi
  
  # Wait a moment and check if the process is still running
  sleep 1
  if kill -0 $NODE_PID 2>/dev/null; then
    echo "[DEBUG] Node $i: Process $NODE_PID is running successfully"
  else
    echo "[DEBUG] Node $i: ERROR - Process $NODE_PID has died!"
    echo "[DEBUG] Node $i: Last 10 lines of log:"
    tail -10 "$LOGDIR/node$i.log" 2>/dev/null || echo "[DEBUG] Node $i: No log file found"
  fi
done

echo "[DEBUG] Completed follower node startup loop"
echo "[DEBUG] Checking which log files were created:"
ls -la "$LOGDIR/" || echo "[DEBUG] No log directory found"

echo "[DEBUG] Checking which processes are running:"
ps aux | grep "geth.*nodes" | grep -v grep || echo "[DEBUG] No geth processes found"

echo "[geth] launched ${NUM_NODES} nodes (node0 JSON-RPC on 127.0.0.1:${BOOT_HTTP}); logs → $LOGDIR"
