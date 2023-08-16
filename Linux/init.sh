#!/usr/bin/env bash

# Linux Init Script by XiaoBai
# Initial August 2023; Last update August 2023

# Purpose:    The purpose of this script is to quickly init linux setting.
#             Thereby avoiding cumbersome manual settings.

shopt -s expand_aliases
alias echo="echo -e"

INSTALL_LOG=$(mktemp)
trap 'rm -rf "${INSTALL_LOG}"' EXIT

SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
SSH_PORT_MIN=50000
SSH_PORT_MAX=60000

END_COLOR="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"

error() {
    echo ""
    echo "${RED}$*${END_COLOR}"
    echo ""
}

info() {
    echo ""
    echo "${GREEN}$*${END_COLOR}"
    echo ""
}

remind() {
    echo ""
    echo "${BLUE}$*${END_COLOR}"
    echo ""
}

warning() {
    echo ""
    echo "${YELLOW}$*${END_COLOR}"
    echo ""
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

configure_shell() {
    remind "正在配置终端"

    # 判断终端的类型
    config_file=""
    if echo "$SHELL" | grep -m 1 bash; then
        config_file=".bashrc"
        info "当前终端为 bash"
    elif echo "$SHELL" | grep -m 1 zsh; then
        info "当前终端为 zsh"
        config_file=".zshrc"
    else
        error "不支持的Shell !!!"
        return
    fi
    {
        echo "export HISTTIMEFORMAT='%F %T  '"
        echo "export HISTSIZE=10000"
        echo "export HISTIGNORE='pwd:ls:exit'"
        echo "alias ll=\"ls -lh\""
        echo "alias la=\"ls -lha\""
        echo "alias vim=\"nvim\""
    } >>"$HOME/${config_file}"

    info "终端配置完成，请重新登录终端"
}

install_baota() {
    remind "开始安装宝塔面板......"

    bt --version && warning "宝塔面板已经存在，跳过..." && return

    # 安装宝塔开心板 7.7
    apt-get update && apt-get install -y curl wget git

    echo ""
    info "正在安装宝塔面板V7.7......"
    echo ""
    curl -sSO https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh && bash install_panel.sh <<<y >>"$INSTALL_LOG"

    echo ""
    info "正在安装破解补丁......"
    echo ""
    curl -sSO https://raw.githubusercontent.com/ztkink/bthappy/main/one_key_happy.sh && bash one_key_happy.sh <<<y

    info "宝塔安装完成"
}

config_baota() {
    remind "正在配置宝塔面板......"

    ! [[ -e INSTALL_LOG ]] && return

    local cookie_file plugins username password url username_md5 password_md5 password_md5_tmp main_html login_result result main_html http_token cookie_token

    cookie_file=$(mktemp)
    trap 'rm -rf "${cookie_file}"' RETURN

    plugins=(
        "sName=nginx&version=1.22&type=1&id=32"
        "sName=mysql&version=5.6&type=1&id=32"
        "sName=pureftpd&version=1.0.49&type=1&id=32"
        "sName=php-7.4&version=7.4&type=1&id=32"
        "sName=phpmyadmin&version=4.4&type=1&id=32"
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
    login_result=$(curl -c "$cookie_file" 'http://192.168.230.2:8888/login' \
        -H 'Origin: http://192.168.230.2:8888' \
        -H "Referer: $url" \
        --data-raw "username=$username_md5&password=$password_md5&code=" \
        --compressed \
        --insecure)

    if ! (echo "$login_result" | jq -r '.status'); then
        error "宝塔面板登录失败！！！"
        error "请自行登录宝塔面板，完成初始化操作"
    else
        info "宝塔面板登录成功"
    fi

    main_html=$(mktemp)
    trap 'rm -rf "${main_html}"' RETURN

    # 获取 csrf token
    curl -o "$main_html" -b "$cookie_file" 'http://192.168.230.2:8888/' \
        -H 'DNT: 1' \
        -H "Referer: $url" \
        -H 'Upgrade-Insecure-Requests: 1' \
        --compressed \
        --insecure

    http_token=$(grep -m 1 request_token_head "$main_html" | awk -F'token="' '/request_token_head/ {print $2}' | awk -F'"' '{print $1}')
    cookie_token=$(grep -m 1 request_token "$cookie_file" | awk '{print $7}')

    for i in "${plugins[@]}"; do
        result=$(curl -b "$cookie_file" 'http://192.168.230.2:8888/plugin?action=install_plugin' \
            -H 'Referer: http://192.168.230.2:8888/' \
            -H "X-Cookie-Token: $cookie_token" \
            -H "X-Http-Token: $http_token" \
            --data-raw "$i" \
            --compressed \
            --insecure)

        remind "$result"
    done

    until [[ "$chosen" == "y" ]] || [[ "$chosen" == "n" ]]; do
        read -r -p "是否要修改用户名和密码(y/n)？" chosen
    done

    # 修改密码
    if "$chosen"; then
        unset username password
        read -rp "请输入用户名: " username
        read -rp "请输入密码： " password

        bt <<<6 "$username"
        bt <<<5 "$password"

        info "用户名密码修改成功!"
    fi

    remind "用户名： ${username}"
    remind "密码： ${password}"
    remind "地址： ${url}"
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
    curl -SL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose &&
        chmod +x /usr/local/bin/docker-compose || error "docker-compose 安装失败"

    info "docker安装完成"
}

install_neovim() {
    remind "开始安装neovim"

    neovim --version && warning "neovim 已经安装，跳过..." && return

    info "正在安装neovim"
    # 安装neovim 并且配置自动切换输入法
    apt install -y neovim

    info "正在配置neovim"
    # 配置自动切换输入法
    [[ -d "$HOME/.config/nvim" ]] || mkdir -p "$HOME/.config/nvim"
    cat >>init.lua <<EOF

-- 记录当前输入法
Current_input_method = vim.fn.system("/usr/local/bin/macism")

-- 切换到英文输入法
function Switch_to_English_input_method()
    Current_input_method = vim.fn.system("/usr/local/bin/macism")
    if Current_input_method ~= "com.apple.keylayout.ABC\n" then
        vim.fn.system("/usr/local/bin/macism com.apple.keylayout.ABC")
    end
end

-- 设置输入法
function Set_input_method()
    if Current_input_method ~= "com.apple.keylayout.ABC\n" then
        vim.fn.system("/usr/local/bin/macism " .. string.gsub(Current_input_method, "\n", ""))
    end
end

-- 进入 normal 模式时切换为英文输入法
vim.cmd([[
augroup input_method
  autocmd!
  autocmd InsertEnter * :lua Set_input_method()
  autocmd InsertLeave * :lua Switch_to_English_input_method()
augroup END
]])
EOF

}

set_sshd() {
    remind "正在设置sshd... "

    sshd_status_file=$(mktemp)
    trap 'rm -rf "${sshd_status_file}"' RETURN

    curl --version || apt install -y curl

    [[ -e /etc/ssh/sshd_config ]] && apt install -y openssh-server

    mv "$SSHD_CONFIG_FILE" "${SSHD_CONFIG_FILE}_back"

    info "正在下载配置文件"
    curl -sSo "$SSHD_CONFIG_FILE" https://raw.githubusercontent.com/flyflas/CommonScripts/main/Linux/sshd_config

    random_number=$((SSH_PORT_MIN + RANDOM % (SSH_PORT_MAX - SSH_PORT_MIN + 1)))

    sed -i "s/#Port 22/Port ${random_number}/" "$SSHD_CONFIG_FILE"
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
        info "正在重启ssh-server服务，请稍后... ${i}\r"
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

        remind "端口： ${random_number}"
    else
        error "Failed!!! 正在回退设置"
        rm -rf "$SSHD_CONFIG_FILE"
        mv "${SSHD_CONFIG_FILE}_back" "$SSHD_CONFIG_FILE"
        systemctl restart sshd
    fi
}

help() {
    echo "用法： ./init.sh [-flags]"
    echo ""
    echo "Flags: "
    echo "          -a : 安装全部"
    echo "          -b : 安装除了baota面板的其他组件"
    echo "          --btop : 安装btop"
    echo "          --baota : 安装baota"
    echo "          --bash : 配置bash"
    echo "          --docker: 安装docker"
    echo "          --neovim : 安装neovim"
    echo "          --sshd : 设置sshd"
    echo "          --zsh : 安装zsh"
}

main() {
    options=$(getopt -o abh --long btop,baota,config,docker,neovim,zsh,help -n 'init.sh' -- "$@")
    eval set -- "$options"

    apt update

    while true; do
        case "$1" in
        -a)
            install_btop
            install_baota
            config_baota
            install_docker
            install_neovim
            install_zsh
            configure_shell
            set_sshd

            echo ""
            echo "*****************************************************"
            echo "*                  install status                   *"
            echo "*****************************************************"
            echo "*                                                   *"

            if btop --version &>>/dev/null; then
                printf "*          btop... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          btop... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            if bt --version &>>/dev/null; then
                printf "*          baota... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          baota... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

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

            if nvim --version &>>/dev/null; then
                printf "*          neovim... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          neovim... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            if zsh --version &>>/dev/null; then
                printf "*          zsh... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          zsh... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                                   *"
            echo "*****************************************************"
            echo ""

            shift
            ;;
        -b)
            install_btop
            install_docker
            install_neovim
            install_zsh
            configure_shell
            set_sshd

            echo ""
            echo "*****************************************************"
            echo "*                  install status                   *"
            echo "*****************************************************"
            echo "*                                                   *"

            if btop --version &>>/dev/null; then
                printf "*          btop... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          btop... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

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

            if nvim --version &>>/dev/null; then
                printf "*          neovim... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          neovim... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            if zsh --version &>>/dev/null; then
                printf "*          zsh... \t\t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          zsh... \t\t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                                   *"
            echo "*****************************************************"
            echo ""

            shift
            ;;
        --btop)
            install_btop

            echo ""
            echo "*********************************************"
            echo "*              install status               *"
            echo "*********************************************"
            echo "*                                           *"

            if btop --version &>>/dev/null; then
                printf "*              btop... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*              btop... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                           *"
            echo "*********************************************"
            echo ""

            shift
            ;;
        --baota)
            install_baota
            config_baota

            echo ""
            echo "*********************************************"
            echo "*              install status               *"
            echo "*********************************************"
            echo "*                                           *"

            if bt --version &>>/dev/null; then
                printf "*          宝塔面板... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*          宝塔面板... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                           *"
            echo "*********************************************"
            echo ""

            shift
            ;;
        --config)
            configure_shell
            shift
            ;;
        --docker)
            install_docker

            echo ""
            echo "*********************************************"
            echo "*              install status               *"
            echo "*********************************************"
            echo "*                                           *"

            if docker --version &>>/dev/null; then
                printf "*         docker... \t\t %b%s%b         *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*         docker... \t\t %b%s%b       *\n" "$RED" "failed" "$END_COLOR"
            fi

            if docker-compose --version &>>/dev/null; then
                printf "*         docker-compose... \t %b%s%b         *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*         docker-compose... \t %b%s%b       *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                           *"
            echo "*********************************************"
            echo ""

            shift
            ;;
        --neovim)
            install_neovim

            echo ""
            echo "*********************************************"
            echo "*              install status               *"
            echo "*********************************************"
            echo "*                                           *"

            if nvim --version &>>/dev/null; then
                printf "*            neovim... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*            neovim... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                           *"
            echo "*********************************************"
            echo ""

            shift
            ;;
        --zsh)
            install_zsh

            echo ""
            echo "*********************************************"
            echo "*              install status               *"
            echo "*********************************************"
            echo "*                                           *"

            if zsh --version &>>/dev/null; then
                printf "*               zsh... \t %b%s%b                 *\n" "$GREEN" "ok" "$END_COLOR"
            else
                printf "*               zsh... \t %b%s%b             *\n" "$RED" "failed" "$END_COLOR"
            fi

            echo "*                                           *"
            echo "*********************************************"
            echo ""

            shift
            ;;
        --sshd)
            set_sshd
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
}

main "$@"
