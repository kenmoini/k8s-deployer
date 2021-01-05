#!/bin/bash

CURDIR=$(pwd)
echo $CURDIR

ln -s $CURDIR/../credentials.tf $CURDIR/credentials.tf
ln -s $CURDIR/../variables.tf $CURDIR/variables.tf
ln -s $CURDIR/../global_data.tf $CURDIR/global_data.tf
ln -s $CURDIR/../version.tf $CURDIR/version.tf