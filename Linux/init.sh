#!/usr/bin/env bash

# Linux Init Script by XiaoBai
# Initial August 2023; Last update August 2023

# Purpose:    The purpose of this script is to quickly init linux setting.
#             Thereby avoiding cumbersome manual settings.

shopt -s expand_aliases
alias echo="echo -e"

INSTALL_LOG=$(mktemp)
trap 'rm -rf "${INSTALL_LOG}"' EXIT

# 安装参数
IS_INSTALL_BTOP=false
IS_INSTALL_BAOTA=false
IS_INSTALL_DOCKER=false
IS_INSTALL_ZSH=false
IS_CONFIG_SHELL=false
IS_SET_SSHD=false
IS_INSTALL_NEOVIM=false
IS_INSTALL_NEXTTRACE=false
IS_INSTALL_REALITY=false
IS_SHOW_RESULT=false
IS_UPDATE=false
IS_SWITCH_MIRROR=false
IS_INSTALL_HYSTERIA=false

# 软件下载地址，国内节点用于替换加速
URL_BTOP_REPOSITORY="https://github.com/aristocratos/btop.git"
URL_DOCKER_COMPOSE_RELEASE="https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64"
URL_SSHD_CONFIG="https://raw.githubusercontent.com/flyflas/CommonScripts/main/Linux/sshd_config"
URL_OH_MY_ZSH_SCRIPT="https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh"
URL_POWERLEVEL10K_REPOSITORY="https://github.com/romkatv/powerlevel10k.git"
URL_BAOTA_SCRIPT="https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh"
URL_BAOTA_HAPPY_SCRIPT="https://raw.githubusercontent.com/ztkink/bthappy/main/one_key_happy.sh"

SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
SSH_PORT_MIN=50000
SSH_PORT_MAX=60000
SSH_PORT=-1

BT_USERNAME=""
BT_PASSWORD=""
BT_URL=""

END_COLOR="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"

error() {
    echo ""
    echo "${RED}$*${END_COLOR}"
}

info() {
    echo ""
    echo "${GREEN}$*${END_COLOR}"
}

remind() {
    echo ""
    echo "${BLUE}$*${END_COLOR}"
}

warning() {
    echo ""
    echo "${YELLOW}$*${END_COLOR}"
}

clear_buffer() {
    read -r -t 0.001 -n 1000 discard
}

help() {
    echo "用法： ./init.sh [-flags]"
    echo ""
    echo "Flags: "
    echo "          -a : 安装全部"
    echo "          -b : 安装除了baota面板的其他组件"
    echo "          -s : 切换国内镜像源"
    echo "          --small : 最小化安装(btop zsh sshd noevim config_bash)"
    echo "          --btop : 安装btop"
    echo "          --baota : 安装baota"
    echo "          --bash : 配置bash"
    echo "          --docker: 安装docker"
    echo "          --neovim : 安装neovim"
    echo "          --nexttrace : 安装nexttrace"
    echo "          --reality : 安装Reality"
    echo "          --sshd : 设置sshd"
    echo "          --zsh : 安装zsh"
}

switch_mirror() {
    URL_BTOP_REPOSITORY="https://github.499990.xyz/https://github.com/aristocratos/btop.git"
    URL_DOCKER_COMPOSE_RELEASE="https://github.499990.xyz/https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64"
    URL_SSHD_CONFIG="https://github.499990.xyz/https://raw.githubusercontent.com/flyflas/CommonScripts/main/Linux/sshd_config"
    URL_OH_MY_ZSH_SCRIPT="https://github.499990.xyz/https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh"
    URL_POWERLEVEL10K_REPOSITORY="https://github.499990.xyz/https://github.com/romkatv/powerlevel10k.git"
    URL_BAOTA_SCRIPT="https://github.499990.xyz/https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh"
    URL_BAOTA_HAPPY_SCRIPT="https://github.499990.xyz/https://raw.githubusercontent.com/ztkink/bthappy/main/one_key_happy.sh"
}

install_btop() {
    remind "开始安装btop"

    btop --version && warning "btop 已经安装，跳过..." && return

    apt install -y coreutils sed git build-essential gcc-11 g++-11 ||
        apt install -y coreutils sed git build-essential gcc g++

    info "正在编译btop源码，这可能需要一段时间......"
    cd "$HOME" &&
        git clone "$URL_BTOP_REPOSITORY" &&
        cd btop &&
        make &&
        make install

    info "btop安装完成"
}

install_docker() {
    remind "开始安装docker"

    docker --version && warning "docker 已经安装，跳过..." && return

    apt install -y curl wget >>/dev/null

    info "正在安装docker"
    # install docker
    curl -fsSL https://get.docker.com -o get-docker.sh &&
        sh get-docker.sh || error "docker 安装失败"

    info "正在安装docker-compose"
    # install docker-compose
    curl -sSL "$URL_DOCKER_COMPOSE_RELEASE" -o /usr/local/bin/docker-compose &&
        chmod +x /usr/local/bin/docker-compose || error "docker-compose 安装失败"

    info "docker安装完成"
}

install_neovim() {
    remind "开始安装neovim"

    neovim --version && warning "neovim 已经安装，跳过..." && return

    info "正在安装neovim"
    # 安装neovim 并且配置自动切换输入法
    apt install -y neovim

    info "neovim 安装完成"
}

set_sshd() {
    remind "正在设置sshd... "

    sshd_status_file=$(mktemp)
    trap 'rm -rf "${sshd_status_file}"' EXIT

    curl --version || apt install -y curl

    [[ -e /etc/ssh/sshd_config ]] && apt install -y openssh-server

    mv "$SSHD_CONFIG_FILE" "${SSHD_CONFIG_FILE}_back"

    info "正在下载配置文件"
    curl -sSo "$SSHD_CONFIG_FILE" "$URL_SSHD_CONFIG"

    SSH_PORT=$((SSH_PORT_MIN + RANDOM % (SSH_PORT_MAX - SSH_PORT_MIN + 1)))

    sed -i "s/#Port 22/Port ${SSH_PORT}/" "$SSHD_CONFIG_FILE"
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" "$SSHD_CONFIG_FILE"
    sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" "$SSHD_CONFIG_FILE"

    info "正在生成SSH-Key"
    ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N ''

    if ! { [[ -e "${HOME}/.ssh/id_ed25519" ]] && [[ -e "${HOME}/.ssh/id_ed25519.pub" ]]; }; then
        error "Error!!! 秘钥生成失败，正在回滚设置"
        rm -rf "$SSHD_CONFIG_FILE"
        mv "${SSHD_CONFIG_FILE}_back" "$SSHD_CONFIG_FILE"
        systemctl restart sshd
        return
    fi

    cat "${HOME}/.ssh/id_ed25519.pub" >>"${HOME}/.ssh/authorized_keys"

    systemctl restart sshd

    i=10
    while ((i > 0)); do
        printf "\r正在重启ssh-server服务，请稍后...   %b%d%b  \t" "$GREEN" $i "$END_COLOR"

        sleep 1
        ((i--))
    done

    systemctl status sshd >>"$sshd_status_file"

    # get status
    if grep -m 1 "Active: active (running)" "$sshd_status_file"; then
        info "sshd_config设置成功"
        remind "私钥："
        cat "${HOME}/.ssh/id_ed25519"
        echo -e ""

        remind "公钥: "
        cat "${HOME}/.ssh/id_ed25519.pub"
        echo -e ""

        remind "端口： ${SSH_PORT}"
    else
        error "Failed!!! 正在回退设置"
        rm -rf "$SSHD_CONFIG_FILE"
        mv "${SSHD_CONFIG_FILE}_back" "$SSHD_CONFIG_FILE"
        systemctl restart sshd
    fi
}

install_zsh() {
    remind "开始安装zsh"

    echo "$SHELL" | grep -m 1 && warning "zsh已经安装，跳过..." && return

    info "正在安装zsh"
    # install zsh
    apt-get update &&
        apt-get install -y zsh &&
        sh -c "echo $(which zsh) >> /etc/shells" &&
        chsh -s "$(which zsh)"

    info "正在安装on-my-zsh"
    # install oh-my-zsh
    sh -c "$(curl -fsSL "$URL_OH_MY_ZSH_SCRIPT")" <<<n

    info "正在安装powerlevel10k"
    # install powerlevel10k
    apt install git &&
        git clone "$URL_POWERLEVEL10K_REPOSITORY" ~/.oh-my-zsh/custom/themes/powerlevel10k &&
        grep -q '^ZSH_THEME=' ~/.zshrc && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

    info "重启终端生效......"
}

config_shell() {
    remind "正在配置终端"
    timedatectl set-timezone Asia/Shanghai

    # 判断终端的类型
    config_file=""

    if $IS_INSTALL_ZSH; then
        config_file=".zshrc"
    else
        if [[ -e "${HOME}/.bashrc" ]]; then
            config_file=".bashrc"
            info "当前终端为 bash"
        elif [[ -e "${HOME}/.zshrc" ]]; then
            info "当前终端为 zsh"
            config_file=".zshrc"
        else
            error "不支持的Shell !!!"
            return
        fi
    fi

    {
        echo "export HISTTIMEFORMAT='%F %T  '"
        echo "export HISTSIZE=10000"
        echo "export HISTIGNORE='pwd:ls:exit'"
        echo "alias ll=\"ls -lh\""
        echo "alias la=\"ls -lha\""
        echo "alias vim=\"nvim\""
        echo "alias cls=\"clear\""
    } >>"$HOME/${config_file}"

    info "终端配置完成，请重新登录终端"
}

install_acme() {
    ssl_path="/opt/ssl"
    acme_path="$HOME/.acme.sh"

    # 清空输入缓冲区
    # while read -r -t 0; do
    # read -r
    # done

    clear_buffer

    if ! [[ -e "${acme_path}" ]]; then
        read -r -p "请输入邮箱：" email
        curl https://get.acme.sh | sh -s email="$email"
    fi

    clear_buffer
    until [[ "$chosen" == "y" ]] || [[ "$chosen" == "n" ]]; do
        read -r -p "是否申请证书(y/n): " chosen
    done

    if [[ "$chosen" == "n" ]]; then
        return
    fi

    clear_buffer
    until [[ "$dns" == "0" ]] || [[ "$dns" == "1" ]] || [[ "$dns" == "2" ]]; do
        echo "请输入你的DNS: "
        printf "\t0. 退出\n"
        printf "\t1. Cloudflare\n"
        printf "\t2. DNSPOD.COM\n"
        read -r dns
    done

    if [[ "$dns" == 0 ]]; then
        return
    fi

    # 清空输入缓冲区
    # while read -r -t 0; do
    # read -r
    # done
    clear_buffer

    read -r -p "请输入你需要申请证书的域名： " domain
    if [[ "$dns" == "1" ]]; then
        read -r -p "请输入你的CF_Account_ID: " account_id
        read -r -p "请输入你的CF_Token: " token

        export CF_Account_ID="$account_id"
        export CF_Token="$token"

        if "${acme_path}/acme.sh" --issue --dns dns_cf -d "$domain"; then
            info "证书申请成功"
            mkdir "$ssl_path"
            "${acme_path}/acme.sh" --install-cert -d "$domain" \
                --key-file "${ssl_path}/key.pem" \
                --fullchain-file "${ssl_path}/cert.pem"
        else
            error "证书申请失败，请检查原因...."
        fi

    elif [[ "$dns" == "2" ]]; then
        read -r -p "请输入你的DPI_Id: " dpi_id
        read -r -p "请输入你的DPI_Key: " dpi_key

        export DPI_Id="$dpi_id"
        export DPI_Key="$dpi_key"

        if "${acme_path}/acme.sh" --issue --dns dns_dpi -d "$domain"; then
            info "证书申请成功"
            mkdir "$ssl_path"
            "${acme_path}/acme.sh" --install-cert -d "$domain" \
                --key-file "${ssl_path}/key.pem" \
                --fullchain-file "${ssl_path}/cert.pem"
        else
            error "证书申请失败，请检查原因...."
        fi
    fi

    chmod +r "${ssl_path}/key.pem"

}

install_hysteria() {
    if hysteria -h; then
        remind "Hysteria 已经安装！！！"
        return
    fi

    bash <(curl -fsSL https://get.hy2.sh/) &&
        mv /etc/hysteria/config.yaml /etc/hysteria/config.yaml.back &&
        curl -sSL -o /etc/hysteria/config.yaml https://raw.githubusercontent.com/flyflas/CommonScripts/main/Linux/hysteria2_config.yaml

    # 清空输入缓冲区
    # while read -r -t 0; do
    # read -r
    # done
    clear_buffer

    read -r -p "请输入Hysteria2 的端口: " port
    uuid=$(cat /proc/sys/kernel/random/uuid)

    sed -i "s/Port\b/$port/" /etc/hysteria/config.yaml
    sed -i "s/UUID\b/$uuid/" /etc/hysteria/config.yaml

    systemctl enable hysteria-server.service &&
        systemctl restart hysteria-server.service

    status=$(systemctl status hysteria-server.service | grep 'Active:' | awk '{print $2}')
    if [[ "$status" == "active" ]]; then
        info "Hysteria 运行成功"
        echo "端口：${port}"
        echo "密码： ${uuid}"
        echo "ipv4: $(curl -s4 ifconfig.co)"
        echo "ipv6: $(curl -s6 ifconfig.co)"
    else
        error "Hysteria 运行失败，请查看原因"
    fi

    info "如果你想要使用端口跳跃功能，请运行以下的命令..."
    warning "请注意替换网卡，目标端口！！！"
    echo ""
    echo ""
    info "iptables -t nat -A PREROUTING -i eth0 -p udp --dport 20000:50000 -j DNAT --to-destination :443"
    info "ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 20000:50000 -j DNAT --to-destination :443"
    echo ""
    echo ""
}

# 用于配置 Hysteria 端口跃迁 的 iptables 规则
config_hysteria_iptables() {
    # 获取所有接口名称，并将它们放入数组中
    interfaces=($(ip -o link show | awk -F': ' '{print $2}' | awk '{print $1}'))

    # 输出所有接口名称以及序号
    echo "可用网口列表："
    for ((i = 0; i < ${#interfaces[@]}; i++)); do
        echo "$((i + 1)). ${interfaces[i]}"
    done

    # 获取接口数量
    max_choice=${#interfaces[@]}

    # 循环直到用户输入正确为止
    while true; do
        # 要求用户输入选择的接口序号
        read -rp "请选择一个接口（输入序号）: " choice

        # 检查用户输入是否为有效的整数，并且在有效范围内
        if [[ "$choice" =~ ^[1-9][0-9]*$ && "$choice" -ge 1 && "$choice" -le "$max_choice" ]]; then
            break
        else
            error "错误：请输入有效的接口序号。"
        fi
    done

    # 用户选择的接口名称
    selected_interface="${interfaces[choice - 1]}"
    echo "您选择了接口：$selected_interface"

    confirm=""
    while true; do
        read -rp "请输入UDP起始端口：" start_port
        read -rp "请输入UDP终止端口：" end_port

        echo "UDP端口跃迁范围: ${start_port} - ${end_port}"
        read -rp "是否使用该范围的端口(y/n): " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "用户确认使用该范围的端口。"
            break
        elif [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "用户取消使用该范围的端口。"
            break
        else
            echo "错误：请输入 'y' 或 'n'。"
        fi
    done

    if [[ "$confirm" == "n" ]]; then
        return
    fi

    if [[ ! -f "/opt/script" ]]; then
        mkdir "/opt/script"
        echo "该目录用于存放开机自动执行的脚本" >>"/opt/script/README"
    fi

    if [[ ! -f "/etc/hysteria/config.yaml" ]]; then
        error "错误： 未发现Hyseteria的配置文件！！！ 请检查Hysteria是否正确安装"
        return
    fi

    hysteria_port=$(grep 'listen:' /etc/hysteria/config.yaml | awk -F': ' '{print $2}' | cut -d':' -f2)

    echo "#!/usr/bin/env bash" >>"/opt/script/set_iptables.sh"
    echo "iptables -t nat -A PREROUTING -i ${selected_interface} -p udp --dport ${start_port}:${end_port} -j DNAT --to-destination :${hysteria_port}" >>"/opt/script/set_iptables.sh"

    # 是否支持ipv6访问
    
    # 检查 ping6 命令的退出状态
    if ping -c 1 ipv6.google.com >/dev/null 2>&1; then
        echo "ip6tables -t nat -A PREROUTING -i ${selected_interface} -p udp --dport ${start_port}:${end_port} -j DNAT --to-destination :${hysteria_port}" >>"/opt/script/set_iptables.sh"
    else
        info "您的网络不支持IPV6"
    fi
    
    chmod +x /opt/script/set_iptables.sh

    info "设置开机启动项"
    cat >>/etc/systemd/system/hy-iptables.service <<EOF
[Unit]
Description=Set iptables for hysteria
After=network.target

[Service]
Type=simple
ExecStart=/opt/script/set_iptables.sh
Restart=always

[Install]
WantedBy=multi-user.target

EOF

    systemctl daemon-reload
    systemctl enable hy-iptables.service
    
    # 在设置完成后，立即执行脚本，完成iptables的设置
    /opt/script/set_iptables.sh

}

install_baota_v8() {
    remind "开始安装宝塔面板......"

    bt --version && warning "宝塔面板已经存在，跳过..." && return

    apt-get update && apt-get install -y curl wget git jq

    echo ""
    info "正在安装宝塔面板V8.0.3......"
    echo ""
    curl -sSL -o "install_panel.sh" "https://install.baota.sbs/install/install_6.0.sh" && bash install_panel.sh <<<y >>"$INSTALL_LOG"

    # echo ""
    # info "正在安装破解补丁......"
    # echo ""
    # curl -sSO "$URL_BAOTA_HAPPY_SCRIPT" && bash one_key_happy.sh <<<y

    # btpip install pyOpenSSL==22.1.0 && btpip install cffi==1.14

    info "宝塔安装完成"

    remind "正在配置宝塔面板......"

    ! [[ -e "$INSTALL_LOG" ]] && return

    cookie_file=$(mktemp)
    trap 'rm -rf "${cookie_file}"' RETURN

    # plugins=(
    #     "sName=nginx&version=1.22&type=1&id=32"
    #     "sName=mysql&version=5.6&type=1&id=32"
    #     "sName=pureftpd&version=1.0.49&type=1&id=32"
    #     "sName=php-7.4&version=7.4&type=1&id=32"
    #     "sName=phpmyadmin&version=4.4&type=1&id=32"
    # )

    plugins=(
        "sName=nginx&version=1.22&type=1&id=32"
    )

    user_agent="User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"

    login_page=$(mktemp)
    trap 'rm -rf "${login_page}"' EXIT

    login_cookie=$(mktemp)
    trap 'rm -rf "${login_cookie}"' EXIT

    # 获取登录信息
    username=$(grep -m 1 username "$INSTALL_LOG" | awk -F'[: ]+' '{print $2}')
    password=$(grep -m 1 password "$INSTALL_LOG" | sed 's/password:[[:space:]]*//' | awk -F'[: ]+' '{print $2}')
    url=$(grep -m 1 "内网面板地址" "$INSTALL_LOG" | awk -F': ' '{print $2}')
    port=$(echo "$url" | awk -F: '{print $3}' | awk -F/ '{print $1}')
    path=$(echo "$url" | awk -F: '{print $3}' | awk -F/ '{print $2}')

    # 获取 last_token
    curl -sS -c "$login_cookie" -o "$login_page" "http://127.0.0.1:${port}/${path}" \
        -H "$user_agent" \
        --compressed \
        --insecure

    last_token=$(grep -m 1 last_token "$login_page" | grep -oP 'data="([^"]+)"' | cut -d'"' -f2)
    public_key=$(grep -m 1 public_key "$login_page" | grep -oP 'data="([^"]+)"' | cut -d'"' -f2)
    public_key_length=${#public_key}
    # 转化为标准公钥形式
    public_key=$(echo "$public_key" | sed 's/-----BEGIN PUBLIC KEY-----/-----BEGIN PUBLIC KEY-----\n/;s/-----END PUBLIC KEY-----/\n-----END PUBLIC KEY-----/')

    # username_md5=$(echo -n "$username" "$last_token" | md5sum | awk '{print $1}' | md5sum | awk '{print $1}')

    username_md5=$(echo -n "$username""$last_token" | md5sum | awk '{print $1}')
    username_md5_md5=$(echo -n "$username_md5" | md5sum | awk '{print $1}')
    password_md5_tmp="$(echo -n "$password" | md5sum | awk '{print $1}')_bt.cn"
    password_md5_md5=$(echo -n "$password_md5_tmp" | md5sum | awk '{print $1}')

    encrypted_username=""
    encrypted_password=""

    if [[ "$public_key_length" -gt 10 ]]; then
        encrypted_username=$(echo -n "$username_md5_md5" | openssl pkeyutl -encrypt -pubin -inkey <(echo "$public_key") | openssl base64 -A)
        encrypted_password=$(echo -n "$password_md5_md5" | openssl pkeyutl -encrypt -pubin -inkey <(echo "$public_key") | openssl base64 -A)
    else
        encrypted_username="$username_md5_md5"
        encrypted_password="$password_md5_md5"
    fi

    # 登录
    # 关闭宝塔的验证码
    bt <<<23

    sleep 10

    login_result=$(curl -sS -b "$login_cookie" -c "$cookie_file" "http://127.0.0.1:${port}/login" \
        -H 'Content-Type: multipart/form-data' \
        -H "Origin: http://127.0.0.1:${port}" \
        -H "Referer: http://127.0.0.1:${port}/${path}" \
        -H "$user_agent" \
        -F "username=${encrypted_username}" \
        -F "password=${encrypted_password}" \
        --compressed \
        --insecure)

    # login_result=$(curl -sS -c "$cookie_file" "http://127.0.0.1:${port}/login" \
    #     -H "Origin: http://127.0.0.1:${port}" \
    #     -H "Referer: $url" \
    #     --data-raw "username=${encrypted_username}password=${encrypted_password}&code=" \
    #     --compressed \
    #     --insecure)

    info "login_result: ${login_result}"

    if ! (echo "$login_result" | jq -r '.status'); then
        error "宝塔面板登录失败！！！"
        error "请自行登录宝塔面板，完成初始化操作"
        return
    else
        info "宝塔面板登录成功"
    fi

    main_html=$(mktemp)
    trap 'rm -rf "${main_html}"' EXIT

    # 获取 csrf token
    curl -sS -o "$main_html" -b "$cookie_file" "http://127.0.0.1:${port}/?license=True" \
        -H 'DNT: 1' \
        -H "Referer: http://127.0.0.1:${port}/${path}" \
        -H 'Upgrade-Insecure-Requests: 1' \
        --compressed \
        --insecure

    http_token=$(grep -m 1 request_token_head "$main_html" | awk -F'token="' '/request_token_head/ {print $2}' | awk -F'"' '{print $1}')

    for i in "${plugins[@]}"; do
        result=$(curl -sS -b "$cookie_file" "http://127.0.0.1:${port}/plugin?action=install_plugin" \
            -H "Referer: http://127.0.0.1:${port}/" \
            -H "X-Http-Token: $http_token" \
            --data-raw "$i" \
            --compressed \
            --insecure)

        remind "$result"
    done

    if $IS_SET_SSHD; then
        # 设置SSH端口
        result=$(curl -sS -b "$cookie_file" "http://127.0.0.1:${port}/safe/firewall/create_rules" \
            -H "Referer: http://127.0.0.1:${port}/firewall" \
            -H "X-Http-Token: $http_token" \
            --data-raw "data=%7B%22protocol%22%3A%22tcp%22%2C%22ports%22%3A%22${SSH_PORT}%22%2C%22choose%22%3A%22all%22%2C%22address%22%3A%22%22%2C%22domain%22%3A%22%22%2C%22types%22%3A%22accept%22%2C%22brief%22%3A%22SSHD%22%2C%22source%22%3A%22%22%7D" \
            --compressed \
            --insecure)

        info "$result"
    else
        # 设置SSH端口
        sshd_port=$(grep -m 1 Port /etc/ssh/sshd_config | awk '/Port/ {print $2}')
        info "SSHD Port: ${sshd_port}, 正在添加防火墙"
        result=$(curl -sS -b "$cookie_file" "http://127.0.0.1:${port}/safe/firewall/create_rules" \
            -H "Referer: http://127.0.0.1:${port}/firewall" \
            -H "X-Http-Token: $http_token" \
            --data-raw "data=%7B%22protocol%22%3A%22tcp%22%2C%22ports%22%3A%22${sshd_port}%22%2C%22choose%22%3A%22all%22%2C%22address%22%3A%22%22%2C%22domain%22%3A%22%22%2C%22types%22%3A%22accept%22%2C%22brief%22%3A%22SSHD%22%2C%22source%22%3A%22%22%7D" \
            --compressed \
            --insecure)
        info "$result"
    fi

    clear_buffer
    until [[ "$chosen" == "y" ]] || [[ "$chosen" == "n" ]]; do
        read -r -p "是否要修改用户名和密码(y/n)？" chosen
    done

    clear_buffer
    # 修改密码
    if [[ "$chosen" == "y" ]]; then
        read -rp "请输入用户名: " username
        read -rp "请输入密码： " password

        bt <<<6 "$username" >>/dev/null
        bt <<<5 "$password" >>/dev/null

        info "用户名密码修改成功!"
    fi

    BT_USERNAME="$username"
    BT_PASSWORD="$password"
    BT_URL="$url"

    remind "用户名： ${username}"
    remind "密码： ${password}"
    remind "地址： ${url}"
}

install_baota() {
    remind "开始安装宝塔面板......"

    bt --version && warning "宝塔面板已经存在，跳过..." && return

    # 安装宝塔开心板 7.7
    apt-get update && apt-get install -y curl wget git jq

    echo ""
    info "正在安装宝塔面板V7.7......"
    echo ""
    curl -sSO "$URL_BAOTA_SCRIPT" && bash install_panel.sh <<<y >>"$INSTALL_LOG"

    echo ""
    info "正在安装破解补丁......"
    echo ""
    curl -sSO "$URL_BAOTA_HAPPY_SCRIPT" && bash one_key_happy.sh <<<y

    btpip install pyOpenSSL==22.1.0 && btpip install cffi==1.14

    info "宝塔安装完成"

    remind "正在配置宝塔面板......"

    ! [[ -e "$INSTALL_LOG" ]] && return

    cookie_file=$(mktemp)
    trap 'rm -rf "${cookie_file}"' RETURN

    # plugins=(
    #     "sName=nginx&version=1.22&type=1&id=32"
    #     "sName=mysql&version=5.6&type=1&id=32"
    #     "sName=pureftpd&version=1.0.49&type=1&id=32"
    #     "sName=php-7.4&version=7.4&type=1&id=32"
    #     "sName=phpmyadmin&version=4.4&type=1&id=32"
    # )

    plugins=(
        "sName=nginx&version=1.22&type=1&id=32"
    )

    # 获取登录信息
    username=$(grep -m 1 username "$INSTALL_LOG" | awk -F'[: ]+' '{print $2}')
    password=$(grep -m 1 password "$INSTALL_LOG" | awk -F'[: ]+' '{print $2}')
    url=$(grep -m 1 "内网面板地址" "$INSTALL_LOG" | awk -F': ' '{print $2}')

    username_md5=$(echo -n "$username" | md5sum | awk '{print $1}')
    password_md5_tmp="$(echo -n "$password" | md5sum | awk '{print $1}')_bt.cn"
    password_md5=$(echo -n "$password_md5_tmp" | md5sum | awk '{print $1}')

    # 登录
    # 关闭宝塔的验证码
    bt <<<23

    sleep 10

    login_result=$(curl -sS -c "$cookie_file" 'http://127.0.0.1:8888/login' \
        -H 'Origin: http://127.0.0.1:8888' \
        -H "Referer: $url" \
        --data-raw "username=$username_md5&password=$password_md5&code=" \
        --compressed \
        --insecure)

    if ! (echo "$login_result" | jq -r '.status'); then
        error "宝塔面板登录失败！！！"
        error "请自行登录宝塔面板，完成初始化操作"
        return
    else
        info "宝塔面板登录成功"
    fi

    main_html=$(mktemp)
    trap 'rm -rf "${main_html}"' EXIT

    # 获取 csrf token
    curl -sS -o "$main_html" -b "$cookie_file" 'http://127.0.0.1:8888/' \
        -H 'DNT: 1' \
        -H "Referer: $url" \
        -H 'Upgrade-Insecure-Requests: 1' \
        --compressed \
        --insecure

    http_token=$(grep -m 1 request_token_head "$main_html" | awk -F'token="' '/request_token_head/ {print $2}' | awk -F'"' '{print $1}')
    cookie_token=$(grep -m 1 request_token "$cookie_file" | awk '{print $7}')

    for i in "${plugins[@]}"; do
        result=$(curl -sS -b "$cookie_file" 'http://127.0.0.1:8888/plugin?action=install_plugin' \
            -H 'Referer: http://127.0.0.1:8888/' \
            -H "X-Cookie-Token: $cookie_token" \
            -H "X-Http-Token: $http_token" \
            --data-raw "$i" \
            --compressed \
            --insecure)

        remind "$result"
    done

    if $IS_SET_SSHD; then
        # 设置SSH端口
        result=$(curl -sS -b "$cookie_file" 'http://127.0.0.1:8888/firewall?action=AddAcceptPort' \
            -H 'Referer: http://127.0.0.1:8888/firewall' \
            -H "X-Cookie-Token: $cookie_token" \
            -H "X-Http-Token: $http_token" \
            --data-raw "port=${SSH_PORT}&type=port&ps=SSH_PORT" \
            --compressed \
            --insecure)
    else
        # 设置SSH端口
        sshd_port=$(grep -m 1 Port /etc/ssh/sshd_config | awk '/Port/ {print $2}')
        info "SSHD Port: ${sshd_port}, 正在添加防火墙"
        result=$(curl -sS -b "$cookie_file" 'http://127.0.0.1:8888/firewall?action=AddAcceptPort' \
            -H 'Referer: http://127.0.0.1:8888/firewall' \
            -H "X-Cookie-Token: $cookie_token" \
            -H "X-Http-Token: $http_token" \
            --data-raw "port=${sshd_port}&type=port&ps=SSH_PORT" \
            --compressed \
            --insecure)

    fi

    clear_buffer
    until [[ "$chosen" == "y" ]] || [[ "$chosen" == "n" ]]; do
        read -r -p "是否要修改用户名和密码(y/n)？" chosen
    done

    clear_buffer
    # 修改密码
    if [[ "$chosen" == "y" ]]; then
        read -rp "请输入用户名: " username
        read -rp "请输入密码： " password

        bt <<<6 "$username" >>/dev/null
        bt <<<5 "$password" >>/dev/null

        info "用户名密码修改成功!"
    fi

    BT_USERNAME="$username"
    BT_PASSWORD="$password"
    BT_URL="$url"

    remind "用户名： ${username}"
    remind "密码： ${password}"
    remind "地址： ${url}"
}

# 如果没有提供任何参数，则默认启用 --help 选项
if [ $# -eq 0 ]; then
    help
    IS_SHOW_RESULT=false
    IS_UPDATE=false
fi

options=$(getopt -o abhs --long btop,baota,config,docker,neovim,zsh,help,small,reality,hysteria,nexttrace -n 'init.sh' -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
    -s)
        IS_SWITCH_MIRROR=true

        shift
        ;;
    -a)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_BTOP=true
        IS_INSTALL_DOCKER=true
        IS_INSTALL_ZSH=true
        IS_SET_SSHD=true
        IS_INSTALL_BAOTA=true
        IS_CONFIG_SHELL=true
        IS_INSTALL_NEOVIM=true
        IS_INSTALL_NEXTTRACE=true

        shift
        ;;
    -b)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_BTOP=true
        IS_INSTALL_DOCKER=true
        IS_INSTALL_ZSH=true
        IS_SET_SSHD=true
        IS_CONFIG_SHELL=true
        IS_INSTALL_NEOVIM=true
        IS_INSTALL_NEXTTRACE=true

        shift
        ;;
    --small)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_BTOP=true
        IS_INSTALL_ZSH=true
        IS_SET_SSHD=true
        IS_CONFIG_SHELL=true
        IS_INSTALL_NEOVIM=true
        IS_INSTALL_NEXTTRACE=true

        shift
        ;;
    --btop)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_BTOP=true
        shift
        ;;
    --baota)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_BAOTA=true
        shift
        ;;
    --config)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_CONFIG_SHELL=true
        shift
        ;;
    --docker)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_DOCKER=true
        shift
        ;;
    --neovim)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_NEOVIM=true
        shift
        ;;
    --zsh)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_ZSH=true
        shift
        ;;
    --sshd)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_SET_SSHD=true
        shift
        ;;
    --reality)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_REALITY=true
        shift
        ;;
    --nexttrace)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_NEXTTRACE=true
        shift
        ;;

    --hysteria)
        IS_SHOW_RESULT=true
        IS_UPDATE=true
        IS_INSTALL_HYSTERIA=true
        shift
        ;;
    -h | --help)
        help
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        # 处理其他参数或无效选项
        echo "Invalid option or argument: $1"
        exit 1
        ;;
    esac
done

if $IS_UPDATE; then
    apt update
fi

if $IS_SWITCH_MIRROR; then
    switch_mirror
fi

if $IS_INSTALL_BTOP; then
    install_btop
fi

if $IS_INSTALL_DOCKER; then
    install_docker
fi

if $IS_INSTALL_NEOVIM; then
    install_neovim
fi

if $IS_SET_SSHD; then
    set_sshd
fi

if $IS_INSTALL_ZSH; then
    install_zsh
fi

if $IS_CONFIG_SHELL; then
    config_shell
fi

if $IS_INSTALL_NEXTTRACE; then
    bash -c "$(curl curl nxtrace.org/nt)"
fi

if $IS_INSTALL_BAOTA; then
    install_baota
fi

if $IS_INSTALL_REALITY; then
    apt install -y curl
    curl -fsSL -o "${HOME}/Xray-script.sh" https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash "${HOME}/Xray-script.sh"
fi

if $IS_INSTALL_HYSTERIA; then
    install_acme
    install_hysteria
    config_hysteria_iptables
fi

# show result
if $IS_SHOW_RESULT; then

    echo ""
    echo "*****************************************************"
    echo "*                  install status                   *"
    echo "*****************************************************"
    echo "*                                                   *"

    if $IS_INSTALL_BTOP; then
        if btop --version &>>/dev/null; then
            printf "*          btop... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          btop... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_BAOTA; then
        if bt --version &>>/dev/null; then
            printf "*          baota... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          baota... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_DOCKER; then
        if docker --version &>>/dev/null; then
            printf "*          docker... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          docker... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi

        if docker-compose --version &>>/dev/null; then
            printf "*          docker-compose... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          docker-compose... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_NEOVIM; then
        if nvim --version &>>/dev/null; then
            printf "*          neovim... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          neovim... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_REALITY; then
        if xray --version &>>/dev/null; then
            printf "*          reality... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          reality... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_ZSH; then
        if zsh --version &>>/dev/null; then
            printf "*          zsh... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          zsh... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    if $IS_INSTALL_NEXTTRACE; then
        if nexttrace --version &>>/dev/null; then
            printf "*          nexttrace... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
        else
            printf "*          nexttrace... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
        fi
    fi

    echo "*                                                   *"
    echo "*****************************************************"
    echo ""

    # show info
    echo ""
    echo "*****************************************************"
    echo "*                  setting info                     *"
    echo "*****************************************************"

    # get status
    if $IS_SET_SSHD && systemctl status sshd | grep -m 1 "Active: active (running)" >>/dev/null; then
        remind "SSHD 配置信息"

        info "公钥: "
        cat "${HOME}/.ssh/id_ed25519.pub"

        info "私钥（需要保存）："
        cat "${HOME}/.ssh/id_ed25519"

        info "端口（需要保存）： ${SSH_PORT}"

        error "请务必保存好你的秘钥信息(私钥、SSH端口)！！！"
        error "一定要先配置好本地的SSH信息，在断开该ssh连接。如果有关SSH的信息没有保存好，则无法登录该主机！！！"
        error "建议先在打开一个终端，确保能够登录之后，在断开本终端！！！"
    fi

    if $IS_INSTALL_BAOTA; then
        remind "宝塔配置信息"
        info "宝塔面板用户名: ${BT_USERNAME}"
        info "宝塔面板密码: ${BT_PASSWORD}"
        info "宝塔面板URL: ${BT_URL}"

        error "建议在完成必要的配置之后，停用宝塔面板（传言宝塔有T0级的漏洞，已经有用宝塔被挂马的案例了）。"
    fi
fi
