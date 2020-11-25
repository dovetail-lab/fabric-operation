# CA crypto utility

This utility uses 2 [fabric-ca](https://hyperledger-fabric-ca.readthedocs.io/en/release-1.4/) servers to generate crypto data for Hyperledger Fabric users and nodes. One server is used to generate CA keys, another is used to generate TLS keys.

## Start CA servers and client containers

Example:

```bash
cd ./ca
./ca-server.sh start -p orderer -t k8s
```

This starts the fabric-ca server and client containers using the config file [orderer.env](../config/orderer.env), which must be configured and put in the [config](../config) folder. The containers will run in `Docker Desktop` Kubernetes on Mac. Non-Mac users can specify a different `-t` value to run it in another environment supported by your platform. The following command prints out the supported options:

```bash
./ca-server.sh -h

Usage:
  ca-server.sh <cmd> [-p <property file>] [-t <env type>] [-d]
    <cmd> - one of 'start', or 'shutdown'
      - 'start' - start ca and tlsca servers and ca client
      - 'shutdown' - shutdown ca and tlsca servers and ca client, and cleanup ca-client data
    -p <property file> - the .env file in config folder that defines network properties, e.g., org1 (default)
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'
    -d - delete all ca/tlsca server data for fresh start next time
  ca-server.sh -h (print this message)
```

- Docker-compose users can use option `-t docker`
- Azure users can refer instructions in the folder [az](../az) to run it from an Azure `bastion` VM instance with option `-t az`.
- AWS users can refer instructions in the folder [aws](../aws) to run it from an Amazon `bastion` EC2 instance with option `-t aws`.

## Bootstrap crypto of all nodes and users

You can bootstrap all crypto data for a pre-defined Fabric network as follows:

```bash
cd ./ca
./bootstrap.sh -o orderer -p org1 -p org2 -d
```

This starts docker containers in Kubernetes of the `Docker Desktop` on Mac, generate all crypto data for orderers, peers and users preconfigured in the org config files, [orderer.env](../config/orderer.env), [org1.env](../config/org1.env), and [org2.env](../config/org2.env).  The generated artifacts are stored separately for each organization, e.g., data of the `orderer` organization is stored in folder `orderer.example.com`.

The `bootstrap` calls the script `ca-crypto.sh`, which supports the following command options:

```bash
./ca-crypto.sh -h

Usage:
  ca-crypto.sh <cmd> [-p <property file>] [-t <env type>] [-s <start seq>] [-e <end seq>] [-u <user name>]
    <cmd> - one of 'bootstrap', 'orderer', 'peer', 'admin', or 'user'
      - 'bootstrap' - generate crypto for all orderers, peers, and users in a network spec
      - 'orderer' - generate crypto for specified orderers
      - 'peer' - generate crypto for specified peers
      - 'admin' - generate crypto for specified admin users
      - 'user' - generate crypto for specified client users
    -p <property file> - the .env file in config folder that defines network properties, e.g., org1 (default)
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'
    -s <start seq> - start sequence number (inclusive) for orderer or peer
    -e <end seq> - end sequence number (exclusive) for orderer or peer
    -u <user name> - space-delimited admin/client user names
  ca-crypto.sh -h (print this message)
```

When this command is used on `AWS` or `Azure`, the generated crypto data will be stored in a cloud file system mounted on the `bastion` host, e.g., a mounted folder `/mnt/share/orderer.example.com` in an `EFS` file system on `AWS` or an `Azure Files` storage on `Azure`.

## Add crypto of new orderer nodes

Example:

```bash
cd ./ca
./ca-crypto.sh orderer -p orderer -t k8s -s 3 -e 5
```

This will create crypto data for 2 new orderer nodes to the `orderer` organization, `orderer-3` and `orderer-4`.

## Add crypto of new peer nodes

Example:

```bash
cd ./ca
./ca-crypto.sh peer -p org1 -t k8s -s 2 -e 4
```

This will create crypto data for 2 new peer nodes to the `org1` organization, `peer-2` and `peer-3`.

## Add crypto of new client users

Example:

```bash
cd ./ca
./ca-crypto.sh user -p org1 -t k8s -u "Carol David"
```

This will create crypto data for 2 new client users to the `org1` organization, `Carol@org1.example.com` and `David@org1.example.com`.

Note that the current implementation specifies only a couple of fixed attributes in user certificates. You may customize the attributes if your application requires. We may enhance the scripts in the future to make it easier to customize user attributes.

## Add crypto of new admin users

Example:

```bash
cd ./ca
./ca-crypto.sh admin -p org1 -t k8s -u "Super Hero"
```

This will create crypto data for 2 new admin users to the `org1` organization, `Super@org1.example.com` and `Hero@org1.example.com`.

## Shutdown and cleanup

Example:

```bash
cd ./ca
./ca-server.sh shutdown -p orderer -t k8s
```

This shuts down the ca-server and ca-client containers of the `orderer` organization, but keeps the state of 2 ca servers, so you can add more users/nodes using the same root CA. If you want to delete all state and start from scratch, however, you can add the option `-d` when shuting down the servers. You should keep a copy of the ca-server folders, e.g., `orderer.example.com/canet/ca-server` and `orderer.example.com/canet/tlsca-server`, if you want to generate additional crypto data for a running Fabric network.
