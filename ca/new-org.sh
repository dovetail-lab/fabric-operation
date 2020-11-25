#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# bootstrap a new peer org to add it to existing network

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
cd ${SCRIPT_DIR}

# wait for CA server and client containers of specified org, e.g.
# waitForCA
function waitForCA {
  local ups=0
  if [ "${ENV_TYPE}" == "docker" ]; then
    ups=$(docker ps -f "status=running" | egrep "ca.${FABRIC_ORG}|caclient.${FABRIC_ORG}" | wc -l)
    local retry=1
    until [ ${ups} -ge 3 ] || [ ${retry} -gt 10 ]; do
      sleep 5s
      echo -n "."
      ups=$(docker ps -f "status=running" | egrep "ca.${FABRIC_ORG}|caclient.${FABRIC_ORG}" | wc -l)
      retry=$((${retry}+1))
    done
  else
    ups=$(kubectl get pod -n ${ORG} | egrep 'ca-client|ca-server|tlsca-server' | grep Running | wc -l)
    local retry=1
    until [ ${ups} -ge 3 ] || [ ${retry} -gt 20 ]; do
      sleep 5s
      echo -n "."
      ups=$(kubectl get pod -n ${ORG} | egrep 'ca-client|ca-server|tlsca-server' | grep Running | wc -l)
      retry=$((${retry}+1))
    done
  fi
  echo "CA container count for ${ORG}: ${ups}"
}

function copySharedTLSCerts {
  # share tls crypto data of the orderer and other peer orgs
  for f in ${ORDERER_DATA_ROOT}/tool/crypto/*; do
    if [ -d $f ]; then
      local dir=$(basename $f)
      if [ "$dir" == "msp" ]; then
        dir=${ORDERER_ORG}
      fi
      if [ "$dir" != "orderers" ] && [ "$dir" != "${FABRIC_ORG}" ]; then
        echo "copy tls certs from $f/tlscacerts to ${DATA_ROOT}/cli/crypto/${dir}"
        if [ -d ${DATA_ROOT}/cli/crypto/${dir}/tlscacerts ]; then
          ${surm} -R ${DATA_ROOT}/cli/crypto/${dir}
        fi
        ${sumd} -p ${DATA_ROOT}/cli/crypto/${dir}
        ${sucp} -R $f/tlscacerts ${DATA_ROOT}/cli/crypto/${dir}

        echo "copy tls certs from $f/tlscacerts to ${DATA_ROOT}/gateway/${dir}"
        if [ -d ${DATA_ROOT}/gateway/${dir}/tlscacerts ]; then
          ${surm} -R ${DATA_ROOT}/gateway/${dir}
        fi
        ${sumd} -p ${DATA_ROOT}/gateway/${dir}
        ${sucp} -R $f/tlscacerts ${DATA_ROOT}/gateway/$dir

        if [ -f $f/ca/tls/server.crt ]; then
          echo "copy ca server certs from $f/ca/tls to ${DATA_ROOT}/gateway/${dir}/ca/tls"
          ${sumd} -p ${DATA_ROOT}/gateway/${dir}/ca/tls
          ${sucp} $f/ca/tls/server.crt ${DATA_ROOT}/gateway/${dir}/ca/tls
        fi
      fi
    fi
  done
}

# Print the usage message
function printHelp() {
  echo "Create crypto data for a new peer org"
  echo "Usage: "
  echo "  new-org.sh -o <orderer-org> [-p <peer-org>] [-t <env type>] [-d]"
  echo "    -o <orderer-org> - the .env file in config folder that defines properties of the orderer org, e.g., orderer"
  echo "    -p <peer-org> - the .env file in config folder that defines properties of a peer org, e.g., org3"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -d - shutdown and delete all ca/tlsca server data after bootstrap"
  echo "  new-org.sh -h (print this message)"
  echo "  Example: "
  echo "    ./new-org.sh -o orderer -p org3 -d"
}

PEER_ENVS=()

while getopts "h?o:p:t:d" opt; do
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
  d)
    CLEANUP="true"
    ;;
  esac
done

if [ -z ${ORDERER_ENV} ]; then
  echo "orderer must be specified"
  printHelp
  exit 1
fi
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ENV} ${ENV_TYPE}
ORDERER_DATA_ROOT=${DATA_ROOT}
ORDERER_ORG=${FABRIC_ORG}
echo "ORDERER_DATA_ROOT: ${ORDERER_DATA_ROOT}"

if [ ${#PEER_ENVS[@]} -eq 0 ]; then
  echo "Must specify orderer org and at least a peer org"
  printHelp
  exit 1
fi

peerOrg=${PEER_ENVS[0]}
echo "start CA server for ${peerOrg}"
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${peerOrg} ${ENV_TYPE}
if [ "${ENV_TYPE}" != "docker" ]; then
  echo "check if namespace ${ORG} exists"
  kubectl get namespace ${ORG}
  if [ "$?" -ne 0 ]; then
    ../namespace/k8s-namespace.sh create -p ${ORG}
  fi
fi
./ca-server.sh start -t "${ENV_TYPE}" -p ${peerOrg}
waitForCA

./ca-crypto.sh bootstrap -t "${ENV_TYPE}" -p ${peerOrg}
# sharing msp and ca server cert with the orderer org
echo "copy peer msp data from ${DATA_ROOT}/crypto/msp to ${ORDERER_DATA_ROOT}/tool/crypto/${FABRIC_ORG}"
${sucp} -R ${DATA_ROOT}/crypto/msp ${ORDERER_DATA_ROOT}/tool/crypto/${FABRIC_ORG}
${sumd} -p ${ORDERER_DATA_ROOT}/tool/crypto/${FABRIC_ORG}/ca/tls
${sucp} ${DATA_ROOT}/crypto/ca/tls/server.crt ${ORDERER_DATA_ROOT}/tool/crypto/${FABRIC_ORG}/ca/tls

# share tls crypt data between peer orgs
copySharedTLSCerts

if [ ! -z "${CLEANUP}" ]; then
  echo "shutdown and cleanup CA server for ${peerOrg}"
  ./ca-server.sh shutdown -t "${ENV_TYPE}" -p ${peerOrg} -d
fi
echo "crypto data for ${peerOrg} are generated in ${DATA_ROOT}"