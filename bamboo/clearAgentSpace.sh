#!/bin/bash
#
# PreReq : Install bamboo agent API plugin - https://marketplace.atlassian.com/plugins/com.edwardawebb.bamboo-agent-apis
#https://marketplace.atlassian.com/plugins/com.edwardawebb.bamboo-agent-apis
#https://eddiewebb.atlassian.net/wiki/display/AAFB/Access+Token+Operations
#https://bitbucket.org/eddiewebb/bamboo-agent-apis
# API Version tested on 2.0

agentLocation="${BAMBOO_AGENT_HOME}"
bambooUrl="${BAMBOO_SERVER_URL}"
uuid="${BAMBOO_API_TOKEN}"

# To extract property value from JSON response
# https://gist.github.com/cjus/1047794
function jsonValue() {
	KEY=$1
	num=$2
	awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

#check for required libraries/tools
command -v curl >/dev/null 2>&1 || { echo "$(date): Required tool 'curl' not found"; exit 2; }

# Run endlessly
while [ true ]; do
	#Check if the file exist
	if [ -e "${agentLocation}/bamboo-agent.cfg.xml" ]; then
		agentId=`cat ${agentLocation}/bamboo-agent.cfg.xml | grep -oPm1 "(?<=<id>)[^<]+"`
		buildWorkingDir=`cat ${agentLocation}/bamboo-agent.cfg.xml | grep -oPm1 "(?<=<buildWorkingDirectory>)[^<]+"`
		agentStatusPrevious="unknown"

		# Cleanup needed when builddir not empty
		find ${buildWorkingDir} -maxdepth 0 -type d -empty > /dev/null 2>&1
		if [ "$?" == "0" ]; then
			echo "$(date): -= Bamboo Agent Cleanup =-"

			# Check if both variables are not null
			if [ -z ${agentId} ] || [ -z ${buildWorkingDir} ] || [ -z ${uuid} ]; then
				echo "$(date): agentId or buildWorkingDir or uuid not found"
			else
				echo "$(date): Agent ID ${agentId}"
				echo "$(date): BuildDir ${buildWorkingDir}"
				echo "$(date): API Token ${uuid}"

				# Make temp directory
				TMPDIR=`mktemp -d /tmp/clearAgentSpace.XXXXXX` || { echo "$(date): Failed creating TMPDIR"; continue; }
				find ${TMPDIR} -type d -exec chmod 0755 {} \;
				echo "$(date): TMPDIR '${TMPDIR}'"

				# Check current agent status
				curl -s -c $TMPDIR/cookies "$bambooUrl" > /dev/null || { echo "$(date): Failed creating Cookie"; continue; }
				curl -s -b $TMPDIR/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPDIR/state.txt > /dev/nul || { echo "$(date): Failed getting Agent status"; continue; }
				agentStatusEnabledPrevious=`cat $TMPDIR/state.txt | jsonValue enabled`

				# Disable Agent?
				if [ "$agentStatusEnabledPrevious" == "true" ]; then
					echo "$(date): Disabling the agent and checking status"
					while [ true ]; do
						curl -s -X POST -b $TMPDIR/cookies -H "Content-Type: application/json" "$bambooUrl/rest/agents/1.0/$agentId/state/disable?uuid=${uuid}" > /dev/nul || { echo "$(date): Failed disabling Agent"; continue; }
						curl -s -b $TMPDIR/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPDIR/state.txt > /dev/nul
						agentStatus=`cat $TMPDIR/state.txt | jsonValue enabled`
						if [ "$agentStatus" == "false" ]; then
							break
						fi
						sleep 10
					done
				else
					echo "$(date): Agent already disabled"
				fi

				# Wait until Agent is idle
				echo "$(date): Waiting for Agent to become idle (>= 120 sec) ..."
				# Countermeasure: Sleeping at least 120 secs to make sure Bamboo has current busy status when Agent just fetched a new job
				sleep 120
				while [ true ]; do
					curl -s -b $TMPDIR/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPDIR/state.txt > /dev/nul || { echo "$(date): Failed getting Agent status"; continue; }
					busy=`cat $TMPDIR/state.txt | jsonValue busy`
					if [ "$busy" == "false" ]; then
						break
					fi
					sleep 10
				done

				# CLEANUP
				echo "$(date): Agent is disabled and idle, starting cleanup"

				echo "$(date): * Workdir ${buildWorkingDir}"
				rm -rf ${buildWorkingDir}/*

				sv status docker | grep -P '^run: docker' > /dev/null 2>&1
				if [ "$?" == "0" ]; then
					echo "$(date): * Docker containers, images, volumes"
					# Fuck the system!
					# There seems to be a Docker bug that causes layers not being deleted properly
					# https://github.com/docker/docker/issues/6354
					# Therefore, don't use docker to cleanup itself but kill its storage
					#docker ps -a -q | xargs -r docker rm -f -v
					#docker images -q | xargs -r docker rmi -f
					#docker volume ls -q | xargs -r docker volume rm
					#docker volume ls -q -f dangling=true | xargs -r docker volume rm
					sv stop docker
					rm -rf /var/lib/docker/*
					sv start docker
				fi

				echo "$(date): Disk clear activities complete"

				# Re-enable agent?
				if [ "${agentStatusEnabledPrevious}" == "true" ]; then
					echo "$(date): Re-enabling the agent"
					while [ true ]; do
						curl -s -X POST -b $TMPDIR/cookies -H "Content-Type: application/json" "$bambooUrl/rest/agents/1.0/$agentId/state/enable?uuid=${uuid}" > /dev/nul || { echo "$(date): Failed enabling Agent"; continue; }
						curl -s -b $TMPDIR/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPDIR/state.txt > /dev/nul
						agentStatus=`cat $TMPDIR/state.txt | jsonValue enabled`
						if [ "$agentStatus" == "true" ]; then
							break
						fi
						sleep 10
					done
				fi

				rm -rf $TMPDIR
				echo "$(date): FINISHED!"
			fi
		fi
	else
		echo "$(date): Agent configuration information not (yet) found at ${agentLocation}/bamboo-agent.cfg.xml"
	fi
	sleep 1
done