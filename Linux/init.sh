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

help() {
    echo "用法： ./init.sh [-flags]"
    echo ""
    echo "Flags: "
    echo "          -a : 安装全部"
    echo "          -b : 安装除了baota面板的其他组件"
    echo "          --small : 最小化安装"
    echo "          --btop : 安装btop"
    echo "          --baota : 安装baota"
    echo "          --bash : 配置bash"
    echo "          --docker: 安装docker"
    echo "          --neovim : 安装neovim"
    echo "          --sshd : 设置sshd"
    echo "          --zsh : 安装zsh"
}

install_btop() {
    remind "开始安装btop"

    btop --version && warning "btop 已经安装，跳过..." && return

    apt install -y coreutils sed git build-essential gcc-11 g++-11 ||
        apt install -y coreutils sed git build-essential gcc g++

    info "正在编译btop源码，这可能需要一段时间......"
    cd "$HOME" &&
        git clone https://github.com/aristocratos/btop.git &&
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
    curl -sSL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose &&
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
    curl -sSo "$SSHD_CONFIG_FILE" https://raw.githubusercontent.com/flyflas/CommonScripts/main/Linux/sshd_config

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
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" <<<n

    info "正在安装powerlevel10k"
    # install powerlevel10k
    apt install git &&
        git clone https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k &&
        grep -q '^ZSH_THEME=' ~/.zshrc && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

    info "重启终端生效......"
}

config_shell() {
    remind "正在配置终端"

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

install_baota() {
    remind "开始安装宝塔面板......"

    bt --version && warning "宝塔面板已经存在，跳过..." && return

    # 安装宝塔开心板 7.7
    apt-get update && apt-get install -y curl wget git jq

    echo ""
    info "正在安装宝塔面板V7.7......"
    echo ""
    curl -sSO https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh && bash install_panel.sh <<<y >>"$INSTALL_LOG"

    echo ""
    info "正在安装破解补丁......"
    echo ""
    curl -sSO https://raw.githubusercontent.com/ztkink/bthappy/main/one_key_happy.sh && bash one_key_happy.sh <<<y

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
    fi

    until [[ "$chosen" == "y" ]] || [[ "$chosen" == "n" ]]; do
        read -r -p "是否要修改用户名和密码(y/n)？" chosen
    done

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

options=$(getopt -o abh --long btop,baota,config,docker,neovim,zsh,help,small,reality -n 'init.sh' -- "$@")
eval set -- "$options"

apt update

while true; do
    case "$1" in
    -a)
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
        IS_INSTALL_BTOP=true
        IS_INSTALL_ZSH=true
        IS_SET_SSHD=true
        IS_CONFIG_SHELL=true
        IS_INSTALL_NEOVIM=true
        IS_INSTALL_NEXTTRACE=true

        shift
        ;;
    --btop)
        IS_INSTALL_BTOP=true
        shift
        ;;
    --baota)
        IS_INSTALL_BAOTA=true
        shift
        ;;
    --config)
        IS_CONFIG_SHELL=true
        shift
        ;;
    --docker)
        IS_INSTALL_DOCKER=true
        shift
        ;;
    --neovim)
        IS_INSTALL_NEOVIM=true
        shift
        ;;
    --zsh)
        IS_INSTALL_ZSH=true
        shift
        ;;
    --sshd)
        IS_SET_SSHD=true
        shift
        ;;
    --reality)
        IS_INSTALL_REALITY=true
        shift
        ;;
    --nexttrace)
        IS_INSTALL_NEXTTRACE=true
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
    esac
done

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
    bash -c "$(curl http://nexttrace-io-leomoe-api-a0.shop/nt_install.sh)"
fi

if $IS_INSTALL_BAOTA; then
    install_baota
fi

if $IS_INSTALL_REALITY; then
    curl -fsSL -o "${HOME}/Xray-script.sh" https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash "${HOME}/Xray-script.sh" <<<1
fi

# show result
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
