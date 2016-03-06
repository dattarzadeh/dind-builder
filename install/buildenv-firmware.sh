#!/bin/bash
set -ex
set -o pipefail

apt-get install -y \
build-essential \
pbuilder \
dh-make \
dh-make-perl \
pbuilder-scripts \
ubuntu-dev-tools \
libncurses5-dev \
zlib1g-dev \
gawk \
subversion \
libssl-dev \
libfile-slurp-perl \
libipc-system-simple-perl \
libxml-parser-perl
