#!/bin/bash
sudo curl -fsSL https://testingcf.jsdelivr.net/gh/Joshua-DinG/Docker-Install@main/accelerate/linux.sh | bash -s docker --mirror Aliyun
sudo ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
docker --version
docker-compose --version
