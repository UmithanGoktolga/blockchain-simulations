#!/bin/bash
# Generate genesis file dynamically for HPC based on number of nodes
# Usage: ./generate-genesis.sh <NUM_NODES> <BLOCK_PERIOD>

set -euo pipefail

NUM_NODES="${1:-5}"
BLOCK_PERIOD="${2:-15}"

MAINFOLDER="${MAINFOLDER:-$HOME/thesis/blockchain-simulations}"
GENESIS_TEMPLATE="$MAINFOLDER/argos-blockchain/geth/files/genesis_poa_template.json"
GENESIS_OUTPUT="$MAINFOLDER/argos-blockchain/geth/files/genesis_poa.json"
KEYSTORES_DIR="$MAINFOLDER/argos-blockchain/geth/files/keystores"

echo "[genesis] Generating genesis for $NUM_NODES nodes with block period ${BLOCK_PERIOD}s"

# Map node IDs to keystore IDs based on the ordering we established
# This ensures the first N nodes use the first N authorized signers
get_keystore_for_node() {
  local node_id="$1"
  case $node_id in
    0) echo 5 ;;
    1) echo 3 ;;
    2) echo 1 ;;
    3) echo 8 ;;
    4) echo 12 ;;
    5) echo 6 ;;
    6) echo 7 ;;
    7) echo 4 ;;
    8) echo 9 ;;
    9) echo 10 ;;
    10) echo 11 ;;
    11) echo 2 ;;
    *) echo "$node_id" ;;
  esac
}

# Get account address from keystore file
get_address_from_keystore() {
  local keystore_id="$1"
  local keystore_file="$KEYSTORES_DIR/$keystore_id/$keystore_id"
  if [[ -f "$keystore_file" ]]; then
    grep -o '"address":"[^"]*"' "$keystore_file" | cut -d'"' -f4
  else
    echo "ERROR: Keystore file not found: $keystore_file" >&2
    return 1
  fi
}

# Build the extraData field for Clique
# Format: 0x + 32 bytes vanity + N*20 bytes addresses + 65 bytes signature
echo "[genesis] Building extraData with $NUM_NODES authorized signers..."

VANITY="0000000000000000000000000000000000000000000000000000000000000000"
SIGNATURE="0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

SIGNERS=""
ALLOC_ACCOUNTS=""

for node_id in $(seq 0 $((NUM_NODES - 1))); do
  keystore_id=$(get_keystore_for_node "$node_id")
  address=$(get_address_from_keystore "$keystore_id")
  
  if [[ -z "$address" ]]; then
    echo "ERROR: Failed to get address for node $node_id (keystore $keystore_id)" >&2
    exit 1
  fi
  
  echo "[genesis] Node $node_id -> Keystore $keystore_id -> Address 0x$address"
  SIGNERS="${SIGNERS}${address}"
  
  # Add to alloc section (pre-fund with 21 ether = 0x1236efcbcbb340000)
  if [[ -n "$ALLOC_ACCOUNTS" ]]; then
    ALLOC_ACCOUNTS="${ALLOC_ACCOUNTS},"
  fi
  ALLOC_ACCOUNTS="${ALLOC_ACCOUNTS}
    \"$address\": {
      \"balance\": \"0x1236efcbcbb340000\"
    }"
done

EXTRA_DATA="0x${VANITY}${SIGNERS}${SIGNATURE}"

echo "[genesis] extraData length: ${#EXTRA_DATA} characters"
echo "[genesis] extraData: $EXTRA_DATA"

# Generate the genesis JSON
cat > "$GENESIS_OUTPUT" << EOF
{
  "config": {
    "chainId": 1515,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "clique": {
      "period": $BLOCK_PERIOD,
      "epoch": 30000
    }
  },
  "nonce": "0x0",
  "timestamp": "0x5b4f",
  "extraData": "$EXTRA_DATA",
  "gasLimit": "0x9000000000000",
  "difficulty": "0x1",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
    "0000000000000000000000000000000000000123": {
      "code": "0x",
      "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
    },${ALLOC_ACCOUNTS}
  },
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
EOF

echo "[genesis] Genesis file generated successfully: $GENESIS_OUTPUT"
echo "[genesis] Chain ID: 1515"
echo "[genesis] Block period: ${BLOCK_PERIOD}s"
echo "[genesis] Number of authorized signers: $NUM_NODES"
echo "[genesis] Clique wait requirement: $((NUM_NODES/2 + 1)) blocks"
