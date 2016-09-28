dind-builder
============
![Yo dawg, I herd you like Docker, so I put an Docker in your Docker so you can Docker while you Docker](https://i.chzbgr.com/full/8756567296/h9E60BDB6/)

This docker container is intended to be used together with either the
[Jenkins Docker Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Docker+Plugin) or an [Bamboo Build Server](https://de.atlassian.com/software/bamboo).

Software Content
-----
* Ubuntu 16.04
* Docker 1.11.1
* Docker Compose 1.7.1
* Docker Build Helper 1.0
* OpenSSH Server
* OpenJDK 8
* Additional build/package requirements are defined in install/buildenv-*

Features
-----
* Jenkins Slave
* Bamboo Agent
* Docker in Docker
  * Build helper: [Docker Build Helper](install/docker-build.pl).
   * Creates a metadata file after docker build which contains all the build information
   * Can build a single docker image or multiple images via compose
   * Export docker image to disk
   * Import docker image from disk
   * Pushes containers to public/private registries
  * Clean image store before build


  A build environment pre contained with all build dependencies, completely separated from the underlying host system/libs. The build environment can be recycled after each build with nearly zero provision time. Containers can be rate limited regarding IO, CPU, MEMORY to prioritize certain build jobs over others, to give every build job a fair amount of resources on the same build node and are fully configurable from the outside via the DOCKER API.

  We use docker extensively and have fully automated build jobs for all our docker images. The base image referencing in the Dockerfile with the ```FROM ocedo/foo:latest``` line is not sufficient enough for us to build images which are predictable and reproducible. When image BAR requires FOO, we build FOO first and store the build image as an artifact in our artifact store. The build job BAR then loads that artifact and replaces the ```FROM``` line with the image ID from the FOO artifact. With docker in docker we can be sure that the image store does not contain any pre-build images. Actually we should never see a ```docker pull``` happening in our build jobs. Most of the functionality described here is implemented in our build helper.

Jenkins Build Slave
-----
* Check that the required module, as stated above is installed
* Add a new credential in Jenkins with Username: jenkins and Password: jenkins
* Configure a new docker cloud in your Jenkins settings (Manage Jenkins->Configure System)
 * Give it a name and a valid docker URL like http://my.docker.host:2375
 * Test the connection
 * Add this image from the public registry to that cloud with the ID: m1no/dind-builder
 * Give that image a valid build label (ex.:"docker") to point your build jobs to it
 * Select the newly created credential from before to allow the Jenkins Master to connect
   via ssh to the new Docker Jenkins slave
 * Click the "Advanced..." button for that image
 * Enable "Run container privileged" mode
* Create a new build job and set the option "Restrict where this project can be run" to
  the new build label (ex.:"docker")
* Do your build steps as usual

After running a build you should see that Jenkins start a new docker container
every time you trigger this job to build. Shortly after triggering the build, there will
be a notice that the job is pending on the build instance, this is totally normal. After
the brand new slave is fully operational this should go over in to "Building".

Bamboo Agent
-----
Example command to run a volatile Bamboo Agent with token based authentication.
```
docker run --privileged --rm -ti -e BAMBOO_AUTOSTART=1 -e BAMBOO_AGENT_INSTALLER_URL=http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-latest.jar -e BAMBOO_TOKEN=403a5fd4v89b6b33ff46805a6529e9016e015612 -e BAMBOO_API_TOKEN=e87342d4-8547-11e6-92d0-74d435e4f811 -e BAMBOO_SERVER_URL=http://bamboo.example.com m1no/dind-builder
```

Known Issues
-----
* The token based authentication does not seem to work, you still need manual approval on the Bamboo server site. A support ticket at Atlassian was already opened for that. No response yet.

Environment Variables
-----
| ENV VARIABLE | FUNCTION |
| ------------ | -------- |
| ```DOCKER_DAEMON_AUTOSTART``` | Default: ```1```. If set to 1 the docker daemon is starting inside the docker container. |
| ```BAMBOO_AUTOSTART``` | Default: ```0```. This should be set to 1 if you want to run this container as a BAMBOO build agent. This requires the environment variables ```BAMBOO_SERVER_URL``` and ```BAMBOO_AGENT_INSTALLER_URL``` to be set. |
| ```BAMBOO_SERVER_URL``` | Default:```""```. This variable determines the BAMBOO server url. <br><br>Format example: ```http://bamboo.example.com/``` |
| ```BAMBOO_AGENT_INSTALLER_URL``` | Default:```""```. This variable determines the BAMBOO download url for the agent. <br>Your URL is available under: <br> Bamboo Administration > Agents > Install Remote Agent <br> behind the download button.  <br><br>Format example: ```http://bamboo.example.com/agentServer/agentInstaller/atlassian-bamboo-agent-installer-latest.jar``` |
| ```BAMBOO_TOKEN``` | Default:```""```. This is only needed if you have token based authentication for your agents activated. <br>Your token is available under: <br>Bamboo Administration > Agents > Install Remote Agent<br> when you have tokens enabled. <br><br>Format example: ```403a5fd4v89b6b33ff46805a6529e9016e015612``` |
| ```BAMBOO_API_TOKEN``` | Default:```""```. This is needed for automatic cleanup. <br>Your token is available under: <br>Bamboo Administration > Agent APIs Admin > Agent API Tokens<br><br>Format example: ```e87342d4-8547-11e6-92d0-74d435e4f811``` |
| ```BAMBOO_CAPABILITIES``` | Default:```""```. If you need to add additional BAMBOO capabilities to the agent. Capabilities can be seperated by the <b>;</b>-Delimiter. There are already predefined ones in [bamboo/bamboo-capabilities.properties](bamboo/bamboo-capabilities.properties) <br><br>Format example: ```IOPS=High\nsystem.builder.command.echo=/bin/echo``` |
