#!/bin/bash

FCOS_VERSION=${1}

mkdir -p /tmp/.k8s-deployer/cache/

if [ ! -f /tmp/.k8s-deployer/cache/fedora-coreos-${FCOS_VERSION}-vmware.x86_64.ova ]; then
  curl -L -o /tmp/.k8s-deployer/cache/fedora-coreos-${FCOS_VERSION}-vmware.x86_64.ova https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${FCOS_VERSION}/x86_64/fedora-coreos-${FCOS_VERSION}-vmware.x86_64.ova
fi