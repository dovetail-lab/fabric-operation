#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create MSP configuration, channel profile, and orderer genesis block
#   for target environment, i.e., docker, k8s, aws, az, gcp, etc
# usage: msp-util.sh -h
# to display usage info

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
PEER_MSPS=()

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

# set list of orderers from config
function getOrderers {
  ORDERERS=()
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    ORDERERS+=("orderer-${seq}")
    seq=$((${seq}+1))
  done
}

function printOrdererMSP {
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}

  echo "
    - &${ORG_MSP}
        Name: ${ORG_MSP}
        ID: ${ORG_MSP}
        MSPDir: /etc/hyperledger/tool/crypto/msp
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.member')\"
            Writers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.member')\"
            Admins:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin')\"
        OrdererEndpoints:"
  for ord in "${ORDERERS[@]}"; do
    echo "            - $(getHostUrl ${ord}):7050"
  done
}

# printPeerMSP <org_name>
# printPeerMSP org1
function printPeerMSP {
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1} ${ENV_TYPE}

  echo "
    - &${ORG_MSP}
        Name: ${ORG_MSP}
        ID: ${ORG_MSP}
        MSPDir: /etc/hyperledger/tool/crypto/${FABRIC_ORG}
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin', '${ORG_MSP}.peer', '${ORG_MSP}.client')\"
            Writers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin', '${ORG_MSP}.client')\"
            Admins:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin')\"
            Endorsement:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.peer')\"
        AnchorPeers:
            - Host: $(getHostUrl peer-0)
              Port: 7051"
}

function printCapabilities {
  echo "
Capabilities:
    Channel: &ChannelCapabilities
        V2_0: true
    Orderer: &OrdererCapabilities
        V2_0: true
    Application: &ApplicationCapabilities
        V2_0: true"
}

function printApplicationDefaults {
  echo "
Application: &ApplicationDefaults
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
        LifecycleEndorsement:
            Type: ImplicitMeta
            Rule: \"MAJORITY Endorsement\"
        Endorsement:
            Type: ImplicitMeta
            Rule: \"MAJORITY Endorsement\"

    Capabilities:
        <<: *ApplicationCapabilities"
}

function printOrdererDefaults {
  echo "
Orderer: &OrdererDefaults
    OrdererType: etcdraft
    Addresses:"
  for ord in "${ORDERERS[@]}"; do
    echo "        - $(getHostUrl ${ord}):7050"
  done
  echo "    EtcdRaft:
        Consenters:"
  for ord in "${ORDERERS[@]}"; do
    echo "        - Host: $(getHostUrl ${ord})
          Port: 7050
          ClientTLSCert: /etc/hyperledger/tool/crypto/orderers/${ord}/tls/server.crt
          ServerTLSCert: /etc/hyperledger/tool/crypto/orderers/${ord}/tls/server.crt"
  done
  echo "    BatchTimeout: 2s
    BatchSize:
        MaxMessageCount: 10
        AbsoluteMaxBytes: 99 MB
        PreferredMaxBytes: 512 KB
    Organizations:

    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
        BlockValidation:
            Type: ImplicitMeta
            Rule: \"ANY Writers\""
}

function printChannelDefaults {
  echo "
Channel: &ChannelDefaults
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
    Capabilities:
        <<: *ChannelCapabilities"
}

function printOrdererGenesisProfile {
  echo "
    AppOrdererGenesis:
        <<: *ChannelDefaults
        Orderer:
            <<: *OrdererDefaults
            Organizations:
                - *${ORG_MSP}
            Capabilities:
                <<: *OrdererCapabilities
        Consortiums:
            AppConsortium:
                Organizations:"
  for p in "${PEER_MSPS[@]}"; do
    echo "                    - *$p"
  done
}

function printChannelProfile {
  echo "
    AppChannel:
        Consortium: AppConsortium
        <<: *ChannelDefaults
        Application:
            <<: *ApplicationDefaults
            Organizations:"
  for p in "${PEER_MSPS[@]}"; do
    echo "                - *$p"
  done
  echo "            Capabilities:
                <<: *ApplicationCapabilities"
}

function printConfigTx {
  getOrderers

  echo "---
Organizations:"
  for p in "${PEER_ENVS[@]}"; do
    printPeerMSP $p
  done
  printOrdererMSP

  printCapabilities
  printApplicationDefaults
  printOrdererDefaults
  printChannelDefaults

  echo "
Profiles:"
  printOrdererGenesisProfile
  printChannelProfile
}

function printDockerYaml {
  local cn="tool.${FABRIC_ORG}"
  echo "version: '3.7'

services:
  ${cn}:
    container_name: ${cn}
    image: yxuco/dovetail-tools:v1.2.0
    tty: true
    stdin_open: true
    environment:
      - FABRIC_CFG_PATH=/etc/hyperledger/tool
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - FABRIC_LOGGING_SPEC=INFO
      - SYS_CHANNEL=${SYS_CHANNEL}
      - ORG=${ORG}
      - ORG_MSP=${ORG_MSP}
      - TEST_CHANNEL=${TEST_CHANNEL}
      - FABRIC_ORG=${FABRIC_ORG}
      - WORK=/etc/hyperledger/tool
    working_dir: /etc/hyperledger/tool
    command: /bin/bash -c 'while true; do sleep 30; done'
    volumes:
        - /var/run/:/host/var/run/
        - ${DATA_ROOT}/tool/:/etc/hyperledger/tool
    networks:
    - ${ORG}

networks:
  ${ORG}:
"
}

# print k8s PV and PVC for tool Pod
function printK8sStorageYaml {
  printK8sStorageClass
  printK8sPV
}

# printK8sStorageClass for tool container
# storage class for local host, or AWS EFS, Azure File, or GCP Filestore
function printK8sStorageClass {
  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    PROVISIONER="efs.csi.aws.com"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    PROVISIONER="kubernetes.io/azure-file"
  elif [ "${K8S_PERSISTENCE}" == "gfs" ]; then
    # no need to define storage class for GCP Filestore
    return 0
  else
    # default to local host
    PROVISIONER="kubernetes.io/no-provisioner"
  fi

  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: ${ORG}-tool-data-class
provisioner: ${PROVISIONER}
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

# printK8sPV for tool container
function printK8sPV {
  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: data-${ORG}-tool
  labels:
    app: data-tool
    org: ${ORG}
spec:
  capacity:
    storage: ${TOOL_PV_SIZE}
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${ORG}-tool-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/tool"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/tool
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
    path: /vol1/${FABRIC_ORG}/tool"
  else
    echo "  hostPath:
    path: ${DATA_ROOT}/tool
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-tool
  namespace: ${ORG}
spec:
  storageClassName: ${ORG}-tool-data-class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${TOOL_PV_SIZE}
  selector:
    matchLabels:
      app: data-tool
      org: ${ORG}"
}

function printK8sPod {
#  local image="hyperledger/fabric-tools"
  local image="yxuco/dovetail-tools:v1.2.0"
  echo "
apiVersion: v1
kind: Pod
metadata:
  name: tool
  namespace: ${ORG}
spec:
  containers:
  - name: tool
    image: ${image}
    imagePullPolicy: Always
    resources:
      requests:
        memory: ${POD_MEM}
        cpu: ${POD_CPU}
    env:
    - name: FABRIC_LOGGING_SPEC
      value: INFO
    - name: GOPATH
      value: /opt/gopath
    - name: FABRIC_CFG_PATH
      value: /etc/hyperledger/tool
    - name: CORE_VM_ENDPOINT
      value: unix:///host/var/run/docker.sock
    - name: SYS_CHANNEL
      value: ${SYS_CHANNEL}
    - name: ORG
      value: ${ORG}
    - name: ORG_MSP
      value: ${ORG_MSP}
    - name: TEST_CHANNEL
      value: ${TEST_CHANNEL}
    - name: SVC_DOMAIN
      value: ${SVC_DOMAIN}
    - name: WORK
      value: /etc/hyperledger/tool
    command:
    - /bin/bash
    - -c
    - while true; do sleep 30; done
    workingDir: /etc/hyperledger
    volumeMounts:
    - mountPath: /host/var/run
      name: docker-sock
    - mountPath: /etc/hyperledger/tool
      name: data
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run
      type: Directory
  - name: data
    persistentVolumeClaim:
      claimName: data-tool"
}

function startService {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "use docker-compose"
    # start tool container to generate genesis block and channel tx
    mkdir -p "${DATA_ROOT}/tool/docker"
    printDockerYaml > ${DATA_ROOT}/tool/docker/docker-compose.yaml
    local ups=$(docker ps -f "status=running" | grep "tool.${ORG}" | wc -l)
    if [ $ups -gt 0 ]; then
      echo "Tools container tool.${ORG} is already running"
    else
      docker-compose -p tool-${ORG} -f ${DATA_ROOT}/tool/docker/docker-compose.yaml up -d
    fi
  else
    echo "use kubernetes"
    # print k8s yaml for tool job
    ${sumd} -p "${DATA_ROOT}/tool/k8s"
    printK8sStorageYaml | ${stee} ${DATA_ROOT}/tool/k8s/tool-pv.yaml > /dev/null
    printK8sPod | ${stee} ${DATA_ROOT}/tool/k8s/tool.yaml > /dev/null
    # run tool job
    kubectl create -f ${DATA_ROOT}/tool/k8s/tool-pv.yaml
    kubectl create -f ${DATA_ROOT}/tool/k8s/tool.yaml
  fi

  ${sucp} ${SCRIPT_DIR}/gen-artifact.sh ${DATA_ROOT}/tool
}

function shutdownService {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "shutdown docker msp tools"
    docker-compose -p tool-${ORG} -f ${DATA_ROOT}/tool/docker/docker-compose.yaml down --volumes --remove-orphans
  else
    echo "shutdown K8s msp tools"
    kubectl delete -f ${DATA_ROOT}/tool/k8s/tool.yaml
    kubectl delete -f ${DATA_ROOT}/tool/k8s/tool-pv.yaml
  fi
}

function execCommand {
  local _cmd="gen-artifact.sh $@"
  echo "execute command ${_cmd}"
  if [ "${ENV_TYPE}" == "docker" ]; then
    docker exec -it tool.${FABRIC_ORG} bash -c "./${_cmd}"
  else
    kubectl exec -it tool -n ${ORG} -- bash -c "cd tool && ./${_cmd}"
  fi
}

# build chaincode cds package from flogo model json
function buildFlogoChaincode {
  if [ -z "${MODEL}" ]; then
    echo "Model json file is not specified"
    printHelp
    return 1
  fi
  local _model=${MODEL##*/}
  local name="${_model%.*}_cc"
  local _src=${MODEL%/*}
  if [ "${_src}" == "${_model}" ]; then
    echo "set model file directory to PWD"
    _src="."
  fi
  if [ -f "${DATA_ROOT}/tool/${name}/${_model}" ]; then
    echo "cleanup old model in ${DATA_ROOT}/tool/${name}"
    ${surm} -rf ${DATA_ROOT}/tool/${name}
  fi
  echo "copy ${MODEL} to ${DATA_ROOT}/tool/${name}"
  ${sumd} -p ${DATA_ROOT}/tool/${name}
  ${sucp} ${MODEL} ${DATA_ROOT}/tool/${name}
  if [ -d "${_src}/META-INF" ]; then
    echo "copy META-INF from model folder"
    ${surm} -rf ${DATA_ROOT}/tool/${name}/META-INF
    ${sucp} -rf ${_src}/META-INF ${DATA_ROOT}/tool/${name}
  fi

  local cmd="fabric-cli/scripts/build-cds.sh ${_model} ${name} ${VERSION}"
  if [ "${ENV_TYPE}" == "docker" ]; then
    docker exec -it tool.${FABRIC_ORG} bash -c "/root/${cmd}"
  else
    kubectl exec -it tool -n ${ORG} -- bash -c "/root/${cmd}"
  fi
  ${sumv} ${DATA_ROOT}/tool/${name}/${name}_${VERSION}.tar.gz ${DATA_ROOT}/tool

  # copy to peer-org's cli for installation if PEER_ENVS are specified
  local pack=${DATA_ROOT}/tool/${name}_${VERSION}.tar.gz
  echo "chaincode package is built in folder ${pack}"
  for po in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${po} ${ENV_TYPE}
    echo "copy chaincode package to ${DATA_ROOT}/cli"
    ${sucp} ${pack} ${DATA_ROOT}/cli
  done
}

# build app executable from flogo model json
function buildFlogoApp {
  if [ -z "${MODEL}" ]; then
    echo "Model json file is not specified"
    printHelp
    return 1
  fi
  local _model=${MODEL##*/}
  local name=${_model%.*}
  name=${name//_/-}
  local _goos=${GO_OS}
  if [ -z "${GO_OS}" ]; then
    _goos="linux"
  fi

  if [ -f "${DATA_ROOT}/tool/${name}/${_model}" ]; then
    echo "cleanup old model in ${DATA_ROOT}/tool/${name}"
    ${surm} -rf ${DATA_ROOT}/tool/${name}
  fi
  echo "copy ${MODEL} to ${DATA_ROOT}/tool/${name}"
  ${sumd} -p ${DATA_ROOT}/tool/${name}
  ${sucp} ${MODEL} ${DATA_ROOT}/tool/${name}

  cmd="fabric-cli/scripts/build-client.sh ${_model} ${name} ${_goos} amd64"
  if [ "${ENV_TYPE}" == "docker" ]; then
    docker exec -it tool.${FABRIC_ORG} bash -c "/root/${cmd}"
  else
    kubectl exec -it tool -n ${ORG} -- bash -c "/root/${cmd}"
  fi

  ${sumv} ${DATA_ROOT}/tool/${name}/${name}_${_goos}_amd64 ${DATA_ROOT}/tool
  echo "app executable is built in folder ${DATA_ROOT}/tool"
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  msp-util.sh <cmd> [-o <orderer-org>] [-p <peer-org>] [-t <env type>] [-c <channel name>]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'start' - start tools container to run msp-util"
  echo "      - 'shutdown' - shutdown tools container for the msp-util"
  echo "      - 'bootstrap' - generate bootstrap genesis block and test channel tx defined in network spec"
  echo "      - 'genesis' - generate genesis block of etcd raft consensus"
  echo "      - 'channel' - generate channel creation tx for specified channel name, with argument '-c <channel name> -p <peer-org>'"
  echo "      - 'new-org' - create artifacts for a new peer org to be added to the network"
  echo "      - 'build-cds' - build chaincode cds package from flogo model, with arguments -m <model-json> [-v <version>]"
  echo "      - 'build-app' - build linux executable from flogo model, with arguments -m <model-json> -g <go-os>"
  echo "    -o <orderer-org> - the .env file in config folder that defines the orderer org, e.g., orderer (default)"
  echo "    -p <peer-org> - the .env file in config folder that defines a peer org, e.g., org1"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -c <channel name> - name of a channel, used with the 'channel' command"
  echo "    -m <model json> - Flogo model json file"
  echo "    -g <go-os> - target os, e.g., linux (default) or darwin"
  echo "    -v <cc version> - version of chaincode"
  echo "  msp-util.sh -h (print this message)"
  echo "  Example:"
  echo "    ./msp-util.sh start -t docker -o orderer"
  echo "    ./msp-util.sh bootstrap -t docker -o orderer -p org1 -p org2"
  echo "    ./msp-util.sh shutdown -t docker -o orderer"
}

PEER_ENVS=()
# default chaincode version
VERSION=1.0

CMD=${1}
if [ "${CMD}" != "-h" ]; then
  shift
fi
while getopts "h?o:p:t:c:m:g:v:" opt; do
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
  c)
    CHAN_NAME=$OPTARG
    ;;
  m)
    MODEL=$OPTARG
    ;;
  g)
    GO_OS=$OPTARG
    ;;
  v)
    VERSION=$OPTARG
    ;;
  esac
done

if [ ! -z "${ORDERER_ENV}" ]; then
  echo "set env to ${ORDERER_ENV}"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
elif [ ${#PEER_ENVS[@]} -gt 0 ]; then
  echo "set env to ${PEER_ENVS[0]}"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${PEER_ENVS[0]} ${ENV_TYPE}
fi

case "${CMD}" in
start)
  echo "start msp util tool: ${ORDERER_ENV} ${PEER_ENVS[@]} ${ENV_TYPE}"
  startService
  ;;
shutdown)
  echo "shutdown msp util tool: ${ORDERER_ENV} ${PEER_ENVS[@]} ${ENV_TYPE}"
  shutdownService
  ;;
bootstrap)
  echo "bootstrap msp artifacts: ${ORDERER_ENV} ${PEER_ENVS[@]} ${ENV_TYPE}"
  if [ -z ${ORDERER_ENV} ]; then
    echo "orderer org must be specified"
    printHelp
    exit 1
  fi

  for p in "${PEER_ENVS[@]}"; do
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${p} ${ENV_TYPE}
    PEER_MSPS+=(${ORG_MSP})
  done
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
  echo "create ${DATA_ROOT}/tool/configtx.yaml"
  printConfigTx | ${stee} ${DATA_ROOT}/tool/configtx.yaml > /dev/null

  execCommand "bootstrap ${PEER_MSPS[@]}"
  ;;
channel)
  echo "create channel tx for channel: [ ${CHAN_NAME} ${PEER_ENVS[@]} ]"
  if [ -z "${CHAN_NAME}" ]; then
    echo "Error: channel name not specified"
    printHelp
  else
    for p in "${PEER_ENVS[@]}"; do
      source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${p} ${ENV_TYPE}
      PEER_MSPS+=(${ORG_MSP})
    done
    source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
    execCommand "channel ${CHAN_NAME} ${PEER_MSPS[@]}"
  fi
  ;;
new-org)
  echo "create new peer org artifacts: ${ORDERER_ENV} ${PEER_ENVS[@]} ${ENV_TYPE}"
  if [ -z ${ORDERER_ENV} ]; then
    echo "orderer org must be specified"
    printHelp
    exit 1
  fi
  if [ ${#PEER_ENVS[@]} -eq 0 ]; then
    echo "Must specify a peer org to create"
    printHelp
    exit 1
  fi

  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${PEER_ENVS[0]} ${ENV_TYPE}
  PEER_MSPS+=(${ORG_MSP})
  ANCHOR="peer-0.${FABRIC_ORG}"
  if [ ! -z "${SVC_DOMAIN}" ]; then
    ANCHOR="peer-0.peer.${SVC_DOMAIN}"
  fi

  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
  echo "create ${DATA_ROOT}/tool/configtx.yaml"
  if [ -f ${DATA_ROOT}/tool/configtx.yaml ]; then
    ${sucp} ${DATA_ROOT}/tool/configtx.yaml ${DATA_ROOT}/tool/configtx_orig.yaml
  fi
  printConfigTx | ${stee} ${DATA_ROOT}/tool/configtx.yaml > /dev/null

  execCommand "new-org ${PEER_MSPS[0]} ${ANCHOR}"
  ;;
genesis)
  echo "create genesis block for etcd raft consensus"
  execCommand genesis
  ;;
build-cds)
  echo "build chaincode package: ${MODEL} ${VERSION}"
  buildFlogoChaincode
  ;;
build-app)
  echo "build executable for app: ${MODEL} ${GO_OS}"
  buildFlogoApp
  ;;
*)
  printHelp
  exit 1
esac
