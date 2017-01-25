#!/bin/bash
set -ex

apt-get install -y \
pxz \
git \
python-pip

yes | pip install -I packaging appdirs awscli jira click
