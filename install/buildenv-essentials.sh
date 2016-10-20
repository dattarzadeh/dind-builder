#!/bin/bash
set -ex
set -o pipefail

apt-get install -y \
pxz \
git \
s3cmd
