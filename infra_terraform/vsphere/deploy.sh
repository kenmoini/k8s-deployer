#!/bin/bash

## set -x	## Uncomment for debugging

sudo pwd

## Include vars if the file exists
FILE=./vars.sh
if [ -f "$FILE" ]; then
    source ./vars.sh
else
    exit "Need to generate variable file first"
fi

## Functions
function checkForProgram() {
    command -v $1
    if [[ $? -eq 0 ]]; then
        printf '%-72s %-7s\n' $1 "PASSED!";
    else
        printf '%-72s %-7s\n' $1 "FAILED!";
    fi
}
function checkForProgramAndExit() {
    command -v $1
    if [[ $? -eq 0 ]]; then
        printf '%-72s %-7s\n' $1 "PASSED!";
    else
        printf '%-72s %-7s\n' $1 "FAILED!";
        exit 1
    fi
}

## Check needed binaries are installed
checkForProgramAndExit curl
checkForProgramAndExit terraform
checkForProgramAndExit govc
checkForProgramAndExit fcct

## Pull assets
. ./scripts/pull-assets.sh $FCOS_VERSION

## Initialize Terraform
terraform init

## Do an initial plan as a test
terraform plan

if [[ $? -eq 0 ]]; then
  echo ""
  echo "============================================================================"
  echo " READY!!!"
  echo "============================================================================"
  echo ""
  echo "Next, just run 'terraform apply' to deploy the cluster"
  echo ""
else
  echo ""
  echo "============================================================================"
  echo " FAILED!!!"
  echo "============================================================================"
  echo ""
  echo "There seem to be issues with planning out the terraform deployment"
  echo ""
fi