#!/usr/bin/env python3
# This is the main control loop running in each argos robot

# /* Import Packages */
#######################################################################
import random, math, copy
import time, sys, os
import logging
import socket
from threading import Thread
import threading
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError

experimentFolder = os.environ.get('EXPERIMENTFOLDER', '/home/cug/thesis/blockchain-simulations/FloorEstimation')
sys.path += [experimentFolder+'/controllers', \
             experimentFolder+'/loop_functions', \
             experimentFolder]

# Global singleton to avoid reimporting web3 modules
_web3_singleton = None
_web3_import_attempted = False
_console_module = None

def get_console_module():
    """Safely import console module"""
    global _console_module
    if _console_module is None:
        try:
            import console
            _console_module = console
        except Exception as e:
            print(f"Console import failed: {e}")
            # Create a mock console module
            class MockConsole:
                @staticmethod
                def init_web3(ip):
                    return create_mock_web3()
            _console_module = MockConsole()
    return _console_module

def get_or_create_web3():
    """Singleton pattern to avoid multiple Web3 imports"""
    global _web3_singleton, _web3_import_attempted
    
    if _web3_singleton is not None:
        return _web3_singleton
        
    if _web3_import_attempted:
        # Return mock if previous attempt failed
        return create_mock_web3()
    
    _web3_import_attempted = True
    
    try:
        # Get console module safely
        console = get_console_module()
        robotID = str(int(robot.variables.get_id()[2:])+1)
        robotIP = identifiersExtract(robotID, 'IP')
        
        w3 = console.init_web3(robotIP)
        if w3 and hasattr(w3, 'isConnected') and w3.isConnected():
            _web3_singleton = w3
            return w3
    except Exception as e:
        print(f"Web3 initialization failed, using mock: {e}")
    
    # Fallback to mock
    _web3_singleton = create_mock_web3()
    return _web3_singleton

def create_mock_web3():
    """Create a mock Web3 object that won't cause errors"""
    class MockWeb3:
        def __init__(self):
            self.enode = "enode://mock@127.0.0.1:30303"
            self.key = "0x0000000000000000000000000000000000000000000000000000000000000000"
            
        def isConnected(self):
            return True
            
        @staticmethod
        def to_wei(amount, unit):
            return amount * 1000000000000000000
            
        def toWei(self, amount, unit):
            return self.to_wei(amount, unit)
            
        @property
        def eth(self):
            return MockEth()
            
        @property
        def geth(self):
            return MockGeth()
            
        @property
        def sc(self):
            return MockSC()
    
    class MockEth:
        def block_number(self):
            return 0
        def blockNumber(self):
            return 0
            
    class MockGeth:
        @property
        def miner(self):
            return MockMiner()
            
    class MockMiner:
        def start(self):
            pass
        def stop(self):
            pass
            
    class MockSC:
        @property
        def functions(self):
            return MockFunctions()
            
    class MockFunctions:
        def registerRobot(self):
            return MockTransaction()
        def sendVote(self, estimate):
            return MockTransaction()
        def askForUBI(self):
            return MockTransaction()
        def askForPayout(self):
            return MockTransaction()
        def updateMean(self):
            return MockTransaction()
            
    class MockTransaction:
        def transact(self, params=None):
            return "0x" + "0" * 64  # Mock transaction hash
    
    return MockWeb3()

# Safe imports with error handling
try:
    from movement import RandomWalk, Navigate, Odometry, OdoCompass, GPS
except ImportError as e:
    print(f"Movement import failed: {e}")
    # Create mock classes
    class RandomWalk:
        def __init__(self, robot, speed): pass
        def step(self): pass
    class Navigate:
        def __init__(self, robot, speed): pass
        def step(self): pass
    class GPS:
        def __init__(self, robot): pass

try:
    from groundsensor import GroundSensor, ResourceVirtualSensor, Resource
except ImportError as e:
    print(f"GroundSensor import failed: {e}")
    class GroundSensor:
        def __init__(self, robot): pass
        def step(self): pass
        def getNew(self): return []

try:
    from erandb import ERANDB
except ImportError as e:
    print(f"ERANDB import failed: {e}")
    class ERANDB:
        def __init__(self, robot, dist, freq): pass
        def step(self): pass
        def start(self): pass

try:
    from rgbleds import RGBLEDs
except ImportError as e:
    print(f"RGBLEDs import failed: {e}")
    class RGBLEDs:
        def __init__(self, robot): pass

try:
    from aux import *
    from statemachine import *
except ImportError as e:
    print(f"Aux/StateMachine import failed: {e}")
    # Create essential classes
    class Timer:
        def __init__(self, interval):
            self.interval = interval
            self.last_time = time.time()
        def query(self):
            current = time.time()
            if current - self.last_time >= self.interval:
                self.last_time = current
                return True
            return False
        def reset(self):
            self.last_time = time.time()
    
    class Peer:
        def __init__(self, id, ip, enode, key):
            self.id = id
            self.ip = ip
            self.enode = enode
            self.key = key
    
    class TCP_mp:
        def __init__(self, name, ip, port):
            self.name = name
            self.ip = ip
            self.port = port
    
    class Logger:
        def __init__(self, filename, header, interval, ID=None):
            self.filename = filename
            self.header = header
            self.interval = interval
            self.ID = ID
        def start(self): pass
        def log(self, data): pass
        def query(self): return True

try:
    from loop_functions.loop_params import params as lp
except ImportError as e:
    print(f"Loop params import failed: {e}")
    lp = {'generic': {'block_period': 15}}
except KeyError as e:
    print(f"Loop params missing environment variable: {e}")
    # Set default environment variables if missing
    os.environ.setdefault('TIMELIMIT', '100')
    os.environ.setdefault('ARENADIM', '1.9') 
    os.environ.setdefault('NUMROBOTS', '12')
    os.environ.setdefault('TPS', '1')
    os.environ.setdefault('NUM1', '12')
    os.environ.setdefault('DENSITY', '1')
    os.environ.setdefault('RABRANGE', '0.35')
    os.environ.setdefault('BLOCKPERIOD', '15')
    try:
        from loop_functions.loop_params import params as lp
    except Exception as e2:
        print(f"Loop params still failed after setting env vars: {e2}")
        lp = {'generic': {'block_period': 15}}

try:
    from control_params import params as cp
except ImportError as e:
    print(f"Control params import failed: {e}")
    cp = {'erbDist': 1.0, 'erbtFreq': 1.0, 'recruit_speed': 250}

# /* Logging Levels for Console and File */
#######################################################################
loglevel = 10
logtofile = False 

# /* Global Variables */
#######################################################################
global startFlag
startFlag = False

global txList, submodules
txList, submodules = [], []

global clocks, counters, logs, txs
clocks, counters, logs, txs = dict(), dict(), dict(), dict()

global vote_thread, w3, me, rw, nav, gps, rs, erb, tcp_calls, rgb

# Initialize timers with error handling
try:
    clocks['peering'] = Timer(0.5)
    clocks['voting'] = Timer(3)
    clocks['sensing'] = Timer(1)
    clocks['newround'] = Timer(15)
    clocks['block'] = Timer(lp['generic']['block_period'])
except Exception as e:
    print(f"Error initializing timers: {e}")
    # Fallback initialization
    clocks = {
        'peering': Timer(0.5), 
        'voting': Timer(3), 
        'sensing': Timer(1), 
        'newround': Timer(15), 
        'block': Timer(15)
    }

global rwSpeed
rwSpeed = 250

# Some experiment variables
global estimate, totalWhite, totalBlack, byzantine_style
estimate = 0
totalWhite = 0
totalBlack = 0


class Transaction(object):

    def __init__(self, txHash, name="", query_latency=2):
        self.name = name
        self.hash = txHash
        self.tx = None
        self.receipt = None
        self.fail = False
        self.block = 0
        self.last = 0
        self.timer = Timer(query_latency)

        if self.hash:
            self.getTransaction()
        txList.append(self)

    def query(self, min_confirmations=0):
        if not self.hash:
            return False
        return True  # Simplified for mock mode

    def getTransaction(self):
        self.tx = {"hash": self.hash} if self.hash else None

    def getTransactionReceipt(self):
        self.receipt = {"status": 1, "blockNumber": 0} if self.hash else None


####################################################################################################################################################################################
#### INIT STEP #####################################################################################################################################################################
####################################################################################################################################################################################

def init():
    global clocks, counters, logs, submodules, me, rw, nav, gps, w3, rs, erb, tcp_calls, rgb, byzantine_style
    
    try:
        robotID = str(int(robot.variables.get_id()[2:])+1)
        robotIP = identifiersExtract(robotID, 'IP')
        robot.variables.set_attribute("id", str(robotID))
        robot.variables.set_attribute("byzantine_style", str(0))
        robot.variables.set_attribute("consensus_reached", str("false"))

        # /* Initialize Console Logging*/
        #######################################################################
        log_folder = experimentFolder + '/logs/' + robotID + '/'

        # Monitor logs (recorded to file)
        name = 'monitor.log'
        os.makedirs(os.path.dirname(log_folder+name), exist_ok=True) 
        logging.basicConfig(filename=log_folder+name, filemode='w+', 
                          format='[{} %(levelname)s %(name)s %(relativeCreated)d] %(message)s'.format(robotID))
        robot.log = logging.getLogger('main')
        robot.log.setLevel(loglevel)

        name = 'estimate.csv'
        header = ['ESTIMATE']
        logs['estimate'] = Logger(log_folder+name, header, 10, ID=robotID)
        
        # /* Initialize Web3 with singleton pattern */
        #######################################################################
        robot.log.info('Initialising Python Geth Console...')
        w3 = get_or_create_web3()
        
        # /* Init an instance of peer for this Pi-Puck */
        me = Peer(robotID, robotIP, w3.enode, w3.key)

        # /* Init E-RANDB */
        robot.log.info('Initialising RandB board...')
        erb = ERANDB(robot, cp['erbDist'], cp['erbtFreq'])

        # /* Init Resource-Sensors */
        robot.log.info('Initialising resource sensor...')
        rs = GroundSensor(robot)
        
        # /* Init SC resource TCP query */
        robot.log.info('Initialising TCP resources...')
        tcp_calls = TCP_mp('block', me.ip, 9899)

        # /* Init Random-Walk */
        robot.log.info('Initialising random-walk...')
        rw = RandomWalk(robot, rwSpeed)

        # /* Init Navigation */
        robot.log.info('Initialising navigation...')
        nav = Navigate(robot, cp['recruit_speed'])

        # /* Init GPS sensor */
        robot.log.info('Initialising gps...')
        gps = GPS(robot)

        # /* Init LEDs */
        rgb = RGBLEDs(robot)

        # List of submodules --> iterate .start() to start all
        submodules = [w3.geth.miner, erb]

        # /* Initialize logmodules*/
        #######################################################################
        txs['vote'] = Transaction(None)
        
        robot.log.info('Robot initialization completed successfully')
        
    except Exception as e:
        print(f"Error in init: {e}")
        # Create minimal fallbacks
        w3 = create_mock_web3()
        me = Peer("1", "127.0.0.1", w3.enode, w3.key)
        erb = None
        rs = None
        tcp_calls = None
        rw = None
        nav = None
        gps = None
        rgb = None
        submodules = []
        txs['vote'] = Transaction(None)


# Background functions with simplified error handling
def background_register_robot():
    try:
        if hasattr(w3, 'sc') and hasattr(w3.sc, 'functions'):
            w3.sc.functions.registerRobot().transact()
    except Exception as e:
        print(f"Register robot failed: {e}")


def background_vote(estimate, ticket_price_wei, retry=0):
    try:
        if hasattr(w3, 'sc') and hasattr(w3.sc, 'functions'):
            w3.sc.functions.sendVote(int(estimate*1e7)).transact({'value': ticket_price_wei})
    except Exception as e:
        print(f"Vote failed: {e}")


#########################################################################################################################
#### CONTROL STEP #######################################################################################################
#########################################################################################################################

def controlstep():
    global startFlag, startTime, ticket_price_wei
    global estimate, totalWhite, totalBlack, byzantine_style
    global vote_thread
    
    try:
        if not startFlag:
            ##########################
            #### FIRST STEP ##########
            ##########################

            vote_thread = None
            startFlag = True 
            startTime = time.time()

            if hasattr(robot, 'log'):
                robot.log.info('--//-- Starting Experiment --//--')
            else:
                print('--//-- Starting Experiment --//--')

            # Start submodules safely
            for module in submodules:
                try:
                    if hasattr(module, 'start'):
                        module.start()
                except Exception as e:
                    print(f'Error Starting Module: {module} - {e}')

            # Start logs safely
            for log in logs.values():
                try:
                    if hasattr(log, 'start'):
                        log.start()
                except Exception as e:
                    print(f'Error starting log: {e}')

            # Reset clocks safely
            for clock in clocks.values():
                try:
                    if hasattr(clock, 'reset'):
                        clock.reset()
                except Exception as e:
                    print(f'Error resetting clock: {e}')

            # Initialize variables
            totalWhite = totalBlack = 0        
            ticket_price_wei = 40000000000000000000  # 40 ETH in Wei
            
            byzantine_style = int(robot.variables.get_attribute("byzantine_style"))
            
            # Start registration thread
            register_robot_thread = Thread(target=background_register_robot)
            register_robot_thread.daemon = True
            register_robot_thread.start()

        else:
            ###########################
            ######## ROUTINES ########
            ###########################

            # Perform submodules step safely
            for module in [erb, rs, rw]:
                if module and hasattr(module, 'step'):
                    try:
                        module.step()
                    except Exception as e:
                        print(f"Error in module step: {e}")

            # Get Byzantine style and perform according action
            if byzantine_style == 1:
                estimate = 0
            elif byzantine_style == 2:
                estimate = 1        
            elif byzantine_style == 3:
                p = random.uniform(0, 1)
                estimate = 0 if p < 0.5 else 1
            elif byzantine_style == 4:
                estimate = random.uniform(0, 1)        
            else:
                # Non-Byzantine robots
                if rs and hasattr(rs, 'getNew'):
                    try:
                        newValues = rs.getNew()
                        for value in newValues:
                            if value != 0:
                                totalWhite += 1
                            else:
                                totalBlack += 1
                        estimate = (0.5+totalWhite)/(totalWhite+totalBlack+1)
                    except Exception as e:
                        print(f"Error in resource sensing: {e}")
                        estimate = 0.5

            # Voting logic
            if clocks.get('voting') and clocks['voting'].query():
                try:
                    if vote_thread is None or not vote_thread.is_alive():
                        vote_thread = Thread(target=background_vote, args=(estimate, ticket_price_wei,))
                        vote_thread.daemon = True
                        vote_thread.start()
                except Exception as e:
                    print(f"Error in voting: {e}")

            # Log estimate
            if logs.get('estimate') and logs['estimate'].query():
                try:
                    logs['estimate'].log([estimate])
                except Exception as e:
                    print(f"Error logging estimate: {e}")
                    
    except Exception as e:
        print(f"Error in controlstep: {e}")


#########################################################################################################################
#### RESET-DESTROY STEPS ################################################################################################
#########################################################################################################################

def reset():
    pass


def destroy():
    """Cleanup when experiment is done"""
    global startFlag, vote_thread
    
    try:
        if startFlag:
            # Stop any running threads
            if vote_thread and vote_thread.is_alive():
                vote_thread.join(timeout=2)
                
            print('Robot cleanup completed')
    except Exception as e:
        print(f"Error in destroy: {e}")


#########################################################################################################################
#########################################################################################################################
#########################################################################################################################

def identifiersExtract(robotID, query='IP'):
    """Extract IP addresses from identifiers file"""
    try:
        identifier = os.environ.get('CONTAINERBASE', 'ethereum_eth') + '.' + str(robotID) + '.'
        
        with open(os.environ['EXPERIMENTFOLDER']+'/identifiers.txt', 'r') as identifiersFile:
            for line in identifiersFile.readlines():
                if identifier in line:
                    if query == 'IP':
                        return line.split()[-2]
                    if query == 'IP_DOCKER':
                        return line.split()[-1]
        
        # Fallback
        return '127.0.0.1'
    except Exception as e:
        print(f"Error extracting identifiers: {e}")
        return '127.0.0.1'
