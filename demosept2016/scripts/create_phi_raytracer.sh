#!/bin/bash

CLDIR="/var/lib/cloudlightning"
MARATHON_ENDPOINT="http://a4c-demo2016.cloudlightning.ieat.ro:8282/v2/apps"
sudo mkdir "${CLDIR}"
#cd "${CLDIR}"

JOBID="engine$(hostname | tr -C -d '[:alnum:]')"
MARATHON_JOB_ID="/cloudlightning/gw/${JOBID}"

echo "export MARATHON_JOB_ID=\"${MARATHON_JOB_ID}\"" >> /tmp/execution_state.sh
echo "export MARATHON_ENDPOINT=\"${MARATHON_ENDPOINT}\"" >> /tmp/execution_state.sh

cat >/tmp/embree_rendering_no_nfs.json <<EOF
{
  "id": "${MARATHON_JOB_ID}",
  "cpus": 0.1,
  "mem": 512,
  "constraints": [
    [
      "mic",
      "CLUSTER",
      "available"
    ]
  ],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "pkudaiyar/mic_app_embree:1",
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
          "value": "embree_renderer.weave.local"
        }
      ]
     },
  "volumes": [
      {
        "containerPath": "/sys/class/mic/mic0",
        "hostPath": "/sys/class/mic/mic0",
        "mode": "RO"
      }
   ]
  },
  "labels": {
    "name": "embree_cpu_mic_instance"
  }
}
EOF




curl -X POST "${MARATHON_ENDPOINT}" -d @/tmp/embree_rendering_no_nfs.json -H "Content-type: application/json" > /tmp/marathon_response.json 2> /tmp/curl_marathon.log


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


exit 0
