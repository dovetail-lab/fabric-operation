#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# bootstrap orderer genesis and channels for specified orderer and peer organizations
#   with optional target env, i.e., docker, k8s, aws, az, gcp, etc
# usage: bootstrap.sh -t <env> -o <orderer-org> -p <peer-org> -p <peer_org> -d
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   bootstrap.sh -t docker -o orderer -p org1 -p org2
# use config parameters specified in ../config/orderer.env, ../config/org1.env, and ../config/org2.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
cd ${SCRIPT_DIR}

# wait for tool container of specified org, e.g.
# waitForTool
function waitForTool {
  local ups=0
  if [ "${ENV_TYPE}" == "docker" ]; then
    ups=$(docker ps -f "status=running" | grep "tool.${FABRIC_ORG}" | wc -l)
    local retry=1
    until [ ${ups} -gt 0 ] || [ ${retry} -gt 20 ]; do
      sleep 5s
      echo -n "."
      ups=$(docker ps -f "status=running" | grep "tool.${FABRIC_ORG}" | wc -l)
      retry=$((${retry}+1))
    done
  else
    ups=$(kubectl get pod -n ${ORG} | grep 'tool' | grep Running | wc -l)
    local retry=1
    until [ ${ups} -gt 0 ] || [ ${retry} -gt 20 ]; do
      sleep 5s
      echo -n "."
      ups=$(kubectl get pod -n ${ORG} | grep 'tool' | grep Running | wc -l)
      retry=$((${retry}+1))
    done
  fi
  echo "Tool container count for ${ORG}: ${ups}"
}

# Print the usage message
function printHelp() {
  echo "Generate artifacts for orderer genesis and channel creation transactions"
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

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORDERER_ORG} ${ENV_TYPE}
peers=""
for p in "${PEER_ORGS[@]}"; do 
  peers="$peers -p $p"
done
echo "specified peers args: $peers"
echo "start tool container for $ORDERER_ORG"
./msp-util.sh start -t ${ENV_TYPE} -o $ORDERER_ORG $peers
waitForTool

echo "bootstrap genesis and channels for $ORDERER_ORG"
./msp-util.sh bootstrap -t ${ENV_TYPE} -o $ORDERER_ORG $peers

if [ ! -z "${CLEANUP}" ]; then
  echo "shutdown tool container for $ORDERER_ORG"
  ./msp-util.sh shutdown -t "${ENV_TYPE}" -o ${ORDERER_ORG}
fi

echo "artifacts are generated in ${DATA_ROOT}/tool"