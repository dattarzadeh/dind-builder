#!/bin/bash
set -ex
set -o pipefail

# Downloading android-sdk
wget http://dl.google.com/android/android-sdk_r24.3.2-linux.tgz
tar zxvf android-sdk_r24.3.2-linux.tgz
mv android-sdk-linux /usr/local/bin/android-sdk
rm android-sdk_r24.3.2-linux.tgz

#Update android-libs and other dependencies

# FIXME: broken sdk
# Error: Ignoring unknown package filter 'build-tools-22.0.1
# https://code.google.com/p/android/issues/detail?id=175087
( sleep 5 && while [ 1 ]; do sleep 1; echo y; done ) | /usr/local/bin/android-sdk/tools/android update sdk -u --filter build-tools-22.0.1
( sleep 5 && while [ 1 ]; do sleep 1; echo y; done ) | /usr/local/bin/android-sdk/tools/android update sdk -u --filter 2
( sleep 5 && while [ 1 ]; do sleep 1; echo y; done ) | /usr/local/bin/android-sdk/tools/android update sdk -u --filter extra-google-m2repository

apt-get install -y --no-install-recommends g++-multilib lib32z1 lib32stdc++6

chmod +x /usr/local/bin/android-sdk/tools/android
