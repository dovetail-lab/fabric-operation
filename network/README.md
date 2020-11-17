# Network utility

This utility is a CLI script for Hyperledger Fabric network operations. It currently supports the following commands:

- Start a Hyperledger Fabric network;
- Shutdown a Hyperledger Fabric network;
- Run smoke test to verify the network health;
- Scale up number of peer nodes while a network is running;
- Scale up orderer nodes while a network is running;
- Create new channels;
- Make a peer node join a channel;
- Package and sign chaincode in cds format;
- Install new chaincodes on a peer node;
- Instantiate new chaincode on a specified channel;
- Upgrade a chaincode on a specified channel;
- Execute queries on a specified chaincode;
- Invoke transactions on a specifiedd chaincode;
- Create channel update for adding a new peer organization;
- Create channel update for adding a new orderer to RAFT consensus;
- Sign a transaction for channel update;
- Update channel config.

More operations will be added in the future to support operations of fabric network that spans multiple organizations and multiple cloud providers.

Following is the current usage info of this utility:

```bash
./network.sh -h

Usage:
  network.sh <cmd> [-o <orderer-org>] [-p <peer-org>] [-t <env type>] [-d]
    <cmd> - one of the following commands:
      - 'start' - start orderers and peers of the fabric network, arguments: [-o <orderer-org>] [-p <peer-org>] [-t <env-type>]
      - 'shutdown' - shutdown orderers and peers of the fabric network, arguments: [-o <orderer-org>] [-p <peer-org>] [-t <env-type>] [-d]
      - 'scale-peer' - scale up peer nodes with argument '-r <replicas>'
      - 'scale-orderer' - scale up orderer nodes (RAFT consenter only one at a time)
      - 'create-channel' - create a channel using a peer-org's cli, with argument: -c <channel>
        e.g., network.sh create-channel -o orderer -p org1 -c mychannel
      - 'join-channel' - join a peer of a peer-org to a channel with arguments: -n <peer> -c <channel> [-a]
        e.g., network.sh join-channel -o orderer -p org1 -n peer-0 -c mychannel -a
      - 'package-chaincode' - package chaincode using a peer-org's cli with arguments: -f <folder> -s <name> [-v <version>] [-g <lang>]
        e.g., network.sh package-chaincode -p org1 -f chaincode_example02/go -s mycc -v 1.0 -g golang
      - 'install-chaincode' - install chaincode on a peer with arguments: -n <peer> -f <cc-package-file>
        e.g., network.sh install-chaincode -p org1 -n peer-0 -f mycc_1.0.tar.gz
      - 'approve-chaincode' - approve a chaincode package on a channel using a peer-org's cli with arguments: -c <channel> -k <package-id> -s <name> [ -v <version> -q <sequence> -f <collection config> -e <policy> ]
        e.g., network.sh approve-chaincode -p org1 -c mychannel -k mycc_1.0:12345 -s mycc -f collections_config.json -e "OR ('org1MSP.peer','org2MSP.peer')"
      - 'commit-chaincode' - commit chaincode package on a channel using a peer-org's cli with arguments: -c <channel> -s <name> [-v <version> -q <sequence> -f <collection config> -e <policy> ]
        e.g., network.sh commit-chaincode -p org1 -p org2 -c mychannel -s mycc -v 1.0 -f collections_config.json -e "OR ('org1MSP.peer','org2MSP.peer')"
      - 'query-chaincode' - query chaincode from a peer, with arguments: -n <peer> -c <channel> -s <name> -m <args>
        e.g., network.sh query-chaincode -p org1 -n peer-0 -c mychannel -s mycc -m '{"Args":["query","a"]}'
      - 'invoke-chaincode' - invoke chaincode from a peer, with arguments: -c <channel> -s <name> -m <args>
        e.g., network.sh invoke-chaincode -p org1 -p org2 -c mychannel -s mycc -m '{"Args":["invoke","a","b","10"]}'
      - 'add-org-tx' - generate update tx for add new msp to a channel, with arguments: -o <msp> -c <channel>
        e.g., network.sh add-org-tx -o peerorg1MSP -c mychannel
      - 'add-orderer-tx' - generate update tx for add new orderers to a channel (default system-channel) for RAFT consensus, with argument: -f <consenter-file> [-c <channel>]
        e.g., network.sh add-orderer-tx -f ordererConfig-3.json
      - 'sign-transaction' - sign a config update transaction file in the CLI working directory, with argument = -f <tx-file>
        e.g., network.sh sign-transaction -f "mychannel-peerorg1MSP.pb"
      - 'update-channel' - send transaction to update a channel, with arguments ('-a' means orderer user): -f <tx-file> -c <channel> [-a]
        e.g., network.sh update-channel -f "mychannel-peerorg1MSP.pb" -c mychannel
    -o <orderer-org> - the .env file in config folder that defines orderer org, e.g., orderer (default)
    -p <peer-orgs> - the .env file in config folder that defines peer org, e.g., org1
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'
    -d - delete ledger data when shutdown network
    -r <replicas> - new peer node replica count for scale-peer
    -n <peer> - peer ID for channel/chaincode commands
    -c <channel> - channel ID for channel/chaincode commands
    -a - update anchor for join-channel, or copy new chaincode for install-chaincode
    -f <cc folder> - path to chaincode source folder, or a config file for some commands
    -s <cc name> - chaincode name
    -v <cc version> - chaincode version, default 1.0
    -g <cc language> - chaincode language, default 'golang'
    -k <cc package id> - chaincode package id
    -q <cc approve seq> - sequence for chaincode approval, default 1
    -e <policy> - endorsement policy for instantiate/upgrade chaincode, e.g., "OR ('Org1MSP.peer')"
    -m <args> - args for chaincode commands
    -i <org msp> - org msp to be added to a channel
  network.sh -h (print this message)
  Example:
    ./network.sh start -t docker -o orderer -p org1 -p org2
    ./network.sh shutdown -t docker -o orderer -p org1 -p org2 -d
```
