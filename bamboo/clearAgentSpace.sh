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

# Make temp directory
TMPFILE=`mktemp -d /tmp/clearAgentSpace.XXXXXX` || exit 1
find ${TMPFILE} -type d -exec chmod 0755 {} \;

# To extract property value from JSON response
# https://gist.github.com/cjus/1047794
function jsonValue() {
	KEY=$1
	num=$2
	awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

#check for required libraries/tools and setup tempdir
command -v curl >/dev/null 2>&1 || { echo "$(date): Required tool 'curl' not found" | tee -a $TMPFILE/log.txt ;exit 2; }

# Run endlessly
while [ true ]; do
	#Check if the file exist
	if [ -e "${agentLocation}/bamboo-agent.cfg.xml" ]; then
		agentId=`cat ${agentLocation}/bamboo-agent.cfg.xml | grep -oPm1 "(?<=<id>)[^<]+"`
		buildWorkingDir=`cat ${agentLocation}/bamboo-agent.cfg.xml | grep -oPm1 "(?<=<buildWorkingDirectory>)[^<]+"`

		# Already clean?
		if [ -e "$buildWorkingDir" ]; then
			# Check if both variables are not null
			if [ -z ${agentId} ] || [ -z ${buildWorkingDir} ] || [ -z ${uuid} ]; then
				echo "$(date): agentId or buildWorkingDir or uuid not found" | tee -a $TMPFILE/log.txt
			else
				echo "$(date): Agent ID ${agentId}" | tee -a $TMPFILE/log.txt
				echo "$(date): Artifacts location ${buildWorkingDir}" | tee -a $TMPFILE/log.txt
				echo "$(date): Token ${uuid}" | tee -a $TMPFILE/log.txt
				echo "$(date): Running Disk Purge for Agent $agentId" | tee -a $TMPFILE/log.txt

				# disable agent
				echo "" | tee -a $TMPFILE/log.txt
				echo "$(date) Disabling the agent and checking status" | tee -a $TMPFILE/log.txt
				curl -s -k -c $TMPFILE/cookies "$bambooUrl" 2>&1 | tee -a $TMPFILE/log.txt
				curl -s -X POST -k -b $TMPFILE/cookies -H "Content-Type: application/json" "$bambooUrl/rest/agents/1.0/$agentId/state/disable?uuid=${uuid}" 2>&1 | tee -a $TMPFILE/log.txt

				# Once the agent is disabled wait for about 2 minutes. Observed a latency between the agent starting to perform a job and the bamboo server
				# realizing the agent is busy
				echo "$(date): Sleeping for 120 seconds to give a chance for the bamboo server to get updated info. Messaging delay benifit of doubt" | tee -a $TMPFILE/log.txt
				sleep 120

				# Check current agent status
				echo "$(date): Proceeding with monitoring the status until agent is idle" | tee -a $TMPFILE/log.txt
				curl -s -k -b $TMPFILE/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPFILE/state.txt 2>&1 | tee -a $TMPFILE/log.txt
				agentStatus=`cat $TMPFILE/state.txt | jsonValue enabled` 
				busy=`cat $TMPFILE/state.txt | jsonValue busy` 
				echo "$(date): Is the agent busy? $busy" | tee -a $TMPFILE/log.txt
				echo "$(date): Is the agent enabled? $agentStatus" | tee -a $TMPFILE/log.txt
				if [ "$busy" == "true" ]; then
					echo "$(date): Agent is still running a job, waiting ..\n" | tee -a $TMPFILE/log.txt
					# while polling, and is still running, sleep
					running=1
					while [ $running -eq 1 ]; do
						sleep 10
						curl -s -k -b $TMPFILE/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPFILE/state.txt 2>&1 | tee -a $TMPFILE/log.txt
						busy=`cat $TMPFILE/state.txt | jsonValue busy`
						echo "$(date): Is the agent busy? $busy" | tee -a $TMPFILE/log.txt
						if [ "$busy" == "false" ]; then
							echo "$(date): Yay, it's idle now!\n" | tee -a $TMPFILE/log.txt
							break
						else
							echo "$(date): still busy..\n" | tee -a $TMPFILE/log.txt
						fi
					done
				fi

				echo "$(date): Agent is disabled and idle, starting cleanup" | tee -a $TMPFILE/log.txt

				echo "* Workdir ${buildWorkingDir}" | tee -a $TMPFILE/log.txt
				rm -rf ${buildWorkingDir} | tee -a $TMPFILE/log.txt

				echo "* Docker volumes, containers, images" | tee -a $TMPFILE/log.txt
				docker kill $(docker ps -q) | tee -a $TMPFILE/log.txt
				docker volume rm $(docker volume ls -q) | tee -a $TMPFILE/log.txt
				docker rm -f -v $(docker ps -a) | tee -a $TMPFILE/log.txt
				docker rmi -f $(docker images -q) | tee -a $TMPFILE/log.txt

				echo "$(date): Disk clear activities complete." | tee -a $TMPFILE/log.txt
				echo "$(date): Disk Info\n" | tee -a $TMPFILE/log.txt
				df -h | sed -e 's/^/\'$'\t/g' | tee -a $TMPFILE/log.txt

				# Re-enable agent after the clearn
				echo "" | tee -a $TMPFILE/log.txt
				echo "$(date): re-enabling the agent" | tee -a $TMPFILE/log.txt
				curl -s -X POST -k -b $TMPFILE/cookies -H "Content-Type: application/json" "$bambooUrl/rest/agents/1.0/$agentId/state/enable?uuid=${uuid}" 2>&1 | tee -a $TMPFILE/log.txt

				# Check current agent status
				curl -s -k -b $TMPFILE/cookies "$bambooUrl/rest/agents/1.0/$agentId/state?uuid=${uuid}" -o $TMPFILE/state.txt 2>&1 | tee -a $TMPFILE/log.txt
				agentStatus=`cat $TMPFILE/state.txt | jsonValue enabled` 
				busy=`cat $TMPFILE/state.txt | jsonValue busy` 
				echo "$(date): Is the agent enabled? $agentStatus" | tee -a $TMPFILE/log.txt
				echo "" | tee -a $TMPFILE/log.txt
				echo "$(date): Complete" | tee -a $TMPFILE/log.txt

			fi
		else
			echo "$(date): Sleeping 1hr ..." | tee -a $TMPFILE/log.txt
			sleep 3600
		fi
	else
		echo "$(date): Agent configuration information not found at ${agentLocation}/bamboo-agent.cfg.xml" | tee -a $TMPFILE/log.txt 
	fi
done