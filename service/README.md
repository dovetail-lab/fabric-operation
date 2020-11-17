# Fabric gateway service

The gateway service is a generic Fabric client service that provides REST and gRPC APIs for other applications to query or invoke Fabric transactions.

## Build gateway service

If you use a cloud provider, i.e., `AWS`, `Azure`, or `GCP`, you can use a `bastion` host to build and test the gateway service, and thus you do not need to install anything on your local PC. Scripts are provided to setup the `bastion` host for each of the supported cloud providers. Refer to the folder for [AWS](../aws), [Azure](../az), or [GCP](../gcp) for more details.

For local test, the gateway service is already pre-built for Mac and Linux as `gateway-darwin` and `gateway-linux`. You may also build the service from source code, but you need to install the [Golang](https://golang.org/dl/), and then install other tools by using the [Makefile](./Makefile), i.e.,

```bash
cd ../service
make tools
```

You can then build the gateway service using the [Makefile](./Makefile), i.e.,

```bash
# build gateway service for linux and mac
cd ../service
make

# copy gateway executables to deployment folder
make dist
```

## Start Fabric network using Kubernetes

Before starting the gateway service, you can follow the instructions in [README.md](../README.md) to bootstrap and start a sample Fabric network using Kubernetes, i.e.,

```bash
cd ../ca
./bootstrap.sh -o orderer -p org1 -p org2 -d
cd ../msp
./bootstrap.sh -o orderer -p org1 -p org2 -d
cd ../network
./network.sh start -o orderer -p org1 -p org2
./smoke-test.sh
```

The above sequence of commands created a Fabric network from scratch, and deployed a sample chaincode `sacc` to a test channel `mychannel`.

## Start gateway service

Use the following commands to start 2 Kubernetes PODs to run the gateway service on Mac `Docker Desktop`:

```bash
cd ../service
./gateway.sh config -o orderer -p org1 -p org1
./gateway.sh start -p org1
```

On a Mac, this gateway service listens to REST requests on a `NodePort`: `30081`. You can also run the service on a cloud provider. The scripts support [AWS](../aws), [Azure](../az), and [Google](../gcp). Click one of the links for the detailed steps on each platform.

If you want to use this service to test chaincode deployed on a local fabric test-network (in the fabric-samples), you can also run the service without Kubernetes, i.e.,

```bash
cd ../service
make run
```

## Invoke Fabric transactions using Swagger UI

Open the Swagger UI in Chrome web-browser: [http://localhost:30081/swagger](http://localhost:30081/swagger).

It defines 2 REST APIs:

- **Connection**, which creates or finds a Fabric network connection, and returns the connection-ID.
- **Transaction**, which invokes a Fabric transaction for query or invocation on a specified or randomly chosen endpoint.

Click `Try it out` for `/v1/connection`, and execute the following request

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
  "chaincodeId": "sacc",
  "transaction": "get",
  "parameter": ["a"]
}
```

It will return the current state of `a` on the sample Fabric channel, e.g. `100`.

Click `Try it out` for `/v1/transaction` again, and execute the following transaction to set the value of `b` to `200`

```json
{
  "connectionId": "10375918345828239422",
  "type": "INVOKE",
  "chaincodeId": "sacc",
  "transaction": "set",
  "parameter": ["b", "200"]
}
```

Execute the above query again, it should return a reduced value of `b`, e.g., `200`.

Note that this gateway service can be used to test any chaincode, and it supports connections to multiple channels or networks, as long as the connection is configured by using the script `./gateway.sh config [options]`. You can also use a gRPC client to send API requests to the gateway service.

## TODO

- Support HTTPS and gRPCs for secure client connections.
- Demonstrate gRPCs client app.
