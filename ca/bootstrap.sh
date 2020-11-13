#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# bootstrap crypto keys for specified orderer and peer organizations
#   with optional target env, i.e., docker, k8s, aws, az, gcp, etc
# usage: bootstrap.sh -t <env> -o <orderer-org> -p <peer-org> -p <peer_org> -d
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   bootstrap.sh -t docker -o orderer -p org1 -p org2
# use config parameters specified in ../config/orderer.env, ../config/org1.env, and ../config/org2.env

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

# Print the usage message
function printHelp() {
  echo "Create crypto data for orderers, peers and users of specified organizations"
  echo "Usage: "
  echo "  bootstrap.sh -o <orderer-org> [-p <peer-org>] [-t <env type>] [-d]"
  echo "    -o <orderer-org> - the .env file in config folder that defines properties of the orderer org, e.g., orderer (default)"
  echo "    -p <peer-org> - the .env file in config folder that defines properties of a peer org, e.g., org1"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -d - shutdown and delete all ca/tlsca server data after bootstrap"
  echo "  bootstrap.sh -h (print this message)"
  echo "  Example: "
  echo "    ./bootstrap.sh -t docker -o orderer -p org1 -p org2 -d"
}

ORDERER_ORG="orderer"
PEER_ORGS=()

while getopts "h?o:p:t:d" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  o)
    ORDERER_ORG=$OPTARG
    ;;
  p)
    PEER_ORGS+=($OPTARG)
    ;;
  t)
    ENV_TYPE=$OPTARG
    ;;
  d)
    CLEANUP="true"
    ;;
  esac
done

ORGS=($ORDERER_ORG)
for p in "${PEER_ORGS[@]}"; do 
  ORGS+=($p)
done

for org in "${ORGS[@]}"; do 
  echo "start CA server for $org"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${org} ${ENV_TYPE}
  if [ "${ENV_TYPE}" != "docker" ]; then
    echo "check if namespace ${ORG} exists"
    kubectl get namespace ${ORG}
    if [ "$?" -ne 0 ]; then
      ../namespace/k8s-namespace.sh create -p ${ORG}
    fi
  fi
  ./ca-server.sh start -t "${ENV_TYPE}" -p ${org}
  waitForCA
done

for o in "${ORGS[@]}"; do
  echo "bootstrap crypto for $o"
  source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${o} ${ENV_TYPE}
  ./ca-crypto.sh bootstrap -t "${ENV_TYPE}" -p ${o}
  if [ "${o}" == "${ORDERER_ORG}" ]; then
    ORDERER_DATA_ROOT=${DATA_ROOT}
    echo "ORDERER_DATA_ROOT: ${ORDERER_DATA_ROOT}"
  else
    # TODO: orderer tool need crypto/msp of all peer-orgs, name the folder ${FABRIC_ORG} instead of ${ORG}
    echo "copy tools data from ${DATA_ROOT} to ${ORDERER_DATA_ROOT}"
    if [ ! -d "${ORDERER_DATA_ROOT}/tool/crypto/${ORG}" ]; then
      cp -R ${DATA_ROOT}/tool/crypto/msp ${ORDERER_DATA_ROOT}/tool/crypto/${ORG}
    fi
    # TODO: handle this generally, cli need crypto/msp/tlscacerts from orderer and other peer-orgs (ref network.sh)
    echo "copy cli data from ${ORDERER_DATA_ROOT}" to ${DATA_ROOT}
    if [ ! -d "${DATA_ROOT}/cli/crypto/orderer-0/msp" ]; then
      mkdir -p ${DATA_ROOT}/cli/crypto/orderer-0/msp
      cp -R ${ORDERER_DATA_ROOT}/crypto/msp/tlscacerts ${DATA_ROOT}/cli/crypto/orderer-0/msp 
    fi
    # TODO: gateway need crypto/msp/tlscacerts from orderer
  fi
done

if [ ! -z "${CLEANUP}" ]; then
  for org in "${ORGS[@]}"; do 
    echo "shutdown and cleanup CA server for $org"
    ./ca-server.sh shutdown -t "${ENV_TYPE}" -p ${org} -d
  done
fi

echo "crypto data for ${ORDERER_ORG} are generated in ${ORDERER_DATA_ROOT}"