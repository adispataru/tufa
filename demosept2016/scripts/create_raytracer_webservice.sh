#!/bin/bash

CLDIR="/var/lib/cloudlightning"
MARATHON_ENDPOINT="http://10.0.0.186:8080/v2/apps"
sudo mkdir "${CLDIR}"
#cd "${CLDIR}"
export > /tmp/create_webservice.variables.sh

JOBID="web$(hostname | tr -C -d '[:alnum:]')"
MARATHON_JOB_ID="/cloudlightning/gw/${JOBID}"

echo "export MARATHON_JOB_ID=\"${MARATHON_JOB_ID}\"" >> /tmp/execution_state.sh
echo "export MARATHON_ENDPOINT=\"${MARATHON_ENDPOINT}\"" >> /tmp/execution_state.sh

echo "127.0.1.42 $(hostname)" | sudo tee -a /etc/hosts
echo "10.0.0.186 mesos.master.local" | sudo tee -a /etc/hosts
echo "10.0.0.187 mesos.slave1.local" | sudo tee -a /etc/hosts
echo "10.0.0.188 mesos.slave2.local" | sudo tee -a /etc/hosts
echo "10.0.0.189 mesos.slave3.local" | sudo tee -a /etc/hosts


cat >/tmp/ray_tracing_webservice_master.json <<EOF
{
  "id": "${MARATHON_JOB_ID}",
  "cpus": 0.1,
  "mem": 512,
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "mneagul/playground:44",
      "forcePullImage": true,
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 9393, "hostPort": 0 },
        { "containerPort": 3005, "hostPort": 0 }
      ],
      "parameters": [
        {
          "key": "hostname",
          "value": "raytracingwebservice.weave.local"
        }
      ]
     }
  },
  "labels": {
    "name": "ray_tracing_webservice_instance"
  }
}
EOF


sudo apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" jq
sudo apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" facter

curl -X POST "${MARATHON_ENDPOINT}" -d @/tmp/ray_tracing_webservice_master.json -H "Content-type: application/json" > /tmp/marathon_response.json 2> /tmp/curl_marathon.log


sudo wget -O /usr/local/bin/consul http://a4c-demo2016.cloudlightning.ieat.ro/consul 2>&1 > /tmp/wget_consul.log

sudo chmod +x /usr/local/bin/consul
sudo mkdir -p /var/lib/consul  /etc/consul.d/
echo '{"service": {"name": "raytracer-webservice", "tags": ["cloudlightning", "messos"], "port": 80}}' | sudo tee /etc/consul.d/raytracer.json


sudo tee /etc/init/consul.conf <<EOF
description "Consul agent"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

script
  exec /usr/local/bin/consul agent \
    -config-dir="/etc/consul.d" \
    -data-dir /var/lib/consul -bind 0.0.0.0 -retry-join=192.168.0.125 -encrypt=7908eb9b44364bee87bdeafcfef764c8 -dc=cloudlightning-ieat-1 \
    >>/var/log/consul.log 2>&1
end script
EOF

sudo /sbin/start consul 

sleep 60

retry=5

while [ $retry -gt 0 ]; do
    retry=$(($retry-1))
    STATUS_FILE="/tmp/status$$.temp.json"
    curl -X GET "${MARATHON_ENDPOINT}${MARATHON_JOB_ID}" > ${STATUS_FILE} 2>/dev/null
    MHOST=$(jq '.app.tasks[0].host' ${STATUS_FILE} | tr -d '"')
    MPORT1=$(jq '.app.tasks[0].ports[0]' ${STATUS_FILE} | tr -d '"')
    MPORT2=$(jq '.app.tasks[0].ports[1]' ${STATUS_FILE} | tr -d '"')
    MPORT3=$(jq '.app.tasks[0].ports[2]' ${STATUS_FILE} | tr -d '"')
    if [ "xnull" = "x${MHOST}" ]; then
        sleep 30
        unset MHOST
        continue
    else
        break
    fi

done

if [ -z $MHOST ]; then
    echo "No Info"
    exit 1
fi

MIP=$(ping -c 1 "${MHOST}" | head -1 | cut -d "(" -f 2 | cut -d ")" -f 1)

sudo sysctl net.ipv4.conf.all.forwarding=1
sudo iptables -t nat -F
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to ${MIP}:${MPORT1}
sudo iptables -t nat -A POSTROUTING -p tcp -d ${MIP} -j MASQUERADE


if [ "x${MPORT2}" = "xnull" ]; then
    echo "No secondary Service"
else
    sudo iptables -t nat -A PREROUTING -p tcp --dport 8081 -j DNAT --to ${MIP}:${MPORT2}
fi

if [ "x${MPORT3}" = "xnull" ]; then
    echo "No secondary Service"
else
    sudo iptables -t nat -A PREROUTING -p tcp --dport 8222 -j DNAT --to ${MIP}:${MPORT3}
fi


#####
# Connecting the endpoints
#####
APPID=$(echo ${PID_FILE} | sed 's|.*brooklyn-managed-processes/apps/||' | cut -d "/" -f 1)
if [ -z "${APPID}" ]; then
  APPID="cloudlightning-default"
fi
echo "export APPID=\"${APPID}\"" >> /tmp/execution_state.sh

RAYTRACER_PUBLIC=$(curl "http://localhost:8500/v1/kv/${APPID}/raytracer/publicIpAddress" 2>/dev/null | jq .[0].Value | tr -d '"' | base64 -d)
RAYTRACER_PUBLIC_PORT=$(curl "http://localhost:8500/v1/kv/${APPID}/raytracer/publicIpAddressPort" 2>/dev/null | jq .[0].Value | tr -d '"' | base64 -d)
RAYTRACER_PRIVATE_ADDRESS=$(curl "http://localhost:8500/v1/kv/${APPID}/raytracer/privateIpAddress" 2>/dev/null | jq .[0].Value | tr -d '"' | base64 -d)
RAYTRACER_PRIVATE_PORT=$(curl "http://localhost:8500/v1/kv/${APPID}/raytracer/privateIpAddressPort" 2>/dev/null | jq .[0].Value | tr -d '"' | base64 -d)


RAYTRACER=${RAYTRACER_PUBLIC// }
RAYTRACER_PORT=${RAYTRACER_PUBLIC_PORT// }
RAYTRACER_PRIVATE_ADDRESS=${RAYTRACER_PRIVATE_ADDRESS// }
RAYTRACER_PRIVATE_PORT=${RAYTRACER_PRIVATE_PORT// }

if [[ -z "${RAYTRACER}" ]]; then
  echo "No raytracer set!"
  exit 1
fi

echo "export RAYTRACER_ENDPOINT=\"${RAYTRACER}:${RAYTRACER_PORT}\"" >> /tmp/execution_state.sh
echo "export RAYTRACER_PRIVATE_ADDRESS=\"${RAYTRACER_PRIVATE_ADDRESS}:${RAYTRACER_PRIVATE_PORT}\"" >> /tmp/execution_state.sh

curl -H "Content-Type: application/json" \
  -X POST -d "{\"url\": \"${RAYTRACER}:${RAYTRACER_PORT}\"}" \
  ${MIP}:${MPORT1}

exit 0
