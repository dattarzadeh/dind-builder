#!/bin/bash
set -e

# Install/start the bamboo agent?
if [ "$BAMBOO_AUTOSTART" = '1' ]; then
  if [ -z "$BAMBOO_SERVER_URL" ]; then
    echo "No BAMBOO_SERVER_URL provided. Format ex.: http://bamboo.example.com. Exiting..."
    false
  fi

  # Customize config
  sed -i "s#<buildWorkingDirectory></buildWorkingDirectory>#<buildWorkingDirectory>$BAMBOO_AGENT_HOME/xml-data/build-dir</buildWorkingDirectory>#g" $BAMBOO_CONFIG_FILE
  if [ -n "$BAMBOO_NAME" ]; then
    sed -i "s#<name></name>#<name>$BAMBOO_NAME ($HOSTNAME)</name>#g" $BAMBOO_CONFIG_FILE
    sed -i "s#<description></description>#<description>Bamboo Build Agent $BAMBOO_NAME in Docker Container $HOSTNAME</description>#g" $BAMBOO_CONFIG_FILE
  else
    sed -i "s#<name></name>#<name>DIND ($HOSTNAME)</name>#g" $BAMBOO_CONFIG_FILE
    sed -i "s#<description></description>#<description>Anonymous Bamboo Build Agent in Docker Container $HOSTNAME (BAMBOO_NAME not set)</description>#g" $BAMBOO_CONFIG_FILE
  fi

  # SSH
  if [ -d '/mnt/ssh/' ]; then
    set +e

    # Copy files - We should not fiddle with files eventually mounted in
    mkdir -p '/root/.ssh'
    cp -rf /mnt/ssh/* '/root/.ssh/'

    # Fix possibly incorrect permissions
    chown -R root:root '/root/.ssh/'
    chmod 755 '/root/.ssh/'
    chmod 644 '/root/.ssh/id_rsa.pub'
    chmod 600 '/root/.ssh/id_rsa'

    # Capability 'ssh.bamboo'? Older versions return fingerprint as hex
    grep -e 'SHA256:odzbpWP/ro7DyfomL5s+/YjQDvvJfaEh+gEnb701ZTI' -e '3a:74:d7:6c:da:64:cd:4c:21:74:a3:26:1b:f7:18:4b' <( ssh-keygen -lf '/root/.ssh/id_rsa.pub' ) > /dev/null 2>&1
    if [ "$?" == "0" ]; then
      # Check keypair
      diff <( ssh-keygen -y -e -f '/root/.ssh/id_rsa' ) <( ssh-keygen -y -e -f '/root/.ssh/id_rsa.pub' ) > /dev/null 2>&1
      if [ "$?" == "0" ]; then
        BAMBOO_CAPABILITIES="$BAMBOO_CAPABILITIES;ssh.bamboo=true"
      fi
    fi

    set -e
  fi

  # Agent Capabilities
  OIFS=$IFS
  IFS=';'
  for i in $BAMBOO_CAPABILITIES; do
    echo $i >> $BAMBOO_CAPABILITIES_FILE
  done
  IFS=$OIFS
  # Remove possible blank or duplicate lines
  sed -i '/^\s*$/d' $BAMBOO_CAPABILITIES_FILE
  sort -u $BAMBOO_CAPABILITIES_FILE

  if [ -z "$BAMBOO_AGENT_INSTALLER_URL" ]; then
    echo "No BAMBOO_AGENT_INSTALLER_URL provided. Format ex.: http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-latest.jar. Exiting..."
    false
  fi

  echo "Downloading bamboo agent"
  curl -L $BAMBOO_AGENT_INSTALLER_URL > $BAMBOO_AGENT_INSTALLER

  # Start agent cleanup service?
  rm -f /etc/service/bamboo_cleanup
  if [ -n "$BAMBOO_API_TOKEN" ]; then
    ln -s /etc/sv/bamboo_cleanup /etc/service/bamboo_cleanup
  else
    echo "No BAMBOO_API_TOKEN provided. Required for disk space housekeeping!"
    false
  fi

  # Start agent service
  rm -f /etc/service/bamboo_agent
  ln -s /etc/sv/bamboo_agent /etc/service/bamboo_agent
fi