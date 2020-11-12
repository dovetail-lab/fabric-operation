#!/bin/bash
# Run these commands to test channel creation and verify chaincode installation

# create mychannel, and join 4 peer nodes from 2 orgs
./network.sh create-channel -t docker -o orderer -p org1 -c mychannel
./network.sh join-channel -t docker -o orderer -p org1 -n peer-0 -c mychannel -a
./network.sh join-channel -t docker -o orderer -p org1 -n peer-1 -c mychannel
./network.sh join-channel -t docker -o orderer -p org2 -n peer-0 -c mychannel -a
./network.sh join-channel -t docker -o orderer -p org2 -n peer-1 -c mychannel

# package and install chaincode for org1
./network.sh package-chaincode -t docker -p org1 -f ../../hyperledger/fabric-samples/chaincode/sacc -s sacc
tar tvfz ../org1.example.com/cli/sacc_1.0.tar.gz
./network.sh install-chaincode -t docker -p org1 -n peer-0 -f sacc_1.0.tar.gz
./network.sh install-chaincode -t docker -p org1 -n peer-1 -f sacc_1.0.tar.gz >&log.txt

# extract PACKAGE_ID from output 
# Chaincode code package identifier: sacc_1.0:764f4ed27ad886f7c54f2cbd8f5bbc7e87769945d247021744da8fe39aca8c89
PACKAGE_ID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //')

# package and install chaincode for org2
./network.sh package-chaincode -t docker -p org2 -f ../../hyperledger/fabric-samples/chaincode/sacc -s sacc
./network.sh install-chaincode -t docker -p org2 -n peer-0 -f sacc_1.0.tar.gz
./network.sh install-chaincode -t docker -p org2 -n peer-1 -f sacc_1.0.tar.gz

# approve and commit chaincode for both orgs
./network.sh approve-chaincode -t docker -p org1 -c mychannel -k ${PACKAGE_ID} -s sacc
./network.sh approve-chaincode -t docker -p org2 -c mychannel -k ${PACKAGE_ID} -s sacc
./network.sh commit-chaincode -t docker -p org1 -p org2 -c mychannel -s sacc

# test chaincode runtime
./network.sh invoke-chaincode -t docker -p org1 -p org2 -c mychannel -s sacc -m '{"function":"set","Args":["a","100"]}'
./network.sh query-chaincode -t docker -p org1 -n peer-0 -c mychannel -s sacc -m '{"Args":["get","a"]}'
