# Setup Microsoft Azure AKS cluster

The scripts in this section will launch an AKS cluster, setup Azure Files for persistence, and configure a `bastion` host that you can login and start a Hyperledger Fabric network. The configuration file [env.sh](./env.sh) specifies the number and type of Azure VM instances and type of storage used by the AKS cluster, e.g., 3 VM instances are used by the default configuration.

## Configure Azure account login

Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) as described by the link.

Once your Azure account is setup, you can login by typing the command:

```bash
az login
```

Enter your account info in a pop-up browser window. Note that you may lookup your account details by using the [Azure Portal](https://portal.azure.com), although it is not absolutely necessary since we use only `Azure CLI` scripts.

## Start AKS cluster

Create and start the AKS cluster with all defaults:

```bash
cd /path/to/dovetail-lab/fabric-operation/az
./az-util.sh create
```

This script accepts 2 parameters for you to specify a different Azure environment, e.g.,

```bash
./az-util.sh create -n fab -r westus2
```

would create an AKS cluster with name prefix of `fab`, at the Azure location of `westus2`.

Wait 10 minutes for the cluster nodes to startup. When the cluster is up, it will print a line, such as:

```bash
ssh fab@51.143.17.95
```

You can use this command to login to the `bastion` VM instance and create a Hyperledger Fabric network in the AKS cluster. Note that the `ssh` keypair for accessing the `bastion` host is in your `$HOME/.ssh` folder, and named as `id_rsa.pub` and `id_rsa`. The script will generate a new keypair if these files do not exist already.

Note also that the scripts have set the security group such that the `bastion` host can be accessed by only your workstation's current IP address. If your IP address changes, you'll need to login to Azure to update the security rule, or simply re-run the script:

```bash
cd ./az
az login
./create-bastion.sh fab westus2
```

## Prepare AKS cluster and Azure File storage for Hyperledger Fabric

Log on to the `bastion` host, e.g., (your real host IP will be different):

```bash
ssh fab@51.143.17.95
```

After login, you'll notice that everything is automatically setup for you. You may verify the following configurations.

- `df` command should show that an `Azure File` storage is already mounted at `/mnt/share`;
- `kubectl get pod,svc --all-namespaces` should show you the Kubernetes system services and PODs;
- `ls ~` should show you that the latest code of this project is already downloaded at `$HOME/fabric-operation`.

## Start and test Hyperledger Fabric network

Following steps will start and smoke test the default Hyperledger Fabric network with 2 peers by each of 2 orgs, and 3 orderers using `etcd raft` consensus. You can learn more details about these commands [here](../README.md).

### Start CA server and create crypto data for the Fabric network

```bash
cd ../ca
./bootstrap.sh -o orderer -p org1 -p org2 -d
```

This command starts 2 CA servers and a CA client for each organization, and generates crypto data according to the network specification, [orderer.env](../config/orderer.env), [org1.env](../config/org1.env) and [org2.env](../config/org2.env). You can verify the result using the following commands:

```bash
ls /mnt/share/orderer.example.com/
```

It should list folders containing crypto data, i.e., `canet`, `cli`, `crypto`, `gateway`, `namespace`, `orderers`, and `tool`.

### Generate genesis block and channel creation tx

```bash
cd ../msp
./bootstrap.sh -o orderer -p org1 -p org2
```

This command starts a Kubernetes POD to generate the genesis block and transaction for creating a test channel `mychannel` based on the network specification. You can verify the result using the following commands:

- `kubectl get pods -n orderer` should list a running POD `tool`;
- `ls /mnt/share/orderer.example.com/tool` should show the generated artifacts: `orderer-genesis.block`, `mychannel.tx`, `mychannel-anchors-org1MSP.tx`, and `configtx.yaml`.

### Start Fabric network

```bash
cd ../network
./network.sh start -o orderer -p org1 -p org2
```

This command starts the orderers and peers using the crypto and genesis block created in the previous steps. You can verify the network status using the following commands:

- `kubectl get pod,svc --all-namespaces` should list 3 running orderers 4 running peers and 2 cli containers;
- `kubectl logs orderer-2 -n orderer` should show that a raft leader is elected by all 3 orderer nodes;
- `kubectl logs peer-1 -c peer -n org1` should show the logs of `peer-1`, that shows its successfully completed gossip communications with `peer-0`.
- `ls /mnt/share/orderer.example.com/orderers/orderer-0/data` shows persistent storage of the `orderer-0`, similar to other orderer nodes;
- `ls /mnt/share/org1.example.com/peers/peer-0/data` shows persistent storage of the `peer-0`, similar to other peer nodes.

### Smoke test of the Fabric network

```bash
cd ../network
./smoke-test.sh
```

This command creates the test channel `mychannel`, installs and instantiates the sample chaincode `sacc`, and then executes a transaction and a query to verify the working network. You can verify the result as follows:

- The last result printed out by the test should be `100`;
- Orderer data folder, e.g., `/mnt/share/orderer.example.com/orderers/orderer-0/data` would show a block file added under the chain of a new channel `chains/mychannel`;
- Peer data folder, e.g., `/mnt/share/org1.example.com/peers/peer-0/data` would show a new chaincode `sacc_1.0` added in the `lifecycle/chaincodes` folder, and a transaction block file created under `ledgersData/chains/chains/mychannel`.

### Start client gateway service and use REST APIs to test chaincode

Refer [gateway](../service/README.md) for more details on how to build and start a REST API service for applications to interact with one or more Fabric networks. The following command starts a gateway service from the bastion host by using the pre-built executable `gateway-linux`.

```bash
# config and start gateway service for Azure
cd ../service
./gateway.sh config -o orderer -p org1 -p org2
./gateway.sh start -p org1
```

The last command started 2 PODs to run the gateway service, and created a load-balancer service with a publicly accessible port. The load-balancer port is automatically open to public, which is convenient for dev and test, although Azure recommends to add `Ingress controllers` for production use.

The URL of the load-balancer is printed by the script as, e.g.,

```
http://52.148.162.197:7081/swagger
```

Copy and paste the URL (your actual URL will be different) into a Chrome web-browser, and use it to test the sample chaincode as described in [gateway](../service/README.md).

Verify the gateway connection by posting following request to `/v1/connection`:

```json
{
  "channelId": "mychannel",
  "userName": "Admin",
  "orgName": "org1"
}
```

It will return a `connectionId`: `10375918345828239422`.

### Build and start Dovetail chaincode and service

Refer [dovetail](../dovetail/README.md) for more details about [Project Dovetail](https://github.com/dovetail-lab/dovetail), which is a visual programming tool for modeling Hyperledger Fabric chaincode and client apps.

A Dovetail chaincode model, e.g., [marble.json](../dovetail/samples/marble/marble.json) is a JSON file that implements a sample chaincode by using the [TIBCO Flogo](https://docs.tibco.com/products/tibco-flogo-enterprise-2-10-0) visual modeler. Use the following script to build and instantiate the chaincode.

```bash
# create chaincode package marble_cc_1.0.tar.gz
cd ../msp
./msp-util.sh start -p org1
./msp-util.sh build-cds -p org1 -p org2 -m ../dovetail/samples/marble/marble.json

# install package marble_cc_1.0.tar.gz
cd ../network
./network.sh install-chaincode -p org1 -n peer-0 -f marble_cc_1.0.tar.gz
./network.sh install-chaincode -p org2 -n peer-0 -f marble_cc_1.0.tar.gz >&log.txt
PACKAGE_ID=$(cat log.txt | grep "Chaincode code package identifier:" | sed 's/.*Chaincode code package identifier: //' | tr -d '\r')

# approve installed package: ${packageID}
./network.sh approve-chaincode -p org1 -c mychannel -k ${PACKAGE_ID} -s marble_cc
./network.sh approve-chaincode -p org2 -c mychannel -k ${PACKAGE_ID} -s marble_cc
./network.sh commit-chaincode -p org1 -p org2 -c mychannel -s marble_cc
```

You can send test transactions by using the Swagger UI of the gateway service, e.g., insert a new marble by posting the following transaction to `/v1/transaction`:

```json
{
  "connectionId": "10375918345828239422",
  "type": "INVOKE",
  "chaincodeId": "marble_cc",
  "transaction": "initMarble",
  "parameter": ["marble1", "blue", "35", "tom"]
}
```

By using the same `Flogo` modeling UI, we can also implement a client app, e.g., [marble_client.json](../dovetail/samples/marble_client/marble_client.json), that updates or queries the Fabric distributed ledger by using the `marble` chaincode. Use the following script to build and run a client app as a Kubernetes service.

```bash
# generate network config if skipped the previous gateway test
cd ../service
./gateway.sh config -o orderer -p org1 -p org2

# build and start client using the generated network config
cd ../dovetail
./dovetail.sh config-app -p org1 -m samples/marble_client/marble-client.json
./dovetail.sh start-app -p org1 -m marble-client.json
```

The above command will start 2 instances of the `marble-client` and expose a `load-balancer` end-point for other applications to invoke the service. Once the script completes successfully, it will print out the service end-point as, e.g.,

```
access marble-client servcice at http://40.91.88.121:7091
```

You can use this end-point to update or query the blockchain ledger. [marble.postman_collection.json](https://github.com/dovetail-lab/fabric-samples/blob/master/marble/marble.postman_collection.json) contains a set of REST messages that you can import to [Postman](https://www.getpostman.com/downloads/) and invoke the `marble-client` REST APIs.

Stop the client app after tests complete:

```bash
./dovetail.sh stop-app -p org1 -m marble-client.json
```

### Stop Fabric network and cleanup persistent data

```bash
cd ../network
./network.sh shutdown -o orderer -p org1 -p org2 -d
```

This command shuts down orderers and peers, and the last argument `-d` means to delete all persistent data as well. If you do not use the argument `-d`, it would keep the test ledger file in the `Azure Files` storage, and so it can be loaded when the network restarts. You can verify the result using the following command.

- `kubectl get svc,pod --all-namespaces` should not list any running orderers or peers;
- The orderers and peers' persistent data folder, e.g., `/mnt/share/org1.example.com/peers/peer-0/data` would be deleted if the argument `-d` is used.

## Clean up all Azure processes and storage

You can exit from the `bastion` host, and clean up every thing created in Azure when they are no longer used, i.e.,

```bash
cd ./az
./az-util.sh cleanup -n fab -r westus2
```

This will clean up the AKS cluster and the Azure Files storage created in the previous steps. Make sure that you supply the same parameters as that of the previous `az-util.sh create` command if they are different from the default values.

## TIPs

### Use kubectl from localhost

If your local workstation has `kubctl` installed, and you want to execute `kubectl` commands directly from the localhost, instead of going through the `bastion` host, you can set the env,

```bash
export KUBECONFIG=/path/to/dovetail-lab/fabric-operation/az/config/config-fab.yaml
```

where the `/path/to` is the location of this project on your localhost, and `config-fab.yaml` is named after the `ENV_NAME` specified in [`env.sh`](./env.sh). The file is created for you when you execute `az-util.sh create`, and it is valid only while the AKS cluster is running.

You can then use `kubectl` commands against the Azure AKS cluster from your localhost directly, e.g.,

```bash
kubectl get pod,svc --all-namespaces
```

### Set default Kubernetes namespace

The containers created by the scripts will use the name of a specified operating company, e.g., `org1`, as the Kubernetes namespace. To save you from repeatedly typing the namespace in `kubectl` commands, you can set `org1` as the default namespace by using the following commands:

```bash
kubectl config view
kubectl config set-context org1 --namespace=netop1 --cluster=fabAKSCluster --user=clusterUser_fabRG_fabAKSCluster
kubectl config use-context org1
```

Note to replace the values of `cluster` and `user` in the second command by the corresponding output from the first command. This configuration is automatically done on the bastion host when the [`k8s-namespace.sh create`](../namespace/k8s-namespace.sh) script is called.
