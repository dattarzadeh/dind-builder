#!/bin/bash
set -e

# Install/start the bamboo agent?
if [ "$BAMBOO_AUTOSTART" = '1' ]; then
  if [ -z "$BAMBOO_SERVER_URL" ]; then
    echo "No BAMBOO_SERVER_URL provided. Format ex.: http://bamboo.example.com. Exiting..."
    false
  fi

  if [ -z "$BAMBOO_AGENT_INSTALLER_URL" ]; then
    echo "No BAMBOO_AGENT_INSTALLER_URL provided. Format ex.: http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-latest.jar. Exiting..."
    false
  fi

  echo "Downloading bamboo agent"
  curl -L $BAMBOO_AGENT_INSTALLER_URL > $BAMBOO_AGENT_INSTALLER

  echo "Installing bamboo agent"
  BAMBOO_AGENT_ARGS="$BAMBOO_SERVER_URL/agentServer/"
  if [ -n "$BAMBOO_TOKEN" ]; then
    BAMBOO_AGENT_ARGS="$BAMBOO_AGENT_ARGS -t $BAMBOO_TOKEN"
  fi
  /usr/bin/java -Dbamboo.home=$BAMBOO_AGENT_HOME -jar $BAMBOO_AGENT_INSTALLER $BAMBOO_AGENT_ARGS install

  echo "Customizing bamboo agent wrapper config"
  sed -i "s#wrapper.java.initmemory=256#wrapper.java.initmemory=512#g" "$BAMBOO_AGENT_HOME/conf/wrapper.conf"
  sed -i "s#wrapper.java.maxmemory=512#wrapper.java.maxmemory=1024#g" "$BAMBOO_AGENT_HOME/conf/wrapper.conf"

  echo "Customizing bamboo agent config"
  # Get our container scale num from parent Docker
  SCALE=`DOCKER_HOST="unix:///var/run/docker_parent.sock" docker inspect $(hostname) 2> /dev/null | perl -ne '/bamboo_(\d+)/ && print $1 ? $1 : 1'`

  # New config from template?
  if [ ! -e $BAMBOO_CONFIG_FILE ]; then
    cp "$BAMBOO_CONFIG_FILE.tpl" "$BAMBOO_CONFIG_FILE"

    # Default Agent name
    sed -i "s#<name>.*</name>#<name>DIND ($HOSTNAME)</name>#g" $BAMBOO_CONFIG_FILE
    sed -i "s#<description>.*</description>#<description>Anonymous Bamboo Build Agent in Docker Container $HOSTNAME (BAMBOO_NAME not set)</description>#g" $BAMBOO_CONFIG_FILE
  fi

  # Store config on host?
  if [ -d '/mnt/cfg/' ]; then
    if [ ! -e "/mnt/cfg/bamboo-agent-$SCALE.cfg.xml" ]; then
      cp "$BAMBOO_CONFIG_FILE" "/mnt/cfg/bamboo-agent-$SCALE.cfg.xml"
    fi
    ln -f -s "/mnt/cfg/bamboo-agent-$SCALE.cfg.xml" "$BAMBOO_CONFIG_FILE"
  fi

  # Override Agent name?
  if [ -n "$BAMBOO_NAME" ]; then
    sed -i --follow-symlinks "s#<name>.*</name>#<name>$BAMBOO_NAME - \#$SCALE</name>#g" $BAMBOO_CONFIG_FILE
    sed -i --follow-symlinks "s#<description>.*</description>#<description>Bamboo Build Agent $BAMBOO_NAME in Docker Container $SCALE</description>#g" $BAMBOO_CONFIG_FILE
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

  # Local cache
  if [ -d '/mnt/cache/' ]; then
    echo "Populating local cache ..."
    set +e

    # Copy files - We should not fiddle with files eventually mounted in
    mkdir -p '/opt/cache/'
    cp -rf /mnt/cache/* '/opt/cache/'

    # Fix possibly incorrect permissions
    chown -R root:root '/opt/cache/'
    find /opt/cache/ -type d -print0 | xargs -0 chmod 755
    find /opt/cache/ -type f -print0 | xargs -0 chmod 644

    set -e
  fi

  # Agent Capabilities
  echo "Configuring bamboo agent capabilities"
  OIFS=$IFS
  IFS=';'
  for i in $BAMBOO_CAPABILITIES; do
    echo $i >> $BAMBOO_CAPABILITIES_FILE
  done
  IFS=$OIFS
  # Remove possible blank or duplicate lines
  sed -i '/^\s*$/d' $BAMBOO_CAPABILITIES_FILE
  sort -u $BAMBOO_CAPABILITIES_FILE

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