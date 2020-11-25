# Network operations

TODO: update required for this doc

After a bootstrap Fabric network is started, you can use the following scripts to deploy your application and scale.

## Create new channel

When the [smoke-test](./network/smoke-test.sh) is executed, the bootstrap network automatically creates a test channel, e.g., `mychannel` (as configured in the network specs [orderer.env](./config/orderer.env), [org1.env](./config/org1.env) and [org2.env](./config/org2.env)). You can create a new channel `newchannel` by using the following script:

```bash
# create channel config tx
cd ./msp
# start tool container and create artifacts for a channel and anchor updates
./msp-util.sh start -t docker -o orderer
./msp-util.sh channel -t docker -o orderer -p org1 -p org2 -c "newchannel"

# create channel in the network
cd ../network
# start fabric network if not already started
./network.sh start -t docker -o orderer -p org1 -p org2
./network.sh create-channel -t docker -o orderer -p org1 -c "newchannel"
```

This creates a channel named `newchannel`.

## Join existing channel

After a channel is created, a peer node can join the channel using the following command:

```bash
cd ../network
# start fabric network if not already started
./network.sh start -t docker -o orderer -p org1 -p org2
./network.sh join-channel -t docker -o orderer -p org1 -n peer-0 -c "newchannel" -a
./network.sh join-channel -t docker -o orderer -p org1 -n peer-1 -c "newchannel"
./network.sh join-channel -t docker -o orderer -p org2 -n peer-0 -c "newchannel" -a
./network.sh join-channel -t docker -o orderer -p org2 -n peer-1 -c "newchannel"
```

This makes 4 peers of 2 organizations to join the channel `newchannel`. The optional argument `-a` means to update the anchor peer for an organization, which can be used only once for each organization.

## Install and instantiate new chaincode

To install new chaincode, e.g., the Fabric sample [marbles02](https://github.com/hyperledger/fabric-samples/tree/master/chaincode/marbles02/go), you can use the following scripts to package and install it.

```bash
cd ../network
FABRIC_SAMPLES=../../hyperledger/fabric-samples
# package and install chaincode for org1
./network.sh package-chaincode -t docker -p org1 -f ${FABRIC_SAMPLES}/chaincode/marbles02/go -s marbles

# verify that chaincode package is built
tar tvfz ../org1.example.com/cli/marbles_1.0.tar.gz

# install chaincode on all peers
./network.sh install-chaincode -t docker -p org1 -n peer-0 -f marbles_1.0.tar.gz
./network.sh install-chaincode -t docker -p org1 -n peer-1 -f marbles_1.0.tar.gz >&log.txt

# extract package-id from output
# Chaincode code package identifier: marbles_1.0:e46bc8cdeb970c57f77cb4d6f02c8d2525c12fc465cb7e3850ffd465ae247753
PACKAGE_ID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //' | tr -d '\r')
echo "package ID: ${PACKAGE_ID}"

# package and install chaincode for org2
./network.sh package-chaincode -t docker -p org2 -f ${FABRIC_SAMPLES}/chaincode/marbles02/go -s marbles
./network.sh install-chaincode -t docker -p org2 -n peer-0 -f marbles_1.0.tar.gz
./network.sh install-chaincode -t docker -p org2 -n peer-1 -f marbles_1.0.tar.gz

# approve and commit chaincode for both orgs
./network.sh approve-chaincode -t docker -p org1 -c "newchannel" -k ${PACKAGE_ID} -s marbles
./network.sh approve-chaincode -t docker -p org2 -c "newchannel" -k ${PACKAGE_ID} -s marbles
./network.sh commit-chaincode -t docker -p org1 -p org2 -c "newchannel" -s marbles
```

This installs the sample chaincode `marbles02` on the 4 peer nodes as `marbles:1.0`, and commits it on the channel `newchannel`. You can verify the installation by using the following scripts:

```bash
cd ../network
./network.sh invoke-chaincode -t docker -p org1 -p org2 -c "newchannel" -s marbles -m '{"function":"initMarble","Args":["marble1","blue","35","tom"]}'
sleep 5
./network.sh query-chaincode -t docker -p org1 -n peer-0 -c "newchannel" -s marbles -m '{"Args":["readMarble","marble1"]}'
```

## Add new peer nodes of the same bootstrap org

You can scale up the number of peers of a running network only if Kubernetes is used. Use the following script to create crypto keys for the additional peer nodes:

```bash
# create crypto data for the new peers
cd ./ca
# start ca server/client if they are not already started
./ca-server.sh start -p org1
./ca-crypto.sh peer -p org1 -s 2 -e 4
```

This assumes that the bootstrap network is already running 2 peer nodes, i.e., `peer-0` and `peer-1`. To scale it to 4 nodes, we generated additional crypto data for `peer-2` and `peer-3`.

You can then scale up the number of peers as follows:

```bash
# scale to 4 peer nodes
cd ../network
./network.sh scale-peer -p org1 -r 4
```

## Add new orderer nodes of the same bootstrap org

When RAFT consensus is used, you can add more orderer nodes to the network. However, as of Fabric release 1.4, it allows you to add only one new consenter at a time. The following script will update the system channel, and add one more orderer node of the same bootstrap orderer org to the network.

```bash
# 1. generate crypto for new orderer nodes (assuming 3 orderers already running, i.e., orderer-0, 1, and 2)
cd ./ca
./ca-server.sh start -p orderer
# create crypto for orderer-3 and orderer-4
./ca-crypto.sh orderer -p orderer -s 3 -e 5

# 2. create tx to update system channel config with additional orderer-3
cd ../network
./network.sh add-orderer -o orderer -q 3

# 3. scale orderer RAFT cluster to include one more orderer, i.e., orderer-3
./network.sh scale-orderer -o orderer
```

Note that this 3-step process can be repeated to add more orderer nodes, one at a time. If you need to add more than one orderer, the first step can generate keys for multiple orderers; the second step uses the generated orderer certificate to update the system channel; the last step will scale the orderer statefulset by adding one more node, and so the new node `orderer-3` will start and join the RAFT cluster.

We then need to update other application channels, as well, e.g., for `mychannel`,

```bash
cd ./network
./network.sh add-orderer -o orderer -q 3 -c mychannel
```

## Add new peer org to the same Kubernetes cluster

It involves multiple steps to add a new organization to a running network. However, all steps are scripted to simplify the process.

First, bootstrap and test a fabric network in Kubernetes as described in [README.md](./README.md), i.e.,

```bash
# create and join mychannel by existing peers of org1 and org2
cd ../network
./network.sh start -o orderer -p org1 -p org2
./smoke-test.sh
```

Second, create crypto data for peers and users of the new organization, as defined in [org3.env](./config/org3.env), i.e.,

```bash
cd ../ca
./new-org.sh -o orderer -p org3 -d
```

Third, create `org3MSP` config and get approval from other orgs to join the network:

```bash
# create new org config
cd ../msp
./msp-util.sh start -o orderer
./msp-util.sh new-org -o orderer -p org3

# start org3 peer nodes
./network.sh start -o orderer -p org3

# send the resulting config file - org3MSP.json - to org1 for approval
cp ../orderer.example.com/tool/org3MSP.json ../org1.example.com/cli

# use org1 to create and sign the channel update tx for adding org3 to mychannel
./network.sh add-org-tx -p org1 -i org3 -c mychannel

# send signed tx to org2 for approval
cp ../org1.example.com/cli/mychannel-org3MSP.pb ../org2.example.com/cli

# use org2 to sign and update channel config
./network.sh update-channel -p org2 -f mychannel-org3MSP.pb -c mychannel
```

Finally, peers of `org3` can join the channel, install chaincode and execute queries as follows:

```bash
# org3 can now join mychannel and execute transactions
./network.sh join-channel -o orderer -p org3 -n peer-0 -c mychannel
./network.sh join-channel -o orderer -p org3 -n peer-1 -c mychannel
./network.sh package-chaincode -p org3 -f ../../hyperledger/fabric-samples/chaincode/sacc -s sacc
./network.sh install-chaincode -p org3 -n peer-0 -f sacc_1.0.tar.gz
./network.sh install-chaincode -p org3 -n peer-1 -f sacc_1.0.tar.gz >&log.txt
PACKAGE_ID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //' | tr -d '\r')
./network.sh approve-chaincode -p org3 -c mychannel -k ${PACKAGE_ID} -s sacc
./network.sh query-chaincode -p org3 -n peer-0 -c mychannel -s sacc -m '{"Args":["get","a"]}'
```

Since the sample chaincode `sacc:1.0` uses the default majority endorsement policy, you can also update the blockchain state and verify the result using any of the 6 running peers as follows:

```bash
./network.sh invoke-chaincode -p org3 -p org1 -c mychannel -s sacc -m '{"function":"set","Args":["a","200"]}'
./network.sh query-chaincode -p org2 -n peer-0 -c mychannel -s sacc -m '{"Args":["get","a"]}'
```
