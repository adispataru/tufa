#!/bin/bash
apt-get update --fix-missing

apt-get install -y git wget build-essential openssl libssl-dev pkg-config python python-dev python-pip ruby rake ruby-dev mongodb libkrb5-dev ImageMagick mencoder curl

curl -sL https://deb.nodesource.com/setup_4.x | bash -

apt-get install -y nodejs

mkdir -p /data/db

pip install pip --upgrade
pip install pika pyyaml requests mock pbr ez_setup jpype1 pymongo paramiko scp pillow

gem install bson_ext -v 1.9.2
gem install genghisapp

npm install -g npm

pip install jsonpickle


rm -rf /root/webpy
rm -rf /src

git clone https://github.com/webpy/webpy.git /root/webpy
rm /root/webpy/web/wsgi.py

cd /root/webpy
#now clone project from bitbucket to  /webapp foler
mkdir -p /webapp

rm -rf /webapp/*

# update username and password
wget --user='user' --password='password' -O rtwebproject.zip https://bitbucket.org/cloudlightning/t2.2_raytracing_integrated_usecase/get/54fa0f6fc6e6.zip

unzip rtwebproject.zip -d  /webapp

mv /webapp/cloudlightning-t2.2_raytracing_integrated_usecase-54fa0f6fc6e6/ray_tracing_web_app/wsgi.py /root/webpy/web/

 
pip install .

apt-get install -y supervisor

mv /webapp/cloudlightning-t2.2_raytracing_integrated_usecase-54fa0f6fc6e6/ray_tracing_web_app/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

mv /webapp/cloudlightning-t2.2_raytracing_integrated_usecase-54fa0f6fc6e6/ray_tracing_web_app/ /src/

echo "#12/08/2016 2.46pm" >> /src/docker-build.log

ln -sf /usr/bin/npm /usr/local/bin/npm

rm -rf rtwebproject.zip

cd /src/src

npm install .

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &