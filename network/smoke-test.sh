#!/bin/bash
# Run these commands to test channel creation and verify chaincode installation
#
# Usage:
#   ./smoke-test.sh [<env>]
# set env to "docker" for docker-compose environment; if not specified, use default Kubernetes env

ENV_TYPE=${1:-""}

function testChannel {
  # create mychannel, and join 4 peer nodes from 2 orgs
  ./network.sh create-channel -t "${ENV_TYPE}" -o orderer -p org1 -c mychannel
  ./network.sh join-channel -t "${ENV_TYPE}" -o orderer -p org1 -n peer-0 -c mychannel -a
  ./network.sh join-channel -t "${ENV_TYPE}" -o orderer -p org1 -n peer-1 -c mychannel
  ./network.sh join-channel -t "${ENV_TYPE}" -o orderer -p org2 -n peer-0 -c mychannel -a
  ./network.sh join-channel -t "${ENV_TYPE}" -o orderer -p org2 -n peer-1 -c mychannel
}

function testChaincode {
  # package and install chaincode for org1
  ./network.sh package-chaincode -t "${ENV_TYPE}" -p org1 -f ../../hyperledger/fabric-samples/chaincode/sacc -s sacc
  #tar tvfz ../org1.example.com/cli/sacc_1.0.tar.gz
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org1 -n peer-0 -f sacc_1.0.tar.gz
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org1 -n peer-1 -f sacc_1.0.tar.gz >&log.txt

  # extract package-id from output 
  # Chaincode code package identifier: sacc_1.0:764f4ed27ad886f7c54f2cbd8f5bbc7e87769945d247021744da8fe39aca8c89
  local packageID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //' | tr -d '\r')

  # package and install chaincode for org2
  ./network.sh package-chaincode -t "${ENV_TYPE}" -p org2 -f ../../hyperledger/fabric-samples/chaincode/sacc -s sacc
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org2 -n peer-0 -f sacc_1.0.tar.gz
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org2 -n peer-1 -f sacc_1.0.tar.gz

  # approve and commit chaincode for both orgs
  echo "approve chaincode package ${packageID}"
  ./network.sh approve-chaincode -t "${ENV_TYPE}" -p org1 -c mychannel -k ${packageID} -s sacc
  ./network.sh approve-chaincode -t "${ENV_TYPE}" -p org2 -c mychannel -k ${packageID} -s sacc
  ./network.sh commit-chaincode -t "${ENV_TYPE}" -p org1 -p org2 -c mychannel -s sacc

  # test chaincode runtime
  echo "test sacc chaincode"
  ./network.sh invoke-chaincode -t "${ENV_TYPE}" -p org1 -p org2 -c mychannel -s sacc -m '{"function":"set","Args":["a","100"]}'
  sleep 5
  ./network.sh query-chaincode -t "${ENV_TYPE}" -p org1 -n peer-0 -c mychannel -s sacc -m '{"Args":["get","a"]}'
}

# test dovetail build
function testDovetail {
  echo "build package marble_cc_1.0.tar.gz"
  cd ../msp
  ./msp-util.sh build-cds -t "${ENV_TYPE}" -o orderer -p org1 -p org2 -m ../dovetail/samples/marble/marble.json

  echo "install package marble_cc_1.0.tar.gz"
  cd ../network
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org1 -n peer-0 -f marble_cc_1.0.tar.gz
  ./network.sh install-chaincode -t "${ENV_TYPE}" -p org2 -n peer-0 -f marble_cc_1.0.tar.gz >&log.txt
  local packageID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //' | tr -d '\r')

  echo "approve installed package: ${packageID}"
  ./network.sh approve-chaincode -t "${ENV_TYPE}" -p org1 -c mychannel -k ${packageID} -s marble_cc
  ./network.sh approve-chaincode -t "${ENV_TYPE}" -p org2 -c mychannel -k ${packageID} -s marble_cc
  ./network.sh commit-chaincode -t "${ENV_TYPE}" -p org1 -p org2 -c mychannel -s marble_cc

  echo "test marble_cc chaincode"
  ./network.sh invoke-chaincode -t "${ENV_TYPE}" -p org1 -p org2 -c mychannel -s marble_cc -m '{"function":"initMarble","Args":["marble1","blue","35","tom"]}'
  sleep 5
  ./network.sh query-chaincode -t "${ENV_TYPE}" -p org1 -n peer-0 -c mychannel -s marble_cc -m '{"Args":["readMarble","marble1"]}'
}

testChannel
testChaincode

# cd ../msp
# ./msp-util.sh start -t "${ENV_TYPE}" -o orderer -p org1 -p org2
# testDovetail