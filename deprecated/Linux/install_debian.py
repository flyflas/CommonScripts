#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import datetime
import os
import random
import socket
import subprocess
import sys
from shlex import quote
from datetime import datetime
import time

def run(command, check=False, verbose=True, realtime=False):
    """执行shell命令并返回结果
    
    Args:
        command: 要执行的命令字符串
        check: 如果为True，命令失败时抛出异常
        verbose: 如果为True，打印执行的命令
        realtime: 如果为True，实时显示命令输出
        
    Returns:
        subprocess.CompletedProcess对象
    """
    if verbose:
        log(f"执行命令: {command}", "blue")
    
    if realtime:
        # 实时输出模式
        process = subprocess.Popen(
            command,
            shell=True,
            executable='/bin/bash',
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        
        # 实时打印输出
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                print(output.strip())
        
        returncode = process.poll()
        result = subprocess.CompletedProcess(
            command, returncode, '', ''
        )
    else:
        # 普通模式
        result = subprocess.run(
            command,
            shell=True,
            executable='/bin/bash',
            capture_output=True,
            text=True
        )
    
    if check and result.returncode != 0:
        if not realtime:  # 实时模式下错误已显示
            log(f"命令执行失败: {command}", "red")
            log(f"错误输出: {result.stderr}", "red")
        raise subprocess.CalledProcessError(
            result.returncode,
            command,
            output=result.stdout,
            stderr=result.stderr
        )
    return result

def log(msg, color=None):
    """打印带颜色的日志消息
    
    Args:
        msg: 要打印的消息
        color: 颜色名称 (red/green/yellow/blue/magenta/cyan)
    """
    colors = {
        'red': '\033[31m',
        'green': '\033[32m',
        'yellow': '\033[33m',
        'blue': '\033[34m',
        'magenta': '\033[35m',
        'cyan': '\033[36m',
        'reset': '\033[0m'
    }
    
    color_code = colors.get(color, '')
    reset_code = colors['reset']
    print(f"{color_code}{msg}{reset_code}")

def detect_distro():
    """检测当前Linux发行版是否为Debian 12
    
    Returns:
        bool: True表示是Debian 12，False表示不是
    """
    try:
        # 通过os-release文件检测
        with open('/etc/os-release', 'r') as f:
            content = f.read().lower()
            if 'debian' in content and '12' in content:
                return True
        
        # 通过debian_version文件检测
        if os.path.exists('/etc/debian_version'):
            with open('/etc/debian_version', 'r') as f:
                version = f.read().strip()
                if version.startswith('12'):
                    return True
    except Exception:
        pass
    
    return False

def install_dependencies():
    """安装基础依赖包(curl和wget)"""
    if not detect_distro():
        log("❌ 不支持的系统(仅支持Debian 12)", "red")
        return False
    
    log("📦 安装基础依赖(curl, wget)...", "blue")
    
    # Debian专用安装命令
    install_cmd = 'apt-get -qq update && apt-get install -qq  -y --no-install-recommends curl wget git'
    
    try:
        result = run(install_cmd, check=False, realtime=True)
        if result.returncode == 0:
            log("✨ 依赖安装完成", "green")
            return True
        else:
            log(f"❌ 依赖安装失败 (返回码: {result.returncode})", "red")
            return False
    except Exception as e:
        log(f"💥 安装依赖时出错: {str(e)}", "red")
        return False

def install_speedtest():
    """安装speedtest测速工具"""
    log("📶 开始安装speedtest...", "cyan")
    result = run("""
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash &&
    apt-get install -qq  -y speedtest
    """, realtime=True)
    
    if run("speedtest --version").returncode == 0:
        log("✅ speedtest安装成功", "green")
        return True
    else:
        log("❌ speedtest安装失败", "red")
        return False

def install_btop():
    """安装btop资源监控工具"""
    log("📊 开始安装btop...", "cyan")
    
    # 安装编译依赖
    run("""
    apt-get install -qq  -y coreutils sed git build-essential gcc-11 g++-11 lowdown || 
    apt-get install -qq  -y coreutils sed git build-essential gcc g++ lowdown
    """, realtime=True)
    
    # 编译安装btop
    result = run("""
    cd /tmp &&
    git clone https://github.com/aristocratos/btop.git &&
    cd btop &&
    make &&
    make install
    """, realtime=True)
    
    if run("btop --version").returncode == 0:
        log("✅ btop安装成功", "green")
        return True
    else:
        log("❌ btop安装失败", "red")
        return False

def install_neovim():
    """安装最新版neovim(官方预编译包)"""
    log("✏️ 开始安装最新版neovim...", "cyan")
    
    install_cmd = """
    apt update &&
    apt install gcc -y &&
    cd /tmp && \
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz && \
    mkdir -p nvim-tmp && \
    tar -xzf nvim-linux-x86_64.tar.gz -C nvim-tmp && \
    cp -r nvim-tmp/nvim-linux-x86_64/bin/* /usr/bin/ && \
    cp -r nvim-tmp/nvim-linux-x86_64/lib/* /usr/lib/ && \
    cp -r nvim-tmp/nvim-linux-x86_64/share/* /usr/share/ && \
    rm -rf nvim-tmp nvim-linux-x86_64.tar.gz
    """

    try:
        # 执行安装命令链
        result = run(install_cmd, check=True, realtime=True)
        
        # 验证安装
        if run("nvim --version").returncode == 0:
            log("✅ neovim安装成功", "green")
            install_lazyvim()
            return True
        raise Exception("安装验证失败")

    except subprocess.CalledProcessError as e:
        log(f"❌ neovim安装失败（错误码：{e.returncode}）", "red")
        # 清理残留文件
        run("cd /tmp && rm -rf nvim-tmp nvim-linux-x86_64.tar.gz", realtime=True)
        return False
    except Exception as e:
        log(f"❌ {str(e)}", "red")
        return False

def install_lazyvim():
    """为neovim安装LazyVim插件管理器"""
    log("✨ 配置LazyVim插件...", "cyan")
    
    # 备份现有配置
    run("""
    mv ~/.config/nvim{,.bak} 2>/dev/null || true &&
    mv ~/.local/share/nvim{,.bak} 2>/dev/null || true &&
    mv ~/.local/state/nvim{,.bak} 2>/dev/null || true &&
    mv ~/.cache/nvim{,.bak} 2>/dev/null || true
    """)
    
    # 安装LazyVim starter
    result = run("""
    git clone https://github.com/LazyVim/starter ~/.config/nvim &&
    rm -rf ~/.config/nvim/.git
    """, realtime=True)
    
    if result.returncode == 0:
        log("✅ LazyVim安装成功，首次运行请执行: nvim 并运行 :LazyHealth 检查", "green")
        return True
    else:
        log("❌ LazyVim安装失败", "red")
        return False

def install_nexttrace():
    """安装nexttrace网络诊断工具"""
    log("🌐 开始安装nexttrace...", "cyan")
    result = run("curl -sSL nxtrace.org/nt | bash", realtime=True)
    
    if run("nexttrace --version").returncode == 0:
        log("✅ nexttrace安装成功", "green")
        return True
    else:
        log("❌ nexttrace安装失败", "red")
        return False

def install_debian12():
    """安装Debian 12系统"""
    log("\n🌊 准备安装 Debian 12 系统", "magenta")
    password = input("🔑 设置root密码: ").strip()
    
    if not password:
        log("❌ 密码不能为空", "red")
        return False
    
    script_url = "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
    install_cmd = (
        f"bash <(curl -sL {script_url} || wget -qO- {script_url}) "
        f"debian 12 --password {quote(password)}"
    )
    
    log("🔄 开始安装 Debian 12 (可能需要5-20分钟)...", "green")
    result = run(install_cmd, realtime=True)
    
    if result.returncode == 0:
        log("🎉 Debian 12 安装成功", "green")
        return True
    else:
        log(f"❌ Debian 12 安装失败 (返回码: {result.returncode})", "red")
        return False

def install_alpine():
    """安装Alpine系统"""
    log("\n🏔️ 准备安装 Alpine 系统", "magenta")
    password = input("🔑 设置root密码: ").strip()
    
    if not password:
        log("❌ 密码不能为空", "red")
        return False
    
    script_url = "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
    install_cmd = (
        f"bash <(curl -sL {script_url} || wget -qO- {script_url}) "
        f"alpine 3.21 --password {quote(password)}"
    )
    
    log("🔄 开始安装 Alpine (可能需要5-20分钟)...", "green")
    result = run(install_cmd, realtime=True)
    
    if result.returncode == 0:
        log("🎉 Alpine 安装成功", "green")
        return True
    else:
        log(f"❌ Alpine 安装失败 (返回码: {result.returncode})", "red")
        return False

def config_shell():
    """配置Shell环境"""
    try:
        run("timedatectl set-timezone Asia/Shanghai ", check=True)
        home_dir = os.path.expanduser("~")
        current_shell = os.environ.get('SHELL', '')
        
        # 配置内容增强唯一性标识
        config_marker = "# === AUTO CONFIGURED BY SCRIPT ===\n"
        config_content = f"""
{config_marker}
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=10000
export HISTIGNORE="pwd:ls:exit"
export EDITOR="nvim"
alias ll="ls -lh --color=auto"
alias la="ls -lha --color=auto"
alias cls="clear"
alias grep="grep --color=auto"
alias ..="cd .."
alias df="df -h"
alias du="du -h"
"""
        # 检测nvim
        if run("command -v nvim", verbose=False).returncode == 0:
            config_content += 'alias vim="nvim"\n'

        # 确定配置文件
        config_files = []
        if 'zsh' in current_shell:
            config_files.append(f"{home_dir}/.zshrc")
        elif 'bash' in current_shell:
            config_files.append(f"{home_dir}/.bashrc")
        else:
            log(f"⚠️ 不支持的Shell类型: {current_shell}", "yellow")
            return False

        for rc_file in config_files:
            if not os.path.exists(rc_file):
                log(f"ℹ️ 配置文件不存在: {rc_file}，跳过配置", "yellow")
                continue

            # 生成唯一备份文件名
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
            backup_file = f"{rc_file}.bak.{timestamp}"
            run(f"cp {rc_file} {backup_file}", check=True)
            log(f"🔒 创建备份文件: {backup_file}", "blue")

            # 检查是否已配置
            with open(rc_file) as f:
                if config_marker in f.read():
                    log(f"⏩ 检测到已有配置: {rc_file}", "yellow")
                    continue

            # 追加配置（使用原子操作）
            tmp_file = f"{rc_file}.tmp"
            with open(tmp_file, "w") as f_out:
                with open(rc_file) as f_in:
                    f_out.write(f_in.read())
                f_out.write(config_content)
            
            os.replace(tmp_file, rc_file)
            log(f"✨ 更新配置文件: {rc_file}", "green")

        return True

    except (PermissionError, IOError) as e:
        log(f"❌ 文件操作失败: {str(e)}", "red")
        return False
    except Exception as e:
        log(f"💥 配置失败: {str(e)}", "red")
        return False
    
def install_zsh():
    """安装并配置zsh环境（包含常用插件）"""
    # 初始化备份路径变量
    backup_path = None
    try:
        # 内联定义所有配置参数
        powerlevel_repo = "https://github.com/romkatv/powerlevel10k.git"
        autosuggestions_repo = "https://github.com/zsh-users/zsh-autosuggestions.git"
        syntax_highlight_repo = "https://github.com/zsh-users/zsh-syntax-highlighting.git"
        
        home_dir = os.path.expanduser("~")
        log("🌀 开始安装zsh环境...", "cyan")
        zshrc_path = f"{home_dir}/.zshrc"
        
        # ========================
        # 1. 安装基础依赖
        # ========================
        run("apt-get update -qq && apt-get -qq install -y --no-install-recommends zsh git curl fonts-powerline", check=True)
        run(f"echo {subprocess.check_output(['which', 'zsh']).decode().strip()} | tee -a /etc/shells", check=True)
        run(f"echo {subprocess.check_output(['which', 'zsh']).decode().strip()}", check=True)

        # ========================
        # 2. 安装oh-my-zsh（保留现有配置）
        # ========================
        log("🔧 安装oh-my-zsh...", "blue")
        # 生成备份路径（无论原文件是否存在）
        backup_path = f"{zshrc_path}.bak.{int(time.time())}"
        # 备份原有.zshrc（如果存在）
        if os.path.exists(zshrc_path):
            run(f"cp {zshrc_path} {backup_path}", check=True)
            log(f"🔒 备份原有配置文件: {backup_path}", "blue")
        
        # 非交互式安装
        install_cmd = (
            "bash <(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"
        )
        run(install_cmd, check=True, realtime=True)

        # ========================
        # 3. 安装主题和插件
        # ========================
        # 安装powerlevel10k
        log("🎨 配置powerlevel10k主题...", "blue")
        p10k_dir = f"{home_dir}/.oh-my-zsh/custom/themes/powerlevel10k"
        run(f"git clone --depth=1 {powerlevel_repo} {p10k_dir}", check=True)

        # 安装插件
        log("🔌 安装zsh插件...", "blue")
        plugins_dir = f"{home_dir}/.oh-my-zsh/custom/plugins"
        run(f"git clone --depth=1 {autosuggestions_repo} {plugins_dir}/zsh-autosuggestions", check=True)
        run(f"git clone --depth=1 {syntax_highlight_repo} {plugins_dir}/zsh-syntax-highlighting", check=True)

        # ========================
        # 4. 智能修改.zshrc配置
        # ========================
        log("📝 配置.zshrc文件...", "blue")
        
        # 读取现有配置或创建新文件
        if not os.path.exists(zshrc_path):
            run(f"cp {home_dir}/.oh-my-zsh/templates/zshrc.zsh-template {zshrc_path}", check=True)

        # 使用sed修改关键配置
        run(f"sed -i 's/^ZSH_THEME=.*/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/' {zshrc_path}", check=True)
        run(f"sed -i 's/^plugins=(.*)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' {zshrc_path}", check=False)
        
        # 追加必要配置
        with open(zshrc_path, "a") as f:
            f.write("""
# === 自动生成配置 ===
# 优化历史记录配置
export HISTSIZE=100000
export HISTFILESIZE=100000
export SAVEHIST=100000

# 禁用自动更新检查
DISABLE_AUTO_UPDATE="true"

# 加载p10k配置
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
""")

        # ========================
        # 5. 设置默认shell为zsh
        # ========================
        log("🔧 设置默认shell为zsh...", "blue")
        
        # 获取当前用户信息
        current_user = os.environ.get('SUDO_USER') or os.environ.get('USER')
        zsh_path = subprocess.check_output(['which', 'zsh']).decode().strip()
        
        # 验证zsh路径
        if not zsh_path or not os.path.exists(zsh_path):
            raise Exception("找不到zsh可执行文件路径")

        # 检查当前默认shell
        current_shell = subprocess.check_output(
            ['grep', current_user, '/etc/passwd'],
            universal_newlines=True
        ).split(':')[-1].strip()
        
        if 'zsh' in current_shell:
            log("✅ zsh已经是当前用户的默认shell", "green")
        else:
            # 安全修改默认shell
            run(f"chsh -s {zsh_path} {current_user}", check=True)
            
            # 验证修改结果
            new_shell = subprocess.check_output(
                ['grep', current_user, '/etc/passwd'],
                universal_newlines=True
            ).split(':')[-1].strip()
            
            if zsh_path not in new_shell:
                raise Exception(f"修改默认shell失败，当前shell: {new_shell}")
            log("✅ 默认shell已成功修改为zsh", "green")

        log("✅ zsh环境安装完成，请重新登录使配置生效", "green")
        return True

    except subprocess.CalledProcessError as e:
        log(f"❌ zsh安装失败（错误码：{e.returncode}）", "red")
        # 恢复备份文件（如果存在）
        if backup_path and os.path.exists(backup_path):
            run(f"mv {backup_path} {zshrc_path}", check=False)
            log("🔄 已恢复.zshrc备份文件", "yellow")
        return False
    except Exception as e:
        log(f"💥 发生错误: {str(e)}", "red")
        # 恢复备份文件（如果存在）
        if backup_path and os.path.exists(backup_path):
            run(f"mv {backup_path} {zshrc_path}", check=False)
            log("🔄 已恢复.zshrc备份文件", "yellow")
        return False

def increase_swap(swap_size="1G"):
    """智能配置swap空间"""
    log("🔄 开始配置swap空间...", "cyan")
    swap_file = "/swapfile"
    
    def create_swapfile():
        """创建并启用新的swap文件"""
        log(f"🆕 创建新的swap文件: {swap_file}", "blue")
        cmds = [
            f"fallocate -l {swap_size} {swap_file}",
            f"chmod 600 {swap_file}",
            f"mkswap {swap_file}",
            f"swapon {swap_file}",
            f"echo '{swap_file} none swap sw 0 0' >> /etc/fstab"
        ]
        for cmd in cmds:
            result = run(cmd, check=False)
            if result.returncode != 0:
                raise Exception(f"创建swap文件失败: {cmd}")

    try:
        # 检测现有swap信息
        result = run("swapon --show=NAME,TYPE --noheadings", check=False)
        if result.returncode != 0 or not result.stdout.strip():
            log("ℹ️ 系统中未检测到swap文件", "yellow")
            create_swapfile()
            return True

        # 解析现有swap信息
        swap_info = result.stdout.split()
        swap_type = swap_info[1]
        existing_file = swap_info[0]

        if swap_type == "partition":
            log("⚠️ 检测到swap分区，将创建独立swap文件", "yellow")
            create_swapfile()
        elif swap_type == "file":
            log(f"🔄 调整现有swap文件: {existing_file}", "blue")
            tmp_file = "/swapfile.tmp"
            
            # 创建临时swap文件
            run(f"fallocate -l {swap_size} {tmp_file} && chmod 600 {tmp_file}", check=True)
            run(f"mkswap {tmp_file}", check=True)
            
            # 切换swap文件
            run(f"swapoff {existing_file}", check=True)
            run(f"swapon {tmp_file}", check=True)
            
            # 替换旧文件
            run(f"mv {tmp_file} {existing_file}", check=True)
            
            # 更新fstab
            with open("/etc/fstab", "r+") as f:
                content = f.read()
                new_entry = f"{existing_file} none swap sw 0 0"
                if existing_file not in content:
                    f.write(f"\n{new_entry}\n")
                elif new_entry not in content:
                    content = content.replace(existing_file, new_entry)
                    f.seek(0)
                    f.write(content)
                    f.truncate()

        # 验证配置
        check_result = run(f"swapon --show={existing_file} --noheadings")
        if check_result.returncode != 0:
            raise Exception("swap配置验证失败")
        
        log(f"✅ swap空间已成功配置为{swap_size}", "green")
        return True

    except Exception as e:
        # 清理临时文件
        run(f"swapoff {existing_file} 2>/dev/null; rm -f {swap_file} {tmp_file} 2>/dev/null")
        log(f"❌ swap配置失败: {str(e)}", "red")
        return False


def config_sshd():
    """配置SSH密钥登录"""
    try:
        log("🔐 开始配置SSH服务...", "cyan")
        sshd_config = "/etc/ssh/sshd_config"
        ssh_dir = os.path.expanduser("~/.ssh")
        key_path = os.path.join(ssh_dir, "id_ed25519")

        # ========================
        # 1. 安装openssh-server
        # ========================
        if not os.path.exists(sshd_config):
            log("ℹ️ 未检测到SSH服务，开始安装...", "blue")
            run("apt-get update -qq && apt-get install -qq  -y openssh-server", check=True)

        # ========================
        # 2. 生成随机端口并验证
        # ========================
        def is_port_available(port):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                return s.connect_ex(('localhost', port)) != 0

        port = random.randint(60000, 65535)
        while not is_port_available(port):
            port = random.randint(60000, 65535)
        log(f"🔧 生成随机SSH端口: {port}", "blue")

        # ========================
        # 3. 备份并修改配置文件
        # ========================
        # 创建带时间戳的备份
        backup_file = f"{sshd_config}.bak.{int(time.time())}"
        run(f"cp {sshd_config} {backup_file}", check=True)
        log(f"📦 创建配置文件备份: {backup_file}", "blue")

        # 使用sed直接修改配置
        config_commands = [
            f"sed -i 's/^#Port.*/Port {port}/' {sshd_config}",
            "sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' {sshd_config}",
            "sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' {sshd_config}",
            "sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' {sshd_config}",
            "sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' {sshd_config}",
            "echo 'AllowUsers root' >> {sshd_config}",
            "rm -rf /etc/ssh/sshd_config.d/*"
        ]
        for cmd in config_commands:
            run(cmd.format(sshd_config=sshd_config), check=True)

        # ========================
        # 4. 生成SSH密钥
        # ========================
        log("🔑 生成ED25519 SSH密钥对...", "blue")
        if not os.path.exists(ssh_dir):
            os.makedirs(ssh_dir, mode=0o700)
            
        run(f"ssh-keygen -t ed25519 -f {key_path} -N ''", check=True)
        
        # 验证密钥生成
        if not (os.path.exists(f"{key_path}") and os.path.exists(f"{key_path}.pub")):
            raise Exception("SSH密钥生成失败")

        # ========================
        # 5. 配置公钥认证
        # ========================
        authorized_keys = os.path.join(ssh_dir, "authorized_keys")
        with open(f"{key_path}.pub") as f:
            pubkey = f.read().strip()
            
        # 避免重复添加
        if not os.path.exists(authorized_keys) or pubkey not in open(authorized_keys).read():
            with open(authorized_keys, "a") as f:
                f.write(f"\n{pubkey}\n")
            os.chmod(authorized_keys, 0o600)
            log("🔐 公钥已添加到授权文件", "green")

        # ========================
        # 6. 验证并重启服务
        # ========================
        log("🔄 检查SSH配置...", "blue")
        run("sshd -t", check=True)
        
        log("♻️ 重启SSH服务...", "blue")
        run("systemctl restart sshd", check=True)
        
        # 验证服务状态
        status = run("systemctl is-active sshd", check=False)
        if "active" not in status.stdout:
            raise Exception("SSH服务启动失败")

        log("✅ SSH配置完成！重要提示：", "green")
        log(f"1. 请记录SSH端口号: {port}", "green")
        log(f"2. 私钥路径: {key_path}", "green")
        log("3. 请妥善保管私钥文件！", "green")
        return True

    except subprocess.CalledProcessError as e:
        log(f"❌ 配置失败（错误码：{e.returncode}）", "red")
        # 自动回滚配置
        if 'backup_file' in locals() and os.path.exists(backup_file):
            run(f"mv {backup_file} {sshd_config}")
            run("systemctl restart sshd")
            log("🔄 已恢复SSH配置备份", "yellow")
        return False
    except Exception as e:
        log(f"💥 发生错误: {str(e)}", "red")
        return False

def check_bbr_enabled():
    """检查BBR是否已启用"""
    try:
        # 检查拥塞控制算法
        congestion = run("sysctl net.ipv4.tcp_congestion_control", check=False, verbose=False)
        # 检查队列纪律
        qdisc = run("sysctl net.core.default_qdisc", check=False, verbose=False)
        return 'bbr' in congestion.stdout and 'fq' in qdisc.stdout
    except Exception as e:
        log(f"⚠️ BBR检查失败: {str(e)}", "yellow")
        return False

def enable_bbr():
    """启用BBR拥塞控制算法"""
    log("🚀 开始配置BBR网络加速", "cyan")
    
    # 检查当前是否已启用
    if check_bbr_enabled():
        log("✅ BBR已启用，无需配置", "green")
        return True
    
    log("🔧 检测到未启用BBR，开始配置...", "yellow")
    
    # 生成带时间戳的备份
    backup_file = f"/etc/sysctl.conf.bak.{int(time.time())}"
    try:
        # 备份原配置文件
        run(f"cp /etc/sysctl.conf {backup_file}", check=True)
        log(f"📦 创建配置文件备份: {backup_file}", "blue")
        
        # 添加BBR配置
        with open("/etc/sysctl.conf", "a") as f:
            f.write("\n# BBR Configuration\n")
            f.write("net.core.default_qdisc=fq\n")
            f.write("net.ipv4.tcp_congestion_control=bbr\n")
        
        # 应用配置
        result = run("sysctl -p", check=False, realtime=True)
        if result.returncode != 0:
            raise Exception("应用sysctl配置失败")
        
        # 二次验证
        if check_bbr_enabled():
            log("✅ BBR配置成功生效", "green")
            return True
            
        log("⚠️ 配置已添加但未生效，可能需要重启系统", "yellow")
        return False

    except Exception as e:
        # 出现错误时恢复备份
        run(f"mv {backup_file} /etc/sysctl.conf", check=False)
        log(f"❌ BBR配置失败: {str(e)}", "red")
        log("🔄 已恢复sysctl配置备份", "yellow")
        return False

def show_help():
    """显示帮助信息"""
    print("""\
✨ 系统安装与工具配置脚本 ✨

使用方法:
  ./install.py [选项] [系统类型/工具]

选项:
  -h, --help      显示此帮助信息

系统设置:
  sshd       配置SSH密钥登录
  bbr        开启BBR流控算法

系统类型:
  debian12       安装Debian 12系o
  alpine         安装Alpine系统

工具安装:
  speedtest      安装speedtest测速工具
  btop           安装btop资源监控工具
  neovim         安装neovim编辑器(含LazyVim)
  nexttrace      安装nexttrace网络诊断工具
  shell          配置Shell环境               # 新增选项
  swap           配置1G swap空间
  zsh            安装zsh

快捷命令：
  base          安装基础软件：speedtest btop neovim nexttrace swap zsh shell sshd bbr

示例:
  ./install.py debian12      # 安装Debian 12系统
  ./install.py btop neovim   # 安装btop和neovim
  ./install.py shell         # 仅配置Shell环境
  ./install.py swap         # 配置swap空间
  ./install.py swap=4G      # 配置4G swap
""")

def main():
    """主执行逻辑"""
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        show_help()
        return
    
    # 安装依赖
    if not install_dependencies():
        log("⚠️ 依赖安装失败，可能会影响后续操作", "yellow")
        if input("是否继续? (y/N) ").lower() != 'y':
            sys.exit(1)
    
    # 处理所有参数
    for arg in sys.argv[1:]:
        try:
            if arg == "debian12":
                install_debian12()
            elif arg == "alpine":
                install_alpine()
            elif arg == "base":
                enable_bbr()
                install_btop()
                install_speedtest()
                install_neovim()
                install_nexttrace()
                increase_swap("1G")
                install_zsh()
                config_shell()
                config_sshd()
            elif arg == "bbr":
                enable_bbr()
            elif arg == "sshd":
                config_sshd()
            elif arg == "zsh":
                install_zsh()
            elif arg.startswith("swap"):
                size = "1G"
                if "=" in arg:
                    size = arg.split("=")[1].upper()
                    if not size.endswith(("G", "M")):
                        log("❌ 无效的swap大小格式，示例：2G 或 512M", "red")
                        sys.exit(1)
                increase_swap(size)
            elif arg == "speedtest":
                install_speedtest()
            elif arg == "btop":
                install_btop()
            elif arg == "neovim":
                install_neovim()
            elif arg == "nexttrace":
                install_nexttrace()
            elif arg == "shell":           # 新增处理逻辑
                config_shell()
            elif arg in ('-h', '--help'):
                show_help()
            else:
                log(f"❌ 未知选项: {arg}", "red")
                show_help()
                sys.exit(1)
        except KeyboardInterrupt:
            log("\n🛑 操作被用户中断", "yellow")
            sys.exit(1)
        except Exception as e:
            log(f"💥 发生错误: {str(e)}", "red")
            sys.exit(1)

if __name__ == '__main__':
    main()
