#!/usr/bin/env python3
"""
Simple test script to verify Web3 connection and basic functionality
"""
import os
import sys
import time

# Set up environment
os.environ['EXPERIMENTFOLDER'] = '/home/cug/thesis/blockchain-simulations/FloorEstimation'
os.environ['HPC_MODE'] = '1'
os.environ['GETH_HOST'] = '127.0.0.1'
os.environ['GETH_HTTP_PORT'] = '8545'

sys.path.insert(0, '/home/cug/thesis/blockchain-simulations/FloorEstimation/controllers')

def test_web3_connection():
    try:
        from console import init_web3
        print("Testing Web3 connection...")
        
        # Test connection
        w3 = init_web3('127.0.0.1')
        if w3 and w3.isConnected():
            print("✓ Web3 connected successfully")
            print(f"✓ Client version: {w3.clientVersion}")
            print(f"✓ Block number: {w3.eth.block_number}")
            return True
        else:
            print("✗ Web3 connection failed")
            return False
            
    except Exception as e:
        print(f"✗ Error testing Web3: {e}")
        return False

def test_imports():
    try:
        from aux import Timer, Peer, Logger
        from erandb import ERANDB
        print("✓ All required imports successful")
        return True
    except Exception as e:
        print(f"✗ Import error: {e}")
        return False

if __name__ == "__main__":
    print("=== Testing Blockchain Simulation Components ===")
    
    # Test 1: Basic imports
    print("\n1. Testing imports...")
    import_success = test_imports()
    
    # Test 2: Web3 connection
    print("\n2. Testing Web3 connection...")
    web3_success = test_web3_connection()
    
    print("\n=== Summary ===")
    print(f"Imports: {'✓ PASS' if import_success else '✗ FAIL'}")
    print(f"Web3:    {'✓ PASS' if web3_success else '✗ FAIL'}")
    
    if import_success and web3_success:
        print("\n🎉 All tests passed! The system should work.")
        sys.exit(0)
    else:
        print("\n❌ Some tests failed. Check the issues above.")
        sys.exit(1)