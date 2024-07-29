#!/bin/bash

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Error: Unable to determine OS type."
    exit 1
fi

mkdir -p /etc/docker/

tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "registry-mirrors": [
        "https://docker.m.daocloud.io",
        "https://docker.1panel.live",
        "https://hub.rat.dev"
    ]
}
EOF

# 提示信息
echo "Docker 镜像加速器配置完成！"

# 根据操作系统类型执行对应的 Docker 服务重启命令
case "$OS" in
    debian|ubuntu)
        systemctl daemon-reload
        systemctl restart docker.service
        ;;
    alpine)
        rc-service docker restart
        ;;
    *)
        echo "Unsupported OS: $OS. Unable to restart Docker service."
        exit 1
        ;;
esac

echo "Docker 服务重启完成！"
