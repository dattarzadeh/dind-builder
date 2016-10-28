#!/bin/bash
set -ex
set -o pipefail

apt-get install -y \
pxz \
git \
python-pip

yes | pip install awscli