# fabric-operation

This package contains scripts that let you define, create, and test a Hyperledger Fabric network in Kubernetes locally or in a cloud. Supported cloud services include AWS, Azure, and Google Cloud. The fabric network can be specified by simple property files of the orderer and peer organizations, e.g., a sample network can be configured by an order organization [orderer.env](./config/orderer.env) and two peer organizations [org1.env](./config/org1.env) and [org2.env](.config/org2.env).

Once the organizations are configured, you can bootstrap the fabric network by using scripts in this repo, and run the network in either `docker-compose` or `kubernetes`. All the execution steps are done in docker containers, and thus you can get a Fabric network running without pre-downloading any artifact of Hyperledger Fabric.

This repo uses only bash scripts, and thus it does not depend on any other scripting tool or framework. It supports Hyperledger Fabric applications developed in [dovetail](https://github.com/dovetail-lab/dovetail), which is a zero-code visual programming tool for modeling Hyperledger Fabric chaincode and client apps. A complete end-to-end sample to deploy a dovetail app in Azure AKS cluster can be found in [jabil_aim](https://github.com/dovetail-lab/fabric-samples/tree/master/jabil-aim).

## Prerequisites

- Your workstation must support `bash` shell scripts.
- If you want to create and test a Fabric network on local host, you need to install docker-compose and/or kubernetes locally, i.e.,
  - Install Docker and Docker Compose as described [here](https://docs.docker.com/compose/install/).
  - Mac user can enable kubernetes as described [here](https://docs.docker.com/docker-for-mac/#kubernetes).
  - The scripts are not tested with [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/), although they may work without much change.
- If you want to create and test a Fabric network in a cloud, you would not need to download anything except a `CLI` required to access the corresponding cloud service. We currently support Amazon EKS, Azure AKS, and Google GKE. Other cloud services may be supported in the future.

  - For AWS, refer the scripts and instructions in the [aws folder](./aws).
  - For Azure, refer the scripts and instructions in the [az folder](./az).
  - For Google cloud, refer the scripts and instructions in the [gcp folder](./gcp)

## Download Dovetail projects and Hyperledger Fabric samples

To get-started for local development, you can set setup the environment as described [here](https://github.com/dovetail-lab/fabric-cli/blob/master/README.md).

## Start CA server and generate crypto data

Following steps use `docker-desktop` Kubernetes on Mac to start `fabric-ca` PODs and generate crypto data required by the sample network operated by 3 organizations, [orderer](./config/orderer.env), [org1](./config/org1.env), and [org2](./config/org1.env).

```bash
cd ../ca
./bootstrap.sh -o orderer -p org1 -p org2 -d
```

The will create crypto data required to support 3 orderers and 2 peers each for `org1` and `org2` as defined in the org's configuration files. You can edit the configuration files, e.g., [orderer.env](./config/orderer.env) if you want to use a different organization name, or run more orderer or peer nodes. The generated crypto data will be stored in the local folder `/path/to/dovetail-lab/fabric-operation/<org-name>`, or in a cloud file system, such as Amazon EFS, Azure Files, or GCP Filestore when the above script is executed in the bastion host of a cloud provider.

## Generate MSP definition and genesis block

The following script generates a genesis block for the sample network in Kubernetes using 3 orderers with `etcd raft` consensus, as well as channel artifacts for creating a test channel `mychannel`.

```bash
cd ../msp
./bootstrap.sh -o orderer -p org1 -p org2 -d
```

## Start the Fabric network

The following script will start and test the sample fabric network by using the `docker-desktop` Kubernetes on a Mac:

```bash
cd ./network
./network.sh start -o orderer -p org1 -p org2
```

Verify that all orderer and peer nodes are running by using `kubectl`, e.g.,

```bash
kubectl get pod,svc --all-namespaces
```

After the network startup, use `kubectl logs orderer-2 -n orderer` to check RAFT leader election result. When RAFT leader is elected, the log should show

```
INFO 101 Raft leader changed: 0 -> 2 channel=netop1-channel node=2
```

Note that the scripts use organization names, e.g, `org1`, as the Kubernetes namespace of corresponding processes, and so it can support multiple member organizations. If you want to reset the default namespace, you can use the following command:

To revoke to the default namespace for `docker-desktop`, you can use the following command:

```bash
kubectl config use-context docker-desktop
```

## Smoke test by deploying sample chaincode `sacc`

The smoke test script [smoke-test.sh](./network/smoke-test.sh) creates the test channel `mychannel`, make 4 peer nodes join the channel, then package, deploy, and invoke the sample chaincode [sacc](https://github.com/hyperledger/fabric-samples/tree/master/chaincode/sacc).

```bash
cd ./network
./smoke-test.sh
```

You should see that the chaincode invocation created a ledger record that sets `a = 100`, and the query afterwards returned the value `100`.

If you used `docker-compose` for this excersize (as described below), you can look at the blockchain state via the `CouchDB` futon UI at `http://localhost:7056/_utils`, which is exposed for `docker-compose` only because it is not recommended to expose `CouchDB` in production configuration using Kubernetes.

## Start gateway service and use REST APIs to test chaincode

TODO: update required here ...

Refer [gateway](./service/README.md) for more details on how to build and start a REST API service for applications to interact with one or more Fabric networks. The following commands will start a gateway service that exposes a Swagger-UI at `http://localhost:30081/swagger`.

```bash
cd ../service
./gateway.sh start
```

## Operations for managing the Fabric network

TODO: update required here ...

The above bootstrap network is for a single operating company to start a Fabric network with its own orderer and peer nodes of pre-configured size. A network in production will need to scale up and let more organizations join and co-operate. Organizations may create their own Kubernetes networks using the same or different cloud service providers. We provide scripts to support such network activities.

The currently supported operations include

- Create and join new channel;
- Install and instantiate new chaincode;
- Add new peer nodes of the same bootstrap org;
- Add new orderer nodes of the same bootstrap org;
- Add new peer org to the same Kubernetes cluster;

Refer [operations](./operations.md) for description of these activities. More operations (as described in `TODO` bellow) will be supported in the future.

## Non-Mac users

If you are not using a Mac, you can run these scripts using `docker-compose`, `Amazon EKS`, `Azure AKS`, or `Google GKE`. Simply add a corresponding `env_type` in all the commands, e.g.,

- `./bootstrap.sh -t docker -o orderer -p org1 -p org2 -d` to use `docker-composer`, or
- execute the command on bastion host in cloud as described for Amazon WebService [aws](./aws), Microsoft Azue [az](./az), or Google Cloud [gcp](./gcp), or
- try to verify if the scripts would work on [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/).

When `docker-compose` is used locally, the commands are as follows:

```bash
cd ./ca
./bootstrap.sh -t docker -o orderer -p org1 -p org2 -d

cd ../msp
./bootstrap.sh -t docker -o orderer -p org1 -p org2 -d

cd ../network
./network.sh start -t docker -o orderer -p org1 -p org2

docker ps -a
./smoke-test.sh docker
```

## TODO

Stay tuned for more updates on the following items:

- Add new orderer org to the same bootstrap Kubernetes cluster for etcd raft consensus;
- Add new orderer org in a different Kubernetes cluster;
- Add new peer org in a different Kubernetes cluster;
- Test multiple org multiple Kubernetes clusters across multiple cloud providers.
