#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Run this sript in tool container to generate network artifacts
# usage: gen-artifact.sh <cmd> <args>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

function bootstrap {
  createGenesisBlock
  createChannelTx ${TEST_CHANNEL} $@
}

function createGenesisBlock {
  echo "create orderer genesis block for ${SYS_CHANNEL}"
  configtxgen -profile AppOrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./orderer-genesis.block
}

function createChannelTx {
  local c=${1}
  shift
  echo "create channel tx for ${c}"
  configtxgen -profile AppChannel -outputCreateChannelTx ./${c}.tx -channelID ${c}
  if [ "$#" -gt "0" ]; then
    for org in "$@"; do
      echo "create anchor tx for channel $c and org $org"
      configtxgen -profile AppChannel -outputAnchorPeersUpdate ./${c}-anchors-${org}.tx -channelID ${c} -asOrg ${org}
    done
  fi
}

# anchorConfig <anchorPeer>
function anchorConfig {
  echo "{
	\"values\": {
    \"AnchorPeers\": {
      \"mod_policy\": \"Admins\",
      \"value\": {
        \"anchor_peers\": [
          {
            \"host\": \"${1}\",
            \"port\": 7051
          }
        ]
      },
      \"version\": \"0\"
    }
  }
}"
}

# createOrg <orgMSP> <anchorPeer>
function createOrg {
  # create channel artifacts for test-channel
  createChannelTx ${TEST_CHANNEL} ${1}

  configtxgen -printOrg ${1} > mspConfig.json
  anchorConfig ${2} > anchorConfig.json
  jq -s '.[0] * .[1]' mspConfig.json anchorConfig.json > ${1}.json
  echo "created peer MSP config file: ${1}.json"
}

# Print the usage message
function printUsage {
  echo "Usage: "
  echo "  gen-artifact.sh <cmd> <args>"
  echo "    <cmd> - one of 'bootstrap', 'genesis', or 'channel'"
  echo "      - 'bootstrap' (default) - generate genesis block and test-channel tx as specified by container env"
  echo "      - 'mspconfig' - print peer MSP config json for adding to a network"
  echo "      - 'genesis' - generate genesis block for specified orderer type, <args> = <orderer type>"
  echo "      - 'channel' - generate tx for create and anchor of a channel, <args> = <channel name> [<peer orgs>]"
}

CMD=${1:-"bootstrap"}
shift
ARGS="$@"

case "${CMD}" in
bootstrap)
  echo "bootstrap orderer genesis block and tx for test channel ${TEST_CHANNEL}"
  bootstrap ${ARGS}
  ;;
new-org)
  echo "create artifacts of a new peer org to be added to the network - ${ARGS}"
  createOrg ${ARGS}
  ;;
genesis)
  echo "create genesis block for etcd raft consensus"
  createGenesisBlock ${ARGS}
  ;;
channel)
  if [ -z "${ARGS}" ]; then
    echo "channel name not specified for tx"
    printUsage
    exit 1
  else
    echo "create tx for channel [ ${ARGS} ]"
    createChannelTx ${ARGS}
  fi
  ;;
*)
  printUsage
  exit 1
esac