FROM quay.io/ocedo/baseimage-docker:14.04
MAINTAINER Jan Zenkner <jan.zenkner@riverbed.com>

# Stops apt-get from complaining about automated installation of packages
ENV DEBIAN_FRONTEND noninteractive

# Basic requirements to make docker in docker, sshd and downloads via curl possible
RUN apt-get update -qq && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    iptables

# Bamboo build agent requirements
ENV BAMBOO_AGENT_INSTALLER /opt/bamboo-agent.jar
ENV BAMBOO_AGENT_HOME /root/bamboo-agent-home
ENV BAMBOO_CAPABILITIES_FILE=$BAMBOO_AGENT_HOME/bin/bamboo-capabilities.properties
ADD bamboo/bamboo-capabilities.properties $BAMBOO_CAPABILITIES_FILE
ENV BAMBOO_CONFIG_FILE $BAMBOO_AGENT_HOME/bamboo-agent.cfg.xml
ADD bamboo/bamboo-agent.cfg.xml.tpl $BAMBOO_CONFIG_FILE.tpl
ADD bamboo/clearAgentSpace.sh $BAMBOO_AGENT_HOME
# Ubuntu 14.04 does not have openjdk-8 by default
RUN apt-get install -y --no-install-recommends software-properties-common \
  && add-apt-repository ppa:openjdk-r/ppa \
  && apt-get update -qq \
  && apt-get install -y --no-install-recommends openjdk-8-jre

# Install all build environments needed
ADD install/buildenv-essentials.sh /opt/install/buildenv-essentials.sh
RUN chmod +x /opt/install/buildenv-essentials.sh && sleep 1 && /opt/install/buildenv-essentials.sh

ADD install/buildenv-firmware.sh /opt/install/buildenv-firmware.sh
RUN chmod +x /opt/install/buildenv-firmware.sh && sleep 1 && /opt/install/buildenv-firmware.sh

# FIXME: broken sdk
# ADD install/buildenv-java.sh /opt/install/buildenv-java.sh
# RUN chmod +x /opt/install/buildenv-java.sh && sleep 1 && /opt/install/buildenv-java.sh

# Docker-in-Docker
# Configuration parameters
ENV DOCKER_BUCKET get.docker.com
ENV DOCKER_VERSION 1.11.1
ENV DOCKER_SHA256 893e3c6e89c0cd2c5f1e51ea41bc2dd97f5e791fcfa3cee28445df277836339d
ENV DOCKER_COMPOSE_VERSION 1.7.1
ENV DIND_COMMIT 3b5fac462d21ca164b3778647420016315289034

# Install docker-compose
RUN curl -s -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose \
  && chmod +x /usr/local/bin/docker-compose

# Install ocedo build helper
ADD install/docker-build.pl /usr/local/bin/docker-build
RUN chmod +x /usr/local/bin/docker-build

# Install docker binary and set the right docker socket permissions for the group docker
# Source: https://github.com/docker-library/docker/blob/8d8a46bbe4c018a262df473d844d548689787d6e/1.10/Dockerfile
RUN curl -fSL "https://${DOCKER_BUCKET}/builds/Linux/x86_64/docker-$DOCKER_VERSION.tgz" -o docker.tgz \
  && echo "${DOCKER_SHA256}  docker.tgz" | sha256sum -c - \
  && tar -xzvf docker.tgz \
  && mv docker/* /usr/local/bin/ \
  && rmdir docker \
  && rm docker.tgz \
  && docker -v \ 
  && chmod +x /usr/local/bin/docker

RUN groupadd docker
RUN touch /var/run/docker.sock \
  && chown root:docker /var/run/docker.sock

#Install Ansible
RUN apt-add-repository ppa:ansible/ansible
RUN apt-get update -qq && apt-get install -y \
    software-properties-common \
    ansible

# Jenkins build agent (master provisions it via SSH) requirements
RUN adduser --disabled-password --gecos "" jenkins
RUN echo "jenkins:jenkins" | chpasswd
RUN echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins

# Allow jenkins to access the docker daemon
RUN gpasswd -a jenkins docker

# Our Runit services & scripts, managed via entrypoint
ADD etc/sv/ /etc/sv
ADD etc/my_init.d/ /etc/my_init.d

# Install the helper script to make docker in docker possible
# Source: https://github.com/docker-library/docker/blob/8d8a46bbe4c018a262df473d844d548689787d6e/1.10/dind/Dockerfile
RUN wget "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind" -O /usr/local/bin/dind \
  && chmod +x /usr/local/bin/dind

# Make bash the default shell
RUN ln -sf /bin/bash /bin/sh

# By default we want the container to start the docker daemon inside our container
ENV DOCKER_DAEMON_AUTOSTART 1

VOLUME /var/lib/docker
VOLUME /root

EXPOSE 2375 22

CMD ["/sbin/my_init"]
