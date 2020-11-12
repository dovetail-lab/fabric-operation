#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# setup variables for target environment, i.e., docker, k8s, aws, az, gcp, etc
# usage: setup.sh <org_name> <env>
# it uses config parameters of the specified org as defined in org_name.env, e.g.
#   setup.sh org1 docker
# using config parameters specified in ./org1.env

curr_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${curr_dir}/${1:-"org1"}.env

# set defaults
FAB_VERSION=${FAB_VERSION:-"2.2.1"}
CA_VERSION=${CA_VERSION:-"1.4.9"}

ORG=${FABRIC_ORG%%.*}
ORG_MSP="${ORG}MSP"
SYS_CHANNEL=${SYS_CHANNEL:-"sys-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}
POD_CPU=${POD_CPU:-"100m"}
POD_MEM=${POD_MEM:-"500Mi"}
NODE_PV_SIZE=${NODE_PV_SIZE:-"500Mi"}
TOOL_PV_SIZE=${TOOL_PV_SIZE:-"100Mi"}

MOUNT_POINT=mnt/share

# AWS EFS variables populated by aws startup
AWS_FSID=fs-aec3d805
# Azure File variables populated by Azure startup
AZ_STORAGE_SHARE=fabshare
# Google Filestore variables populated by GCP startup
GCP_STORE_IP=10.216.129.154

target=${2}
# set ENV_TYPE according to /mnt/share mount point if ${2} is empty
if [ -z "${target}" ]; then
  # default to local Kubernetes
  target="k8s"
  fs=$(df | grep ${MOUNT_POINT} | awk '{print $1}')
  if [[ $fs == *efs.*.amazonaws.com* ]]; then
    target="aws"
  elif [[ $fs == *file.core.windows.net* ]]; then
    target="az"
  elif [[ $fs == */vol1 ]]; then
    target="gcp"
  fi
  ENV_TYPE=${target}
fi

if [ "${target}" == "docker" ]; then
  SVC_DOMAIN=""
else
  # config for kubernetes
  DNS_IP=$(kubectl get svc --all-namespaces -o wide | grep kube-dns | awk '{print $4}')
  SVC_DOMAIN="${ORG}.svc.cluster.local"
fi

sumd="sudo mkdir"
sucp="sudo cp"
surm="sudo rm"
sumv="sudo mv"
stee="sudo tee"
DATA_ROOT="/${MOUNT_POINT}/${FABRIC_ORG}"
# Kubernetes persistence type: local | efs | azf | gfs
if [ "${target}" == "aws" ]; then
  K8S_PERSISTENCE="efs"
elif [ "${target}" == "az" ]; then
  K8S_PERSISTENCE="azf"
elif [ "${target}" == "gcp" ]; then
  K8S_PERSISTENCE="gfs"
else
  DATA_ROOT=$(dirname "${curr_dir}")/${FABRIC_ORG}
  K8S_PERSISTENCE="local"
  sumd="mkdir"
  sucp="cp"
  surm="rm"
  sumv="mv"
  stee="tee"
fi
${sumd} -p ${DATA_ROOT}
