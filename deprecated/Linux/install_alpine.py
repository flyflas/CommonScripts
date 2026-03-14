#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import random
import subprocess
import sys
from datetime import datetime


def run(command, check=False, verbose=True, realtime=False):
    """执行shell命令（BusyBox优化版）"""
    if verbose:
        log(f"执行命令: {command}", "blue")

    shell_env = {
        "SHELL": "/bin/sh",
        "PATH": os.environ.get("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    }

    if realtime:
        process = subprocess.Popen(
            command,
            shell=True,
            env=shell_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        while True:
            output = process.stdout.readline()
            if not output and process.poll() is not None:
                break
            if output:
                print(output.strip())

        returncode = process.poll()
        result = subprocess.CompletedProcess(
            command, returncode, '', ''
        )
    else:
        result = subprocess.run(
            command,
            shell=True,
            env=shell_env,
            capture_output=True,
            text=True
        )

    if check and result.returncode != 0:
        if not realtime:
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
    """打印带颜色的日志消息"""
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
    """检测Alpine系统"""
    return os.path.exists('/etc/alpine-release')


def install_dependencies():
    """安装基础依赖"""
    if not detect_distro():
        log("❌ 不支持的系统（仅限Alpine）", "red")
        return False

    log("📦 安装基础依赖...", "blue")
    try:
        run("apk add --no-cache git", check=True)
        run("echo '' > /etc/motd", check=True)
        log("✅ 依赖安装完成", "green")
        return True
    except subprocess.CalledProcessError as e:
        log(f"❌ 依赖安装失败（代码：{e.returncode}）", "red")
        return False


def install_speedtest():
    """安装speedtest测速工具"""
    log("📶 安装speedtest...", "cyan")
    try:
        cmd = """
        wget -q -O /tmp/speedtest.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz &&
        tar -xzf /tmp/speedtest.tgz -C /tmp &&
        install -v -m 755 /tmp/speedtest /usr/local/bin/ &&
        rm -rf /tmp/speedtest*
        """
        run(cmd, check=True)
        log("✅ speedtest安装成功", "green")
        return True
    except Exception as e:
        log(f"❌ 安装失败：{str(e)}", "red")
        return False


def install_btop():
    """安装btop监控工具"""
    log("📊 安装btop...", "cyan")
    try:
        run("apk add --no-cache btop", check=True)
        log("✅ btop安装成功", "green")
        return True
    except subprocess.CalledProcessError:
        log("❌ btop安装失败", "red")
        return False


def install_neovim():
    """安装Neovim编辑器"""
    log("✏️ 安装Neovim...", "cyan")
    try:
        run("apk add --no-cache neovim", check=True)
        log("✅ Neovim安装成功", "green")
        return True
    except subprocess.CalledProcessError:
        log("❌ Neovim安装失败", "red")
        return False


def install_nexttrace():
    """安装nexttrace网络诊断工具"""
    log("🌐 开始安装nexttrace...", "cyan")
    cmd = """
    wget -q -O /tmp/nexttrace "https://dl-r2.nxtrace.org/dist/core/v1.3.7/nexttrace_linux_amd64" &&
    install -v -m 755 /tmp/nexttrace /usr/local/bin
    """

    run(cmd, check=True)

    if run("nexttrace --version").returncode == 0:
        log("✅ nexttrace安装成功", "green")
        return True
    else:
        log("❌ nexttrace安装失败", "red")
        return False


def config_shell():
    """配置Shell环境"""
    try:
        # 设置时区
        run("ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime", check=True)

        # 生成配置文件内容
        config = """\
# === AUTO CONFIGURED ===
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=10000
alias ll="ls -lh --color=auto"
alias la="ls -lha --color=auto"
alias cls="clear"
alias grep="grep --color=auto"
alias ..="cd .."
alias df="df -h"
alias du="du -h"
"""

        # 检测并添加nvim别名
        if run("command -v nvim", check=False).returncode == 0:
            config += "alias vim='nvim'\n"
            config += "export EDITOR='nvim'\n"

        # 写入配置文件
        rc_file = os.path.expanduser("~/.profile")
        if os.path.exists(rc_file):
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
            run(f"cp {rc_file} {rc_file}.bak.{timestamp}", check=True)

        with open(rc_file, "a") as f:
            f.write(config)

        log("✅ Shell配置完成", "green")
        return True
    except Exception as e:
        log(f"❌ 配置失败：{str(e)}", "red")
        return False


def increase_swap(size="1G"):
    """配置Swap空间"""
    log(f"🔄 配置{size} Swap...", "cyan")
    swap_file = "/swapfile"

    try:
        # 转换大小
        unit = size[-1].upper()
        num = int(size[:-1])
        mb_size = num * 1024 if unit == 'G' else num

        # 创建Swap文件
        cmds = [
            f"dd if=/dev/zero of={swap_file} bs=1M count={mb_size}",
            f"chmod 0600 {swap_file}",
            f"mkswap {swap_file}",
            f"swapon {swap_file}",
            f"echo '{swap_file} none swap defaults 0 0' >> /etc/fstab",
            f"rc-update add swap"
        ]

        for cmd in cmds:
            run(cmd, check=True)

        log("✅ Swap配置成功", "green")
        return True
    except Exception as e:
        log(f"❌ 配置失败：{str(e)}", "red")
        run(f"rm -f {swap_file}", check=False)
        return False


def config_sshd():
    log("🔐 配置SSH...", "cyan")
    try:
        while True:
            port = random.randint(60000, 65500)
            if run(f"netstat -ltn | grep -q :{port}", check=False).returncode != 0:
                break

        # 修改配置
        cmds = [
            f"sed -i 's/^#Port.*/Port {port}/' /etc/ssh/sshd_config",
            "sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
            "sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
            "sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
            "sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
            'echo "KbdInteractiveAuthentication no " >> /etc/ssh/sshd_config',
        ]
        for cmd in cmds:
            run(cmd, check=True)

        # 生成密钥
        key_path = "/root/.ssh/id_ed25519"
        if not os.path.exists(key_path):
            run(f"ssh-keygen -t ed25519 -f {key_path} -N ''", check=True)
            run(f"cat {key_path}.pub >> /root/.ssh/authorized_keys", check=True)
            run("chmod 600 /root/.ssh/authorized_keys", check=True)

        # 管理服务
        run("rc-update add sshd default", check=True)
        run("rc-service sshd restart", check=True)

        log(f"✅ SSH配置完成！端口：{port}", "green")
        return True
    except Exception as e:
        log(f"❌ 配置失败：{str(e)}", "red")
        return False


def enable_bbr():
    """启用BBR加速"""
    log("🚀 启用BBR...", "cyan")
    try:
        with open("/etc/sysctl.conf", "a") as f:
            f.write("\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n")

        run("sysctl -p", check=True)
        log("✅ BBR已启用", "green")
        return True
    except Exception as e:
        log(f"❌ 启用失败：{str(e)}", "red")
        return False


def install_singbox():
    """安装Sing-Box"""
    log("🛡️ 安装Sing-Box...", "cyan")
    try:
        run("apk add sing-box --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing --allow-untrusted", check=True)
        run("rc-update add sing-box default", check=True)
        run('(crontab -l 2>/dev/null; echo "0 3 * * * /sbin/rc-service sing-box restart") | crontab -', check=True)
        log("✅ Sing-Box安装成功", "green")
        return True
    except Exception as e:
        log(f"❌ 安装失败：{str(e)}", "red")
        return False


def show_help():
    """显示帮助信息"""
    print("""\
✨ Alpine系统配置工具 ✨

使用方法:
  ./install.py [选项] [功能...]

功能列表:
  base        基础组件: speedtest btop neovim nexttrace swap shell sshd bbr
  speedtest   网速测试工具
  btop        资源监控工具
  neovim      现代文本编辑器
  nexttrace   网络路径追踪工具
  shell       优化Shell配置
  swap=大小   配置Swap空间 (示例: swap=2G)
  sshd        配置SSH服务
  bbr         启用BBR加速
  singbox     安装Sing-Box代理工具

示例:
  ./install.py base          # 安装基础组件
  ./install.py swap=2G       # 配置2G Swap
  ./install.py sshd singbox  # 配置SSH并安装SingBox
""")


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        show_help()
        return

    # 安装依赖
    if not install_dependencies():
        if input("继续执行？(y/N) ").lower() != 'y':
            return

    # 处理参数
    for arg in sys.argv[1:]:
        try:
            if arg == "base":
                enable_bbr()
                install_btop()
                install_speedtest()
                install_neovim()
                install_nexttrace()
                increase_swap("1G")
                config_shell()
                config_sshd()
            elif arg.startswith("swap="):
                size = arg.split('=')[1].upper()
                increase_swap(size)
            elif arg == "sshd":
                config_sshd()
            elif arg == "bbr":
                enable_bbr()
            elif arg == "singbox":
                install_singbox()
            elif arg in ('speedtest', 'btop', 'neovim', 'nexttrace', 'shell'):
                globals()[f"install_{arg}"]() if arg != 'shell' else config_shell()
            else:
                log(f"❌ 无效参数：{arg}", "red")
                show_help()
                sys.exit(1)
        except KeyboardInterrupt:
            log("\n操作已取消", "yellow")
            sys.exit(1)
        except Exception as e:
            log(f"💥 错误：{str(e)}", "red")
            sys.exit(1)


if __name__ == '__main__':
    main()
