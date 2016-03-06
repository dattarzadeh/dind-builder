FROM ubuntu:latest
MAINTAINER Julian Klinck <git@lab10.de>

# Stops apt-get from complaining about automated installation of packages
ENV DEBIAN_FRONTEND noninteractive

# Basic requirements to make docker in docker, sshd and downloads via curl possible
RUN apt-get update -qq && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    iptables \
    openssh-server
RUN locale-gen en_US.UTF-8

# The SSH server needs that to startup
RUN mkdir -p /var/run/sshd

# Jenkins build agent (master provisions it via SSH) requirements
RUN adduser --disabled-password --gecos "" jenkins
RUN echo "jenkins:jenkins" | chpasswd
RUN echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins

# Bamboo build agent requirements
ENV BAMBOO_AGENT_INSTALLER /opt/bamboo-agent.jar
ENV BAMBOO_AGENT_HOME /root/bamboo-agent-home
ENV BAMBOO_CAPABILITIES_FILE bin/bamboo-capabilities.properties
# Ubuntu 14.04 does not have openjdk-8 by default
ADD bamboo/bamboo-capabilities.properties $BAMBOO_AGENT_HOME/$BAMBOO_CAPABILITIES_FILE
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
ENV DOCKER_VERSION 1.10.2
ENV DOCKER_SHA256 3fcac4f30e1c1a346c52ba33104175ae4ccbd9b9dbb947f56a0a32c9e401b768
ENV DOCKER_COMPOSE_VERSION 1.6.2
ENV DIND_COMMIT 3b5fac462d21ca164b3778647420016315289034

# Install docker-compose
RUN curl -s -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose \
  && chmod +x /usr/local/bin/docker-compose

# Install ocedo build helper
ADD install/docker-build.pl /usr/local/bin/docker-build
RUN chmod +x /usr/local/bin/docker-build

# Install docker binary and set the right docker socket permissions for the group docker
# Source: https://github.com/docker-library/docker/blob/8d8a46bbe4c018a262df473d844d548689787d6e/1.10/Dockerfile
RUN curl -fSL "https://${DOCKER_BUCKET}/builds/Linux/x86_64/docker-$DOCKER_VERSION" -o /usr/local/bin/docker \
  && echo "${DOCKER_SHA256}  /usr/local/bin/docker" | sha256sum -c - \
  && chmod +x /usr/local/bin/docker
RUN groupadd docker
RUN touch /var/run/docker.sock \
  && chown root:docker /var/run/docker.sock

# Allow jenkins to access the docker daemon
RUN gpasswd -a jenkins docker

# Install the helper script to make docker in docker possible
# Source: https://github.com/docker-library/docker/blob/8d8a46bbe4c018a262df473d844d548689787d6e/1.10/dind/Dockerfile
RUN wget "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind" -O /usr/local/bin/dind \
  && chmod +x /usr/local/bin/dind

# By default we want the container to start the docker daemon inside our container
ENV DOCKER_DAEMON_AUTOSTART 1

COPY entrypoint.sh /usr/local/bin/

VOLUME /var/lib/docker
EXPOSE 2375 22

ENTRYPOINT ["entrypoint.sh"]
CMD []
