# MSP utility

This utility uses `fabric-tools` container to generate artifacts for a Hyperledger Fabric network, including genesis block, transactions for channel creation and updates, etc.

## Start Fabric-tools

Example:

```bash
cd ./msp
./msp-util.sh start -t docker -o orderer
```

It starts a fabric-tools container using properties in org config files [orderer.env](../config/orderer.env), which must be configured and put in the [config](../config) folder. The container will run in `Docker Desktop` Kubernetes on Mac. Non-Mac users may specify a flag `-t docker` to run it as docker container. The following command prints out the supported options:

```bash
./msp-util.sh -h

Usage:
  msp-util.sh <cmd> [-o <orderer-org>] [-p <peer-org>] [-t <env type>] [-c <channel name>]
    <cmd> - one of the following commands
      - 'start' - start tools container to run msp-util
      - 'shutdown' - shutdown tools container for the msp-util
      - 'bootstrap' - generate bootstrap genesis block and test channel tx defined in network spec
      - 'genesis' - generate genesis block of etcd raft consensus
      - 'channel' - generate channel creation tx for specified channel name, with argument '-c <channel name>'
      - 'mspconfig' - print MSP config json for adding to a network, output in '/tool'
      - 'orderer-config' - print orderer RAFT consenter config for adding to a network, with arguments -s <start-seq> [-e <end-seq>]
      - 'build-cds' - build chaincode cds package from flogo model, with arguments -m <model-json> [-v <version>]
      - 'build-app' - build linux executable from flogo model, with arguments -m <model-json> -g <go-os>
    -o <orderer-org> - the .env file in config folder that defines the orderer org, e.g., orderer (default)
    -p <peer-org> - the .env file in config folder that defines a peer org, e.g., org1
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'
    -c <channel name> - name of a channel, used with the 'channel' command
    -s <start seq> - start sequence number (inclusive) for orderer config
    -e <end seq> - end sequence number (exclusive) for orderer config
    -m <model json> - Flogo model json file
    -g <go-os> - target os, e.g., linux (default) or darwin
    -v <cc version> - version of chaincode
  msp-util.sh -h (print this message)
  Example:
    ./msp-util.sh start -t docker -o orderer
    ./msp-util.sh bootstrap -t docker -o orderer -p org1 -p org2
    ./msp-util.sh shutdown -t docker -o orderer
```

## Bootstrap artifacts of Fabric network

Example:

```bash
cd ./msp
./msp-util.sh bootstrap -o orderer -p org1 -p org2
```

This uses the `tool` container to generate the genesis block and transaction block for creating a test channel `mychannel` as specified in the config file [orderer.env](../config/orderer.env). The number of peer node and other attributes of peer organizations can be configured in the files [org1.env](../config/org1.env) and [org2.env](../config/org2.env). The generated artifacts are stored in the folder `orderer.example.com/tool` as `orderer-genesis.block`, `mychannel.tx`, and `mychannel-anchors-org1MSP.tx`.

When this command is executed on `AWS`, `Azure` or `GCP`, the generated files will be stored in a cloud file system mounted on the `bastion` host, e.g., a mounted folder `/mnt/share/orderer.example.com/tool` in an `EFS` file system on `AWS` or an `Azure Files` storage on `Azure` or a `Filestore` volume on `GCP`.

## Generate orderer genesis block only

Example:

```bash
cd ./msp
./msp-util.sh genesis -o orderer -p org1 -p org2
```

This will create a genesis block `orderer-genesis.block`.

## Generate channel transactions for a specified channel name

Example:

```bash
cd ./msp
./msp-util.sh channel -o orderer -p org1 -p org2 -c testchan
```

This will create the channel creation and anchor transactions for a channel named `testchan`. The created files are named `testchan.tx`, `testchan-anchors-org1MSP.tx` and `testchan-anchors-org2MSP.tx`.

## Shutdown and cleanup

Example:

```bash
cd ./msp
./msp-util.sh shutdown -o orderer
```

This shuts down the `tool` container for the `orderer` organization.

## TODO

More operations will be supported by this utility, including

- Update transaction for adding new orderers;
- Update transaction for adding new peer organizations;
- Update transaction for adding new orderer organizations
