#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# start or shutdown and config client gateway service
# usage: gateway.sh <cmd> -o <orderer-org> -p <peer-org> [-t <env type>] [-c channel>] [-u <user>]
# it uses a property file of the specified org as defined in ../config/org.env, e.g.
#   gateway.sh start -o orderer -p org1
# would use config parameters specified in ../config/orderer.env and ../config/org1.env
# the env_type can be k8s or aws/az/gcp to use local host or a cloud file system, i.e. efs/azf/gfs, default k8s for local persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

# set list of orderers from config
function getOrderers {
  ORDERERS=()
  local seq=${ORDERER_MIN:-"0"}
  local max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    ORDERERS+=("orderer-${seq}")
    seq=$((${seq}+1))
  done
}

# set list of peers from config
function getPeers {
  PEERS=()
  local seq=${PEER_MIN:-"0"}
  local max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    PEERS+=("peer-${seq}")
    seq=$((${seq}+1))
  done
}

# e.g., getHostUrl peer-1
function getHostUrl {
  if [ ! -z "${SVC_DOMAIN}" ]; then
    # for Kubernetes target
    svc=${1%%-*}
    echo "${1}.${svc}.${SVC_DOMAIN}"
  else
    # default for docker-composer
    echo "${1}.${FABRIC_ORG}"
  fi
}

# printNetworkYaml <channel>
function printNetworkYaml {
  echo "
name: ${1}
version: 1.0.0

client:
  organization: ${ORG}
  logging:
    level: info
  cryptoconfig:
    path: \${CRYPTO_PATH}

channels:
  ${1}:
    peers:"
  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    getPeers
    for p in "${PEERS[@]}"; do
      echo "
      ${p}.${FABRIC_ORG}:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true"
    done
  done
  echo "
organizations:"
  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    getPeers
    echo "  ${ORG}:
    mspid: ${ORG_MSP}
    cryptoPath:  ${FABRIC_ORG}/users/{username}@${FABRIC_ORG}/msp
    peers:"
    for p in "${PEERS[@]}"; do
      echo "      - ${p}.${FABRIC_ORG}"
    done
    echo "    certificateAuthorities:
      - ca.${FABRIC_ORG}"
  done
  echo "
orderers:"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
  getOrderers
  for ord in "${ORDERERS[@]}"; do
    echo "
  ${ord}.${FABRIC_ORG}:
    url: $(getHostUrl ${ord}):7050
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem"
  done
  echo "
peers:"
  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    getPeers
    for p in "${PEERS[@]}"; do
      echo "
  ${p}.${FABRIC_ORG}:
    url: $(getHostUrl ${p}):7051
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem"
    done
  done
  echo "
certificateAuthorities:"
  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    local caHost="ca.${FABRIC_ORG}"
    if [ ! -z "${SVC_DOMAIN}" ]; then
      caHost="ca-server.${SVC_DOMAIN}"
    fi
    echo "  ca.${FABRIC_ORG}:
    url: https://${caHost}:7054
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/ca/tls/server.crt
    registrar:
      enrollId: ${CA_ADMIN:-"caadmin"}
      enrollSecret: ${CA_PASSWD:-"caadminpw"}
    caName: ca.${FABRIC_ORG}
"
  done
}

function printLocalMatcherYaml {
  echo "entityMatchers:
  peer:"

  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    PEER_PORT=${PEER_PORT:-"7051"}

    # peer name matchers
    local seq=${PEER_MIN:-"0"}
    local max=${PEER_MAX:-"0"}
    until [ "${seq}" -ge "${max}" ]; do
      local p="peer-${seq}"
      local port=$((${seq} * 10 + ${PEER_PORT}))
      seq=$((${seq}+1))
      echo "
    - pattern: ${p}.${FABRIC_ORG}
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${p}.${FABRIC_ORG}
      mappedHost: ${p}.${FABRIC_ORG}

    - pattern: ${p}.${FABRIC_ORG}:7051
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${p}.${FABRIC_ORG}
      mappedHost: ${p}.${FABRIC_ORG}"
    done
  done
  echo "
  orderer:"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
  ORDERER_PORT=${ORDERER_PORT:-"7050"}

  # orderer name matchers
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local ord="orderer-${seq}"
    local port=$((${seq} * 10 + ${ORDERER_PORT}))
    seq=$((${seq}+1))
    echo "
    - pattern: ${ord}.${FABRIC_ORG}
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${ord}.${FABRIC_ORG}
      mappedHost: ${ord}.${FABRIC_ORG}

    - pattern: ${ord}.${FABRIC_ORG}:7050
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${ord}.${FABRIC_ORG}
      mappedHost: ${ord}.${FABRIC_ORG}"
  done

  echo "
  certificateAuthority:"

  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    caPort=${CA_PORT:-7054}
    echo "
    - pattern: ca.${FABRIC_ORG}
      urlSubstitutionExp: https://localhost:${caPort}
      sslTargetOverrideUrlSubstitutionExp: ca.${FABRIC_ORG}
      mappedHost: ca.${FABRIC_ORG}

    - pattern: ca.${FABRIC_ORG}:7054
      urlSubstitutionExp: https://localhost:${caPort}
      sslTargetOverrideUrlSubstitutionExp: ca.${FABRIC_ORG}
      mappedHost: ca.${FABRIC_ORG}"
  done
}

##############################################################################
# Kubernetes functions
##############################################################################

# print k8s persistent volume for gateway config files
# e.g., printDataPV
function printDataPV {
  local _store_size="${TOOL_PV_SIZE}"
  local _mode="ReadWriteOnce"
  local _folder="gateway"

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: data-${ORG}-gateway
  labels:
    app: data-gateway
    org: ${ORG}
spec:
  capacity:
    storage: ${_store_size}
  volumeMode: Filesystem
  accessModes:
  - ${_mode}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${ORG}-gateway-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/${_folder}"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/${_folder}
    readOnly: false
  mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=10000
  - gid=10000
  - mfsymlinks
  - nobrl"
  elif [ "${K8S_PERSISTENCE}" == "gfs" ]; then
    echo "  nfs:
    server: ${GCP_STORE_IP}
    path: /vol1/${FABRIC_ORG}/${_folder}"
  else
    echo "  hostPath:
    path: ${DATA_ROOT}/${_folder}
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-gateway
  namespace: ${ORG}
spec:
  storageClassName: ${ORG}-gateway-data-class
  accessModes:
    - ${_mode}
  resources:
    requests:
      storage: ${_store_size}
  selector:
    matchLabels:
      app: data-gateway
      org: ${ORG}"
}

# printStorageClass
# storage class for local host, or AWS EFS, or Azure Files
function printStorageClass {
  local _provision="kubernetes.io/no-provisioner"
  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    _provision="efs.csi.aws.com"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    _provision="kubernetes.io/azure-file"
  elif [ "${K8S_PERSISTENCE}" == "gfs" ]; then
    # no need to define storage class for Google Filestore
    return 0
  fi

  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: ${ORG}-gateway-data-class
provisioner: ${_provision}
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

function printStorageYaml {
  # storage class for gateway data folders
  printStorageClass

  # PV and PVC for gateway data
  printDataPV
}

# printGatewayYaml <channel> <user>
function printGatewayYaml {
  local user=${2:-"Admin"}
  echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
  namespace: ${ORG}
  labels:
    app: gateway
spec:
  replicas: 2
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: gateway
  template:
    metadata:
      labels:
        app: gateway
    spec:
      containers:
      - name: gateway
        image: golang:1.14.12-alpine3.12
        resources:
          requests:
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
        env:
        - name: CONFIG_PATH
          value: /etc/hyperledger/gateway/config
        - name: CRYPTO_PATH
          value: /etc/hyperledger/gateway
        - name: GRPC_PORT
          value: \"7082\"
        - name: HTTP_PORT
          value: \"7081\"
        - name: TLS_ENABLED
          value: \"false\"
        - name: NETWORK_FILE
          value: \"config_${1}.yaml\"
        - name: ENTITY_MATCHER_FILE
          value: \"\"
        - name: CHANNEL_ID
          value: ${1}
        - name: USER_NAME
          value: ${user}
        - name: ORG
          value: ${ORG}
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        workingDir: /etc/hyperledger/gateway
        command: [\"./gateway\"]
        args: [\"-logtostderr\", \"-v\", \"2\"]
        ports:
        - containerPort: 7081
          name: http-port
        - containerPort: 7082
          name: grpc-port
        volumeMounts:
        - mountPath: /etc/hyperledger/gateway
          name: data
      restartPolicy: Always
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-gateway
---
apiVersion: v1
kind: Service
metadata:
  name: gateway
  namespace: ${ORG}
spec:
  selector:
    app: gateway"
  if [ "${ENV_TYPE}" == "k8s" ]; then
    echo "  ports:
  # use nodePort for Mac docker-desktop, port range must be 30000-32767
  - protocol: TCP
    name: http-port
    port: 7081
    targetPort: http-port
    nodePort: 30081
  - protocol: TCP
    name: grpc-port
    port: 7082
    targetPort: grpc-port
    nodePort: 30082
  type: NodePort"
  else
    echo "  ports:
  - protocol: TCP
    name: http-port
    port: 7081
    targetPort: http-port
  - protocol: TCP
    name: grpc-port
    port: 7082
    targetPort: grpc-port
  type: LoadBalancer"
  fi
}

##############################################################################
# Gateway operations
##############################################################################

function createNetworkArtifacts {
  local configPath=${DATA_ROOT}/gateway/config
  ${sumd} -p ${configPath}
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "create network config for local host"
    printNetworkYaml ${CHANNEL_ID} > ${configPath}/config_${CHANNEL_ID}.yaml
    printLocalMatcherYaml > ${configPath}/matchers.yaml
  else
    echo "create network config"
    printNetworkYaml ${CHANNEL_ID} | ${stee} ${configPath}/config_${CHANNEL_ID}.yaml > /dev/null
    if [ -f ${configPath}/matchers.yaml ]; then
      ${surm} ${configPath}/matchers.yaml
    fi
  fi
}

function createK8sGatewayYaml {
  echo "create k8s yaml files"
  ${sumd} -p ${DATA_ROOT}/gateway/k8s
  printStorageYaml | ${stee} ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml > /dev/null
  printGatewayYaml ${CHANNEL_ID} ${USER_ID} | ${stee} ${DATA_ROOT}/gateway/k8s/gateway.yaml > /dev/null
}

# copy Admin user crypto data to first peer org's gateway for testing purpose
function copyAdminUser {
  local gatewayRoot=""
  for org in ${PEER_ENVS[@]}; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${org} ${ENV_TYPE}
    if [ -z "${gatewayRoot}" ]; then
      # set target gateway data root
      gatewayRoot=${DATA_ROOT}/gateway
    else
      local adminCrypto=${gatewayRoot}/${FABRIC_ORG}/users/${USER_ID}\@${FABRIC_ORG}
      if [ -d "${adminCrypto}" ]; then
        ${surm} -R ${adminCrypto}
      fi
      ${sumd} -p ${gatewayRoot}/${FABRIC_ORG}/users
      echo "check ${DATA_ROOT}/crypto/users/${USER_ID}@${FABRIC_ORG}"
      if [ -d "${DATA_ROOT}/crypto/users/${USER_ID}@${FABRIC_ORG}" ]; then
        echo "copy admin user to ${adminCrypto}"
        ${sucp} -R ${DATA_ROOT}/crypto/users/${USER_ID}\@${FABRIC_ORG} ${gatewayRoot}/${FABRIC_ORG}/users
      fi
    fi
  done
}

function startGateway {
  if [ ! -f ${DATA_ROOT}/gateway/config/config_${CHANNEL_ID}.yaml ]; then
    echo "Cannot find network config ${DATA_ROOT}/gateway/config/config_${CHANNEL_ID}.yaml"
    echo "Generate the network config using './gateway.sh config ..."
    exit 1
  fi

  if [ "${ENV_TYPE}" == "docker" ]; then
    if [ -f ${SCRIPT_DIR}/gateway-darwin ]; then
      echo "start gateway service"
      cd ${SCRIPT_DIR}
      CRYPTO_PATH=${DATA_ROOT}/gateway ./gateway-darwin -network config_${CHANNEL_ID}.yaml -matcher matchers.yaml -org ${ORG} -logtostderr -v 2
    else
      echo "Cannot find gateway-darwin executable. Build it and then retry."
      return 1
    fi
  else
    createK8sGatewayYaml
    if [ ! -f ${DATA_ROOT}/gateway/gateway ]; then
      if [ -f ${SCRIPT_DIR}/gateway-linux ]; then
        echo "copy gateway artifacts to ${DATA_ROOT}/gateway"
        ${sucp} ${SCRIPT_DIR}/gateway-linux ${DATA_ROOT}/gateway/gateway
        ${sucp} ${SCRIPT_DIR}/src/proto/fabric/fabric.proto ${DATA_ROOT}/gateway
        ${sucp} -Rf ${SCRIPT_DIR}/swagger-ui ${DATA_ROOT}/gateway
      else
        echo "cannot find gateway executable 'gateway-linux'. Build it and then retry."
        return 1
      fi
    fi

    echo "start gateway service"
    kubectl create -f ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml
    kubectl create -f ${DATA_ROOT}/gateway/k8s/gateway.yaml
    if [ "${ENV_TYPE}" == "k8s" ]; then
      echo "browse gateway REST swagger-ui at http://localhost:30081/swagger"
      echo "view gateway grpc service defintion at http://localhost:30081/doc"
    elif [ "${ENV_TYPE}" == "aws" ]; then
      ${SCRIPT_DIR}/../aws/setup-service-sg.sh ${ORG} "gateway"
    elif [ "${ENV_TYPE}" == "az" ] || [ "${ENV_TYPE}" == "gcp" ]; then
      # wait for load-balancer to start
      local lbip=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
      local cnt=1
      until [ ! -z "${lbip}" ] || [ ${cnt} -gt 20 ]; do
        sleep 5s
        echo -n "."
        lbip=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
        cnt=$((${cnt}+1))
      done
      if [ -z "${lbip}" ]; then
        echo "cannot find k8s gateway service for org: ${ORG}"
      else
        echo "browse gateway swagger UI at http://${lbip}:7081/swagger"
      fi
    fi
  fi
}

function shutdownGateway {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "You can shutdown gateway by Ctrl+C"
  else
    echo "stop gateway service ..."
    kubectl delete -f ${DATA_ROOT}/gateway/k8s/gateway.yaml
    kubectl delete -f ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  gateway.sh <cmd> [-p <property file>] [-t <env type>] [-c channel>] [-u <user>]"
  echo "    <cmd> - one of the following commands:"
  echo "      - 'start' - start gateway service, arguments: -p <peer-org> [-t <env-type>] [-c channel>] [-u <user>]"
  echo "      - 'shutdown' - shutdown gateway service, arguments: [-p <peer-org>] [-t <env-type>]"
  echo "      - 'config' - create gateway artifacts, arguments: -o <orderer-org> -p <peer-org> [-t <env-type>] [-c channel>] [-u <user>]"
  echo "    -o <orderer-org> - the .env file in config folder that defines orderer org properties, e.g., orderer (default)"
  echo "    -p <peer-org> - the .env file in config folder that defines peer org properties, e.g., org1"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -c <channel> - default channel ID that the gateway will connect to, default 'mychannel'"
  echo "    -u <user> - default user that the gateway will use to connect to fabric network, default 'Admin'"
  echo "  gateway.sh -h (print this message)"
  echo "  Example:"
  echo "    ./gateway.sh config -o orderer -p org1 -p org2"
  echo "    ./gateway.sh start -p org1"
  echo "    ./gateway.sh shutdown -p org1"
}

PEER_ENVS=()

CMD=${1}
if [ "${CMD}" != "-h" ]; then
  shift
fi
while getopts "h?o:p:t:c:u:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  o)
    ORDERER_ENV=$OPTARG
    ;;
  p)
    PEER_ENVS+=($OPTARG)
    ;;
  t)
    ENV_TYPE=$OPTARG
    ;;
  u)
    USER_ID=$OPTARG
    ;;
  c)
    CHANNEL_ID=$OPTARG
    ;;
  esac
done

if [ ${#PEER_ENVS[@]} -gt 0 ]; then
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${PEER_ENVS[0]} ${ENV_TYPE}
else
  echo "Must specify at least one peer org"
  printHelp
  exit 1
fi
if [ -z "${USER_ID}" ]; then
  USER_ID=${ADMIN_USER:-"Admin"}
fi
if [ -z "${CHANNEL_ID}" ]; then
  CHANNEL_ID=${TEST_CHANNEL:-"mychannel"}
fi
POD_CPU=${POD_CPU:-"500m"}
POD_MEM=${POD_MEM:-"1Gi"}

case "${CMD}" in
start)
  echo "start gateway service: ${PEER_ENVS[@]} ${ENV_TYPE} ${CHANNEL_ID} ${USER_ID}"
  startGateway
  ;;
shutdown)
  echo "shutdown gateway service: ${PEER_ENVS[@]} ${ENV_TYPE}"
  shutdownGateway
  ;;
config)
  if [ -z "${ORDERER_ENV}" ]; then
    echo "orderer org must be specified"
    printHelp
    exit 1
  fi
  echo "config gateway service: ${ORDERER_ENV} ${PEER_ENVS[@]} ${ENV_TYPE} ${CHANNEL_ID}"
  createNetworkArtifacts
  if [ ${#PEER_ENVS[@]} -gt 1 ]; then
    copyAdminUser
  fi
  ;;
*)
  printHelp
  exit 1
esac
