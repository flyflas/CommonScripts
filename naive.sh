#!/usr/bin/env bash

unset CADDY_CONFIG_DIR PORT DOMAIN EMAIL PASSWD USERNAME END_COLOR RED GREEN YELLOW BLUE

CADDY_CONFIG_DIR="/etc/caddy"
EMAIL_REG="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
DOMAIN_REG="^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$"

END_COLOR="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"

error() {
	echo -e "${RED}$*${END_COLOR}"
}

info() {
    echo -e "${GREEN}$*${END_COLOR}"
}

remind() {
    echo -e "${BLUE}$*${END_COLOR}"
}

warning() {
    echo -e "${YELLOW}$*${END_COLOR}"
}


get_info() {
    read -rp "请输入你的域名： " DOMAIN
    [[ ! ($DOMAIN =~ $DOMAIN_REG) ]] && error "请输入正确的域名!!!" && exit 1

    read -rp "请输入你的邮箱（用于申请SSL证书）: " EMAIL
    [[ ! ($EMAIL =~ $EMAIL_REG) ]] && error "请输入正确的邮箱!!!" && exit 1

    read -rp "请输入naive的密码： " PASSWD
    [[ -z $PASSWD ]] && error "密码为空!!!" && exit 1

    read -rp "请输入用户名：" USERNAME
    [[ -z $USERNAME ]] && error "用户名为空!!!" && exit 1

    read -rp "请输入端口（默认为443）: " PORT
    [[ -z $PORT ]] && PORT=443
}

install_go() {
    info "正在安装Go"

    wget https://go.dev/dl/go1.19.7.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.19.7.linux-amd64.tar.gz && \
    echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile.d/go.sh && \
    source /etc/profile.d/go.sh
    
    info "Go安装完毕"
}

install_naive() {
    info "正在安装 naive, 请稍后......"
    # 安装navie
    go get -u github.com/caddyserver/xcaddy/cmd/xcaddy && \
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
    setcap cap_net_bind_service=+ep ./caddy

    info "正在设置 naive 配置文件......"

    # 设置 Caddy 配置文件
    [[ ! -d ${CADDY_CONFIG_DIR} ]] && mkdir -p $CADDY_CONFIG_DIR
    [[ -e ${CADDY_CONFIG_DIR}/Caddyfile ]] && rm -rf ${CADDY_CONFIG_DIR}/Caddyfile && \
    cat >> ${CADDY_CONFIG_DIR}/Caddyfile << EOF
:$PORT, $DOMAIN {
	tls $EMAIL
	route {
		forward_proxy {
			basic_auth $USERNAME $PASSWD
			hide_ip
			hide_via
			probe_resistance
		}
		reverse_proxy https://demo.cloudreve.org {
			#伪装网址
			header_up Host {upstream_hostport}
			header_up X-Forwarded-Host {host}
		}
	}

	log {
		output file /var/log/caddy/log.txt {
            roll_size 10mb
            roll_keep 20
            roll_keep_for 7d
		}
        format json {
            time_local
            time_format wall_milli
        }
	}
}
    
EOF
}

add_daemon() {
    # move caddy to PATH
    chmod +x caddy && mv caddy /usr/bin/

    # add user and user group
    groupadd --system caddy
    useradd --system \
    --gid caddy \
    --create-home \
    --home-dir /var/lib/caddy \
    --shell /usr/sbin/nologin \
    --comment "Caddy web server" \
    caddy

    # set daemon
    cat >> /etc/systemd/system/ << EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target 
EOF

    # reload daemon
    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy
}

output_config() {
    info "naive已经安装完毕"
    remind "\t端口: $PORT"
    remind "\t域名: $DOMAIN"
    remind "\t用户名: $USERNAME"
    remind "\t密码: $PASSWD"
}

get_info
install_go
install_naive
add_daemon
output_config



