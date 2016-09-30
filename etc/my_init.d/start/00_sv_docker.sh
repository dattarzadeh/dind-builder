#!/bin/bash

# Start the docker service?
rm -f /etc/service/docker
if [ "$DOCKER_DAEMON_AUTOSTART" = '1' ]; then
  ln -s /etc/sv/docker /etc/service/docker
fi