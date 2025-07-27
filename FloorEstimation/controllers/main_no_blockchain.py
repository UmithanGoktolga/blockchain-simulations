#!/usr/bin/env python3
# This is the main control loop running in each argos robot

# /* Import Packages */
#######################################################################
import random, math, copy
import time, sys, os
import logging

experimentFolder = os.environ['EXPERIMENTFOLDER']
sys.path += [os.environ['EXPERIMENTFOLDER']+'/controllers', \
             os.environ['EXPERIMENTFOLDER']+'/loop_functions', \
             os.environ['EXPERIMENTFOLDER']]

from movement import RandomWalk, Navigate, Odometry, OdoCompass, GPS
from groundsensor import GroundSensor, ResourceVirtualSensor, Resource
from erandb import ERANDB
from rgbleds import RGBLEDs
from console import *
from aux import *
from statemachine import *

from loop_functions.loop_params import params as lp
from control_params import params as cp

# /* Logging Levels for Console and File */
#######################################################################
loglevel = 10
logtofile = False 

# /* Global Variables */
#######################################################################
global startFlag
startFlag = False

global txList, submodules
txList,  submodules = [], []

global clocks, counters, logs, txs
clocks, counters, logs, txs = dict(), dict(), dict(), dict()

clocks['estimate'] = Timer(10)
clocks['peering'] = Timer(0.5)
clocks['sensing'] = Timer(1)
clocks['newround'] = Timer(15) # Prevents spamming of newround transactions, 15 is the block time
clocks['block'] = Timer(lp['generic']['block_period'])


global rwSpeed
rwSpeed = 250

# Some experiment variables
global estimate, totalWhite, totalBlack
estimate = 0
totalWhite = 0
totalBlack = 0


class Transaction(object):

    def __init__(self, txHash, robot, name = "", query_latency = 2):
        self.robot = robot
        self.name      = name
        self.hash      = txHash
        self.tx        = None
        self.receipt   = None

        self.fail      = False
        self.block     = w3.eth.blockNumber()
        self.last      = 0
        self.timer     = Timer(query_latency)

        if self.hash:
            self.getTransaction()
        txList.append(self)

    def query(self, min_confirmations = 0):
        confirmations = 0

        if not self.hash:
            return False

        if self.timer.query():
            self.getTransaction()
            self.getTransactionReceipt()
            self.block = w3.eth.blockNumber()

        if not self.tx:
            self.robot.log.warning('Fail: Not found')
            self.fail = True
            return False

        elif not self.receipt:
            return False

        elif not self.receipt['status']:
            self.robot.log.warning('Fail: Status 0')
            self.fail = True
            return False

        else:
            confirmations = self.block - self.receipt['blockNumber']

            if self.last < confirmations:
                self.last = confirmations
                self.robot.log.info('Confirming: %s/%s', confirmations, min_confirmations)
                
            if confirmations >= min_confirmations:
                self.last = 0
                return True
            else:
                return False

    def getTransaction(self):
        try:
            self.tx = w3.eth.getTransaction(self.hash)
        except Exception as e:
            self.tx = None

    def getTransactionReceipt(self):
        try:
            self.receipt = w3.eth.getTransactionReceipt(self.hash)
        except Exception as e:
            self.receipt = None



####################################################################################################################################################################################
#### INIT STEP #####################################################################################################################################################################
####################################################################################################################################################################################

class Controller:
    def __init__(self, robot):
        self.robot = robot

    def init(self):
        global clocks,counters, logs, submodules, me, rw, nav, gps, w3, rs, erb, tcp_calls, rgb
        robotID = str(int(self.robot.variables.get_id()[2:])+1)
        robotIP = identifiersExtract(robotID, 'IP')
        self.robot.variables.set_attribute("id", str(robotID))

        # /* Initialize Console Logging*/
        #######################################################################
        log_folder = experimentFolder + '/logs/' + robotID + '/'

        # Monitor logs (recorded to file)
        name =  'monitor.log'
        os.makedirs(os.path.dirname(log_folder+name), exist_ok=True) 
        logging.basicConfig(filename=log_folder+name, filemode='w+', format='[{} %(levelname)s %(name)s %(relativeCreated)d] %(message)s'.format(robotID))
        self.robot.log = logging.getLogger('main')
        self.robot.log.setLevel(loglevel)

        # /* Initialize submodules */
        #######################################################################
        # # /* Init web3.py */
        self.robot.log.info('Initialising Python Geth Console...')
        w3 = init_web3(robotIP)

        # /* Init an instance of peer for this Pi-Puck */
        me = Peer(robotID, robotIP, w3.enode, w3.key)

        # /* Init E-RANDB __listening process and transmit function
        self.robot.log.info('Initialising RandB board...')
        erb = ERANDB(self.robot, cp['erbDist'] , cp['erbtFreq'])

        #/* Init Resource-Sensors */
        self.robot.log.info('Initialising resource sensor...')
        rs = GroundSensor(self.robot)
        
        #/* Init SC resource TCP query */
        self.robot.log.info('Initialising TCP resources...')
        tcp_calls = TCP_mp('block', me.ip, 9899)

        # /* Init Random-Walk, __walking process */
        self.robot.log.info('Initialising random-walk...')
        rw = RandomWalk(self.robot, rwSpeed)

        # /* Init Navigation, __navigate process */
        self.robot.log.info('Initialising navigation...')
        nav = Navigate(self.robot, cp['recruit_speed'])

        # /* Init GPS sensor */
        self.robot.log.info('Initialising gps...')
        gps = GPS(self.robot)

        # /* Init LEDs */
        rgb = RGBLEDs(self.robot)

        # List of submodules --> iterate .start() to start all
        submodules = [w3.geth.miner, erb]

        # /* Initialize logmodules*/
        #######################################################################
        # Experiment data logs (recorded to file)

        txs['vote'] = Transaction(None, self.robot)

    def controlstep(self):
        global pos, clocks, counters, startFlag, startTime
        global estimate, totalWhite, totalBlack
        
        if not startFlag:
            ##########################
            #### FIRST STEP ##########
            ##########################

            startFlag = True 
            startTime = time.time()

            self.robot.log.info('--//-- Starting Experiment --//--')

            for module in submodules:
                try:
                    module.start()
                except:
                    self.robot.log.critical('Error Starting Module: %s', module)
                    sys.exit()

            for log in logs.values():
                log.start()

            for clock in clocks.values():
                clock.reset()

            # Startup transactions

            totalWhite = totalBlack = 0        

        else:

            ###########################
            ######## ROUTINES ########
            ###########################

            # Send current estimate (but only if the previous one was valid)
            def vote(ether):

                if txs['vote'].query():
                    txs['vote'] = Transaction(None)

                elif txs['vote'].fail:
                    txs['vote'] = Transaction(None)

                # Everything fine, ready to vote!
                elif txs['vote'].hash == None:

                    mean = tcp_calls.request(data = 'mean')
                    print("Voting with ", estimate)
                    print("Mean is ", mean / 1e5)                
                    try:
                        txHash = w3.sc.functions.sendVote(int(estimate*1e7)).transact({'value':ether})
                        txs['vote'] = Transaction(txHash)
                    except Exception as e:
                        print('Failed to vote: (Unexpected)', e)
                        

            def send_to_docker():
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.connect((me.ip, 9898))
                    s.sendall("hi from robot %s" % me.id)
                    data = s.recv(1024)
                    print(data)

            def peering():
                global geth_peer_count
                geth_peer_count = 0
                if clocks['peering'].query(): 

                    peer_IPs = dict()
                    peer_IDs = erb.getNew()
                    for peer_ID in peer_IDs:
                        peer_IPs[peer_ID] = identifiersExtract(peer_ID, 'IP_DOCKER')

                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                        s.connect((me.ip, 9898))
                        s.sendall(str(peer_IPs).encode())
                        data = s.recv(1024)
                        geth_peer_count = int(data)

                     # Turn on LEDs according to geth Peers
                    if geth_peer_count == 0: 
                        rgb.setLED(rgb.all, 3* ['black'])
                    elif geth_peer_count == 1:
                        rgb.setLED(rgb.all, ['red', 'black', 'black'])
                    elif geth_peer_count == 2:
                        rgb.setLED(rgb.all, ['red', 'black', 'red'])
                    elif geth_peer_count > 2:
                        rgb.setLED(rgb.all, 3*['red'])



            ##############################
            ##### STATE-MACHINE STEP #####
            ##############################

            #########################################################################################################
            #### State::EVERY
            #########################################################################################################
            
            # Perform submodules step
            for module in [erb, rs, rw]:
                module.step()

            # Get Byzantine style and perform according acction
            byzantine_style = self.robot.variables.get_attribute("byzantine_style")

            if byzantine_style == 1:
                estimate = 0
            elif byzantine_style == 2:
                estimate = 1        
            elif byzantine_style == 3:
                # 50% chance white, 50% change black
                p = random.uniform(0, 1)
                if p < 0.5:
                    estimate = 0
                else:
                    estimate = 1
            elif byzantine_style == 4:
                estimate = random.uniform(0, 1)        
            
            # Non-Byzantine robots
            else:
                #if clocks['sensing'].query(): 
                newValues = rs.getNew()

                #print([newValue for newValue in newValues])
        
                for value in newValues:
                    if value != 0:
                        totalWhite += 1
                    else:
                        totalBlack += 1
                estimate = (0.5+totalWhite)/(totalWhite+totalBlack+1)

            if clocks['estimate'].query():
                print("Estimate is", estimate)
                print("totalWhite", totalWhite)
                print("totalBlack", totalBlack)
            

    def reset(self):
        pass

    def destroy(self):
        print('Killed robot '+ me.id)

#########################################################################################################################
#########################################################################################################################
#########################################################################################################################


def getEnodes():
    return [peer['enode'] for peer in w3.geth.admin.peers()]

def getEnodeById(__id, gethEnodes = None):
    if not gethEnodes:
        gethEnodes = getEnodes() 

    for enode in gethEnodes:
        if readEnode(enode, output = 'id') == __id:
            return enode

def getIds(__enodes = None):
    if __enodes:
        return [enode.split('@',2)[1].split(':',2)[0].split('.')[-1] for enode in __enodes]
    else:
        return [enode.split('@',2)[1].split(':',2)[0].split('.')[-1] for enode in getEnodes()]

# Create the instance that ARGoS will use
controller = Controller
