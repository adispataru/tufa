#!/bin/bash

. /tmp/execution_state.sh

curl -X DELETE "${MARATHON_ENDPOINT}${MARATHON_JOB_ID}" 

sudo /usr/local/bin/consul leave
sudo stop consul


