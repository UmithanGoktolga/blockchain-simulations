# HPC Migration Status Report

**Date:** October 5, 2025  
**Current Job:** 269 (cancelled)  
**Status:** Blockchain infrastructure working, but consensus limitation identified

---

## ✅ ACHIEVEMENTS

### 1. **Blockchain Node Startup - WORKING**
- ✅ All 5 nodes start successfully with unique ports
- ✅ Genesis POA initialization working (Chain ID 1515)
- ✅ Keystores correctly copied to each node
- ✅ HTTP RPC APIs accessible on ports 8545-8549
- ✅ P2P network configured on ports 30303-30307
- ✅ AuthRPC ports configured uniquely (8551-8555)

### 2. **Geth Version - RESOLVED**
- ✅ Successfully downgraded from v1.16.2 to v1.10.26
- ✅ Pre-merge Geth with native Clique POA support
- ✅ Apptainer container rebuilt with correct version
- ✅ Container includes Python packages: web3, rpyc, hexbytes

### 3. **Genesis Configuration - FIXED**
- ✅ Removed `terminalTotalDifficulty` field that was triggering The Merge
- ✅ Clique POA consensus properly configured
- ✅ Period: 15 seconds, Epoch: 30000
- ✅ 12 authorized signers in extraData

### 4. **Mining Infrastructure - WORKING**
- ✅ Account unlocking successful: `0x036d6b4da0b4eeb9d312e958c2937d9016765f50`
- ✅ Mining threads active (16 threads)
- ✅ First block successfully sealed (Block #1)
- ✅ Log messages confirm: "Successfully sealed new block number=1"

### 5. **ARGoS Simulation - STARTS**
- ✅ Simulation loads and initializes
- ✅ 5 robots configured (fb0-fb4)
- ✅ Controllers load correctly
- ✅ Physics engine running (10 iterations per tick)

---

## ⚠️ IDENTIFIED ISSUES

### **CRITICAL: Clique Single-Signer Limitation**

**Problem:**  
- Clique consensus requires `(N/2)+1` blocks between signatures from the same signer
- With 12 authorized signers in genesis, node must wait for 7 other signers before sealing block #2
- Currently only node 0 (keystore 5) is configured as a signer
- Nodes 1-4 use keystores 1-4, which are NOT in the authorized signers list
- Result: Block production stops after block #1

**Evidence:**
```
INFO [DATE] Signed recently, must wait for others        
Block number: 1 (stuck)
```

**Impact:**
- Simulation runs but blockchain doesn't process transactions
- Smart contracts cannot execute
- Simulation likely times out waiting for blockchain operations

---

## 🔍 COMPARISON NEEDED

To proceed, we need to compare this HPC setup with a working Docker version:

### Docker Setup (Need to verify):
- How many nodes run as miners/signers?
- Which keystores are used for each node?
- Are all nodes authorized signers, or just some?
- What is the typical block production rate?
- Does simulation complete successfully?

### HPC Setup (Current):
- Node 0: Miner with keystore 5 (authorized signer `0x036d6b4...`)
- Nodes 1-4: Non-mining followers with keystores 1-4 (NOT authorized)
- Block production: 1 block then stuck
- Simulation: Starts but can't progress due to blockchain

---

## 💡 POSSIBLE SOLUTIONS

### **Option 1: Use Multiple Authorized Signers (Recommended)**
Map the first 5 keystores to the first 5 authorized signers from genesis:
- Node 0 → Keystore 5 → `0x036d6b4da0b4eeb9d312e958c2937d9016765f50` ✅
- Node 1 → Find keystore for `0x05d6edc4ff8ef40321abcf7886bc606ed13327b0`
- Node 2 → Find keystore for `0x0fa9077350fc3ee6924743e1ad9b735c657c455e`
- Node 3 → Find keystore for `0x26cbcac5281b6e159bc3e6c7400af25fa46f246b`
- Node 4 → Find keystore for `0x3662fa93e6c3bcb04b95e5dd7b1266ad9e8a9965`

Enable mining on all 5 nodes with their respective accounts.

**Pros:**
- Matches Clique design (multiple signers)
- Should enable continuous block production
- More realistic distributed consensus

**Cons:**
- Need to find correct keystores for each address
- More complex configuration
- Higher CPU usage (5 miners vs 1)

### **Option 2: Regenerate Genesis with Fewer Signers**
Create new genesis with only the accounts we're actually using:
- Single signer: `0x036d6b4da0b4eeb9d312e958c2937d9016765f50`
- Or 5 signers matching keystores 1-5

**Pros:**
- Simpler configuration
- Single miner can seal blocks continuously

**Cons:**
- Changes genesis hash (incompatible with existing Docker setup)
- May not match research requirements
- Less realistic distributed consensus

### **Option 3: Use PoW or Other Consensus**
Switch from Clique POA to:
- Ethash PoW (mining difficulty adjustable)
- Clique with modified parameters

**Pros:**
- No signer authorization needed
- Any node can mine

**Cons:**
- Major change from existing setup
- May not match research requirements
- More computational overhead

---

## 📋 NEXT STEPS

1. **[IMMEDIATE]** Check Docker configuration:
   - How many nodes run as signers?
   - Which keystores are used?
   - Get reference run with similar parameters

2. **[DECISION]** Choose solution approach:
   - If Docker uses multiple signers → Implement Option 1
   - If Docker uses single signer → Implement Option 2
   - If different consensus → Investigate further

3. **[IMPLEMENTATION]** Based on decision:
   - Update `start-geth.sh` to configure correct keystores
   - Enable mining on appropriate nodes
   - Test block production with `eth_blockNumber`

4. **[VALIDATION]** Run full test:
   - Verify continuous block production
   - Check transaction processing
   - Confirm simulation completes
   - Compare results with Docker version

5. **[OPTIMIZATION]** Once working:
   - Scale to 12 nodes if needed
   - Tune parameters for HPC environment
   - Run full experiment suite

---

## 📁 MODIFIED FILES

### `/home/cug/thesis/blockchain-simulations/FloorEstimation/hpc/geth.def`
- Rebuilt to use Geth v1.10.26-e5eb32ac
- Downloads from gethstore.blob.core.windows.net
- Installs Python packages: web3, rpyc, hexbytes

### `/home/cug/thesis/blockchain-simulations/FloorEstimation/hpc/start-geth.sh`
- Added MAINFOLDER environment variable
- Keystore copying from pre-generated files
- Node 0 uses keystore 5 (authorized signer)
- Mining flags: --mine, --unlock, --password, --miner.etherbase
- Added clique and miner APIs to HTTP

### `/home/cug/thesis/blockchain-simulations/argos-blockchain/geth/files/genesis_poa.json`
- Removed `terminalTotalDifficulty` field
- Backup saved as `genesis_poa.json.backup`

### `/home/cug/thesis/blockchain-simulations/FloorEstimation/experimentconfig.sh`
- LENGTH=5000 (500 seconds at 10 ticks/sec)
- BLOCKPERIOD=15 seconds
- HPC_NUM_NODES=5
- TIMELIMIT=600 seconds

---

## 🔬 TECHNICAL DETAILS

### Authorized Signers in Genesis (12 total):
1. `0x036d6b4da0b4eeb9d312e958c2937d9016765f50` ← **USING (keystore 5)**
2. `0x05d6edc4ff8ef40321abcf7886bc606ed13327b0`
3. `0x0fa9077350fc3ee6924743e1ad9b735c657c455e`
4. `0x26cbcac5281b6e159bc3e6c7400af25fa46f246b`
5. `0x3662fa93e6c3bcb04b95e5dd7b1266ad9e8a9965`
6. `0x5c5f829c4c3e8c4ab97390cb053a456616c27ea3`
7. `0x633462025cf12d347c0df50b2114e65aa364f0a6`
8. `0x77b770ceb4b2537e52f4534bb39e43754eb5b7e5`
9. `0xa4b1b07974bf67f04ec51becabf4ad62106b1dd0`
10. `0xa79160bc038c07678c145f1b5220be15badb13d7`
11. `0xc72b1b70e69d270544369132d53529e37be87742`
12. `0xd4aedd30d11907e10b6353e59685bb7efc14f55d`

### Network Configuration:
- **Network ID:** 456719
- **Chain ID:** 1515
- **P2P Ports:** 30303-30307
- **HTTP Ports:** 8545-8549
- **AuthRPC Ports:** 8551-8555
- **Host IP:** 192.168.1.152

---

## 📊 LOGS LOCATION

- **SLURM logs:** `/home/cug/thesis/blockchain-simulations/FloorEstimation/logs/geth-net-<JOB>_<ARRAY>.{out,err}`
- **Node logs:** `/tmp/ethnet/logs/node{0..4}.log` (temporary, cleaned between runs)
- **Last successful job:** 269 (cancelled after identifying issue)

---

## 🎯 SUCCESS CRITERIA

For HPC migration to be considered successful:
1. ✅ All blockchain nodes start and stay connected
2. ⏳ Blocks are produced continuously (not stuck at block 1)
3. ⏳ Smart contract transactions are processed
4. ⏳ ARGoS simulation completes within TIMELIMIT
5. ⏳ Results match Docker version (within acceptable variance)
6. ⏳ Can scale to 12+ nodes for full experiments

**Current Status:** 1/6 complete

---

## 🤝 COLLABORATION NOTE

Waiting for user decision on approach after comparing with Docker setup. Key question:
**How many nodes run as signers in the working Docker configuration?**
