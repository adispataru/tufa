#!/bin/bash

CLDIR="/var/lib/cloudlightning"
MARATHON_ENDPOINT="http://10.0.0.186:8080/v2/apps"
sudo mkdir "${CLDIR}"


JOBID="engine$(hostname | tr -C -d '[:alnum:]')"
MARATHON_JOB_ID="/cloudlightning/gw/${JOBID}"

echo "export MARATHON_JOB_ID=\"${MARATHON_JOB_ID}\"" >> /tmp/execution_state.sh
echo "export MARATHON_ENDPOINT=\"${MARATHON_ENDPOINT}\"" >> /tmp/execution_state.sh

echo "127.0.1.42 $(hostname)" | sudo tee -a /etc/hosts
echo "10.0.0.186 mesos.master.local" | sudo tee -a /etc/hosts
echo "10.0.0.187 mesos.slave1.local" | sudo tee -a /etc/hosts
echo "10.0.0.188 mesos.slave2.local" | sudo tee -a /etc/hosts
echo "10.0.0.189 mesos.slave3.local" | sudo tee -a /etc/hosts

cat >/tmp/embree_rendering_no_nfs.json <<EOF
{
  "id": "${MARATHON_JOB_ID}",
  "cpus": 0.1,
  "mem": 512,
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "pkudaiyar/ray_tracing_engine_embree:1",
      "privileged": true,
      "network": "BRIDGE",
      "portMappings": [
        {
          "containerPort": 22,
          "hostPort": 0,
          "protocol": "tcp"
        }
      ],
      "parameters": [
        {
          "key": "hostname",
          "value": "embreerenderer.weave.local"
        }
      ]
     }
  }
}
EOF

sudo apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" facter
sudo apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" jq

curl -X POST "${MARATHON_ENDPOINT}" -d @/tmp/embree_rendering_no_nfs.json -H "Content-type: application/json" > /tmp/marathon_response.json 2> /tmp/curl_marathon.log

sleep 10
curl -X GET "${MARATHON_ENDPOINT}${MARATHON_JOB_ID}" > status_json


sudo wget -O /usr/local/bin/consul http://a4c-demo2016.cloudlightning.ieat.ro/consul 2>&1 > /tmp/wget_consul.log

sudo chmod +x /usr/local/bin/consul
sudo mkdir -p /var/lib/consul  /etc/consul.d/
echo '{"service": {"name": "raytracer", "tags": ["cloudlightning", "messos"], "port": 80}}' | sudo tee /etc/consul.d/raytracer.json


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

sleep 30

retry=5

while [ $retry -gt 0 ]; do
    retry=$(($retry-1))
    STATUS_FILE="/tmp/status$$.temp.json"
    curl -X GET "${MARATHON_ENDPOINT}${MARATHON_JOB_ID}" > ${STATUS_FILE} 2>/dev/null
    MHOST=$(jq '.app.tasks[0].host' ${STATUS_FILE} | tr -d '"')
    MPORT1=$(jq '.app.tasks[0].ports[0]' ${STATUS_FILE} | tr -d '"')
    MPORT2=$(jq '.app.tasks[0].ports[1]' ${STATUS_FILE} | tr -d '"')
    if [ "xnull" = "x${MHOST}" ]; then
        sleep 20
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
sudo iptables -t nat -A PREROUTING -p tcp --dport 8222 -j DNAT --to ${MIP}:${MPORT1}
sudo iptables -t nat -A POSTROUTING -p tcp -d ${MIP} -j MASQUERADE

PUBLIC_IP_ADDRESS=$(facter | grep ec2_public_ipv4 | cut -d ">" -f 2 | tr -d " ")

APPID=$(echo ${PID_FILE} | sed 's|.*brooklyn-managed-processes/apps/||' | cut -d "/" -f 1)
if [ -z "${APPID}" ]; then
  APPID="cloudlightning-default"
fi
echo "export APPID=\"${APPID}\"" >> /tmp/execution_state.sh

if [ ! -z "${PUBLIC_IP_ADDRESS}" ]; then
  curl -X PUT -d "${PUBLIC_IP_ADDRESS}" "http://localhost:8500/v1/kv/${APPID}/raytracer/publicIpAddress" 2>/dev/null
  curl -X PUT -d '8222' "http://localhost:8500/v1/kv/${APPID}/raytracer/publicIpAddressPort" 2>/dev/null
  curl -X PUT -d "${MIP}" "http://localhost:8500/v1/kv/${APPID}/raytracer/privateIpAddress" 2>/dev/null
  curl -X PUT -d "${MPORT1}" "http://localhost:8500/v1/kv/${APPID}/raytracer/privateIpAddressPort" 2>/dev/null
fi

exit 0
