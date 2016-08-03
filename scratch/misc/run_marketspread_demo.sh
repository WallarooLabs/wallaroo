#!/bin/bash -e

echo -e "\033[0;31m"WARNING! This is a hacky script and not guaranteed to work. It is run with set -e and will exit on the first error encountered.'\033[0m'


if [ $# -ne 2 ]; then
  echo "Must supply two arguments:"
  echo "1: IP Address"
  echo "2: docker_tag"
  exit 1
fi

ip=${1}
tag=${2}

if [ `basename ${PWD}` != misc ]; then
  echo "Must run from misc directory"
  exit 1
fi

pem=~/.ssh/ec2/us-east-1.pem
docker_port=2378
docker_net_port=2375

if [ ${ip} == 10.0.1.200 ]; then
  pem=../../orchestration/vagrant/.vagrant/machines/buffy-leader-1/virtualbox/private_key
fi

scp -i ${pem} -o StrictHostKeyChecking=no docker-market-spread-aws-swarm.ini sendence@${ip}:/tmp
scp -i ${pem} -o StrictHostKeyChecking=no ../../demos/marketspread/trades.msg sendence@${ip}:/tmp
scp -i ${pem} -o StrictHostKeyChecking=no ../../demos/marketspread/nbbo.msg sendence@${ip}:/tmp

docker --host=tcp://${ip}:${docker_net_port} network create -d overlay buffy-swarm

docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/sendence/market-spread.amd64:${tag}
docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/sendence/giles-sender.amd64:${tag}
docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/sendence/giles-receiver.amd64:${tag}
docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/sendence/dagon.amd64:${tag}
docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/buffy-metrics-ui
docker --host=tcp://${ip}:${docker_port} pull docker.sendence.com:5043/market-spread-reports-ui


docker --host=tcp://${ip}:${docker_port} run -v /tmp:/apps/market_spread_reports_ui/log -d -p 0.0.0.0:4000:4000 -e "constraint:node==buffy-leader-1" --name mui -h mui --net=buffy-swarm docker.sendence.com:5043/buffy-metrics-ui

docker --host=tcp://${ip}:${docker_port} run -v /tmp:/apps/market_spread_reports_ui/log -d -p 0.0.0.0:4001:4001 -e "constraint:node==buffy-leader-1" --name aui -h aui --net=buffy-swarm docker.sendence.com:5043/market-spread-reports-ui

sleep 2

open http://${ip}:4000/#/applications/market-spread-app/dashboard
open http://${ip}:4001/#/reports/rejected-client-order-summaries-report

sleep 5

docker --host=tcp://${ip}:${docker_port} run -d -u 1111 --name metrics  -h metrics  --privileged -v /usr/bin:/usr/bin:ro  -v /var/run/docker.sock:/var/run/docker.sock  -v /bin:/bin:ro  -v /lib:/lib:ro  -v /lib64:/lib64:ro  -v /usr:/usr:ro  -v /tmp:/tmp  -w /tmp  --net=buffy-swarm docker.sendence.com:5043/sendence/market-spread.amd64:${tag} --run-sink -r -l metrics:9000 -m mui:5001 --name market-spread --period 1 -a market-spread-app

sleep 5

docker --host=tcp://${ip}:${docker_port} run -u 1111 --name dagon  -h dagon  --privileged  -i  -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 -e "constraint:node==buffy-leader-1" -v /usr/bin:/usr/bin:ro  -v /var/run/docker.sock:/var/run/docker.sock  -v /bin:/bin:ro  -v /lib:/lib:ro  -v /lib64:/lib64:ro  -v /usr:/usr:ro  -v /tmp:/tmp  -w /tmp  --net=buffy-swarm docker.sendence.com:5043/sendence/dagon.amd64:${tag} dagon.amd64  --docker=tcp://${ip}:${docker_port}  -t 30  --filepath=/tmp/docker-market-spread-aws-swarm.ini  --phone-home=dagon:8080 --tag=${tag}


