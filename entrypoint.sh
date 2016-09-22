#!/bin/bash
set -e

if [ "$DOCKER_DAEMON_AUTOSTART" = '1' ]; then
  /usr/local/bin/dind docker daemon -H 0.0.0.0:2375 -H unix:///var/run/docker.sock $DOCKER_DAEMON_ARGS &> /var/log/docker.log &
fi

# If a cmd argument is defined in docker run <container> <cmd>
if [ -n "$1" ]; then

  exec "$@"

# Otherwise start the bamboo agent if set
elif [ "$BAMBOO_AUTOSTART" = '1' ]; then

  if [ -z "$BAMBOO_SERVER_URL" ]; then
    echo "No BAMBOO_SERVER_URL provided. Format ex.: http://bamboo.example.com/agentServer/. Exiting..."
    exit 1
  fi

  # Customize config
  if [ -n "$BAMBOO_NAME" ] && [ -n "$HOSTNAME" ]; then
    sed -i "s/<name><\/name>/<name>$BAMBOO_NAME ($HOSTNAME)<\/name>/g" $BAMBOO_CONFIG_FILE
    sed -i "s/<description><\/description>/<description>Bamboo Build Agent $BAMBOO_NAME, Docker Container $HOSTNAME<\/description>/g" $BAMBOO_CONFIG_FILE
  else
    rm $BAMBOO_CONFIG_FILE
  fi

  # SSH
  if [ -d '/mnt/ssh/' ]; then
    # Copy files - We should not fiddle with files eventually mounted in
    mkdir -p '/root/.ssh'
    cp -rf '/mnt/ssh/*' '/root/.ssh/'
  fi
  if [ -d '/root/.ssh/' ]; then
    # Fix possibly incorrect permissions
    chown -R root:root '/root/.ssh/'
    chmod 755 '/root/.ssh/'
    chmod 644 '/root/.ssh/id_rsa.pub' || /bin/true
    chmod 600 '/root/.ssh/id_rsa'     || /bin/true

    # Capability 'ssh.bamboo'?
    grep 'SHA256:odzbpWP/ro7DyfomL5s+/YjQDvvJfaEh+gEnb701ZTI' <( ssh-keygen -lf '/root/.ssh/id_rsa.pub' ) > /dev/null 2>&1
    if [ "$?" == "0" ]; then
      # Check keypair
      diff <( ssh-keygen -y -e -f '/root/.ssh/id_rsa' ) <( ssh-keygen -y -e -f '/root/.ssh/id_rsa.pub' ) > /dev/null 2>&1
      if [ "$?" == "0" ]; then
        BAMBOO_CAPABILITIES="$BAMBOO_CAPABILITIES;ssh.bamboo=true"
      fi
    fi
  fi

  # Add addional capabilties if env var is set
  if [ -n "$BAMBOO_CAPABILITIES" ]; then
    OIFS=$IFS
    IFS=';'
    for i in $BAMBOO_CAPABILITIES; do
      echo $i >> $BAMBOO_CAPABILITIES_FILE
    done
    IFS=$OIFS
  fi

  # Remove possible blank lines
  sed -i '/^\s*$/d' $BAMBOO_CAPABILITIES_FILE

  if [ -z "$BAMBOO_AGENT_INSTALLER_URL" ]; then
    echo "No BAMBOO_AGENT_INSTALLER_URL provided. Format ex.: http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-latest.jar. Exiting..."
    exit 1
  fi

  echo "Downloading bamboo agent"
  curl -L $BAMBOO_AGENT_INSTALLER_URL > $BAMBOO_AGENT_INSTALLER

  BAMBOO_AGENT_ARGS="$BAMBOO_SERVER_URL"

  if [ -n "$BAMBOO_TOKEN" ]; then
    BAMBOO_AGENT_ARGS="$BAMBOO_AGENT_ARGS -t $BAMBOO_TOKEN"
  fi

  # Installs and runs the bamboo agent, if he dies he automatically restarts
  exec /usr/bin/java -Dbamboo.home=$BAMBOO_AGENT_HOME -jar $BAMBOO_AGENT_INSTALLER $BAMBOO_AGENT_ARGS
fi
