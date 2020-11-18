# Build and deploy Dovetail flows

When [Dovetail](https://github.com/dovetail-lab/dovetail) is used to develop chaincode and client apps for Hyperledger Fabric, the Flogo flows can be built and deployed locally or in cloud using scripts in this folder.

## Use docker-compose on local PC

On a Mac or Linux PC with docker installed, you can use the following scripts to start a Fabric network, and deploy a Dovetail app that contains a chaincode and a client service, and perform an end-to-end test by using a REST client.

### Start CA server and create crypto data

```bash
cd /path/to/fabric-operation/ca
./bootstrap.sh -t docker -o orderer -p org1 -p org2 -d
```

Refer to [README](https://github.com/dovetail-lab/fabric-operation/blob/master/ca/README.md) for more details of the crypto utility scripts.

### Generate Fabric network and channel artifacts

```bash
cd ../msp
./bootstrap.sh -t docker -o orderer -p org1 -p org2
```

Refer to [README](https://github.com/dovetail-lab/fabric-operation/blob/master/msp/README.md) for more details of the MSP utility scripts.

### Start Fabric network

```bash
cd ../network
./network.sh start -t docker -o orderer -p org1 -p org2
```

This will start a Fabric network including docker containers of 3 orderers and 4 peers. Refer to [README](https://github.com/dovetail-lab/fabric-operation/blob/master/network/README.md) for more details of the network utility scripts.

### Build and test a sample Dovetail chaincode

```bash
cd ../network
./smoke-test.sh docker dovetail
```

This will install and test the sample [marble_cc](./samples/marble) chaincode. Refer to [Samples](https://github.com/dovetail-lab/fabric-samples) for more details about the zero-code development of Fabric chaincode.

### Build and run client service

This step will configure and run a client service, [marble_client.json](./samples/marble_client/marble-client.json), that makes the `marble_cc` chaincode accessible via REST APIs.

First, export the connection info of the Fabric network:

```bash
cd ../service
./gateway.sh config -t docker -o orderer -p org1 -p org2
```

Second, configure the client service app [marble-client](./samples/marble_client) to use the exported network connection info:

```bash
cd ../dovetail
./dovetail.sh config-app -t docker -p org1 -m samples/marble_client/marble-client.json
```

Then, build and run the client service:

```bash
./dovetail.sh build-app -t docker -p org1 -m marble-client.json -g darwin

FLOGO_APP_PROP_RESOLVERS=env FLOGO_APP_PROPS_ENV=auto PORT=8989 APPUSER=Admin FLOGO_LOG_LEVEL=DEBUG FLOGO_SCHEMA_SUPPORT=true FLOGO_SCHEMA_VALIDATION=false CRYPTO_PATH=/Users/yxu/work/dovetail-lab2/fabric-operation/org1.example.com/gateway ../org1.example.com/gateway/marble-client_darwin_amd64
```

The client service opens a port `8989` for REST API calls. It also specifies `Admin` as the `APPUSER` that is used to send chaincode requests by this client service. This variable can be configured as any user of `org1`, e.g., `Alice` or `Bob` which are also specified in [org1.env](../config/org1.env) and created during the bootstrap process.

### Invoke chaincode using REST APIs

Import the test message [collection](https://github.com/dovetail-lab/fabric-samples/blob/master/marble/marble.postman_collection.json) to [Postman](https://www.postman.com/downloads/), and send the REST requests to update and query the `marble` chaincode.

### Shutdown and cleanup

Quit client service by `Ctrl+C`, and then stop and cleanup the Fabric network:

```bash
cd ../network
./network.sh shutdown -t docker -o orderer -p org1 -p org2 -d
cd ../msp
./msp-util.sh shutdown -t docker -p org1
```

## Use Kubernetes on local PC

The following steps are verified for Kubernetes of `Docker Desktop` on Mac. It is required that you enable Kubernetes on `Docker Desktop`.

### Configure and start Fabric network in Kubernetes

These steps are the same as those of `docker-compose` described in the previous section. Without a flag `-t`, the scripts use `Kubernetes` by default:

```bash
cd /path/to/fabric-operation/ca
./bootstrap.sh -o orderer -p org1 -p org2 -d

cd ../msp
./bootstrap.sh -o orderer -p org1 -p org2

cd ../network
./network.sh start -o orderer -p org1 -p org2
./smoke-test.sh "" dovetail
```

### Configure and start REST gateway service

```bash
cd ../service
./gateway.sh config -o orderer -p org1 -p org2
./gateway.sh start -p org1
```

The gateway service opens a port `30081` for Swagger UI that you can use to send chaincode requests. Refer [README](../service/README.md) for more details of the gateway service.

### Test chaincode using Swagger UI

Open the Swagger UI in a web-browser: [http://localhost:30081/swagger](http://localhost:30081/swagger).

Click `Try it out` for `/v1/connection`, and execute the following request:

```json
{
  "channelId": "mychannel",
  "userName": "Admin",
  "orgName": "org1"
}
```

It will return a `connectionId`: `10375918345828239422`.

Click `Try it out` for `/v1/transaction`, and execute the following query

```json
{
  "connectionId": "10375918345828239422",
  "type": "QUERY",
  "chaincodeId": "marble_cc",
  "transaction": "readMarble",
  "parameter": ["marble1"]
}
```

It will return the attributes of `marble1` that the smoke test created on the `mychannel` chain.

Click `Try it out` for `/v1/transaction` again, and execute the following transaction to transfer `marble1` to a new owner `jerry`:

```json
{
  "connectionId": "10375918345828239422",
  "type": "INVOKE",
  "chaincodeId": "marble_cc",
  "transaction": "transferMarble",
  "parameter": ["marble1", "jerry"]
}
```

Run the above query again, you should see that the `marble1` has been changed owner from `tom` to `jerry`.

Run the following query should return the full state change history of the `marble1`:

```json
{
  "connectionId": "10375918345828239422",
  "type": "QUERY",
  "chaincodeId": "marble_cc",
  "transaction": "getHistoryForMarble",
  "parameter": ["marble1"]
}
```

### Build and run client service in Kubernetes

You can configure and run a client service, [marble_client.json](./samples/marble_client/marble-client.json), that makes the `marble_cc` chaincode accessible via REST APIs.
Use the following script to build and run the client app as a Kubernetes service.

```bash
# generate network config if skipped the previous gateway test
cd ../service
./gateway.sh config -o orderer -p org1 -p org2

# build and start client using the generated network config
cd ../dovetail
./dovetail.sh config-app -p org1 -m samples/marble_client/marble-client.json -u Alice
./dovetail.sh start-app -p org1 -m marble-client.json -f
```

Notice that optionally you can specify a user name `Alice` in the specified organization `org1`, because this Dovetail model uses an environment variable `APPUSER` to configure the blockchain user used to invoke chaincode transactions. If the argument `-u` is not specified, it will use the default user `Admin`, which has been configured for both `org1` and `org2`. Besides, the flag `-f` forces a rebuild of the application to make sure that it picks the correct connection info of the Fabric network.

The above command will start 2 Kubernetes PODs and a service for `marble-client`. Once the script completes successfully, it will print out the service end-point as, e.g.,

```
access marble-client servcice at http://localhost:30194
```

You can use this end-point to update or query the blockchain ledger. [marble.postman_collection.json](https://github.com/dovetail-lab/fabric-samples/blob/master/marble/marble.postman_collection.json) contains a set of REST messages that you can import to [Postman](https://www.getpostman.com/downloads/) and invoke the `marble_cc` chaincode.

Stop the client service and gateway service after tests complete:

```bash
cd ../dovetail
./dovetail.sh stop-app -p org1 -m marble-client.json

cd ../service
./gateway.sh shutdown -p org1
```

## Build and run Dovetail app in cloud

The same scripts can be used to build and run Dovetail applications in Cloud. Refer to the following links for detailed steps on [Azure](../az/README.md), [AWS](../aws/README.md), and [Google](../gcp/README.md).
