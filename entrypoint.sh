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

  # Add addional capabilties if env var is set
  if [ -n "$BAMBOO_CAPABILITIES" ]; then
    OIFS=$IFS
    IFS=';'
    for i in $BAMBOO_CAPABILITIES; do
      echo $i >> $BAMBOO_AGENT_HOME/$BAMBOO_CAPABILITIES_FILE
    done
    IFS=$OIFS
  fi

  if [ -z "$BAMBOO_AGENT_INSTALLER_URL" ]; then
    echo "No BAMBOO_AGENT_INSTALLER_URL provided. Format ex.: http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-5.10.1.1.jar. Exiting..."
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
