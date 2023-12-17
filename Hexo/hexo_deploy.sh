#!/usr/bin/env bash

# title: Hexo 部署脚本
# function: 当github指定仓库的分支更新的时候，Server自动拉取，并且编译代码
#

WORK_DIR="/opt/GithubWebHook"
GITHUB_SSH_TIMEOUT=5
SSH_LOG=$(mktemp)
trap 'rm -rf "${SSH_LOG}"' EXIT

while [[ "$is_ready" != "y" ]] && [[ "$is_ready" != "n" ]]; do
    read -r -p "您是否已经准备好Github访问秘钥(y/n): " is_ready
done

if [[ "$is_ready" == "n" ]]; then
    echo "请先准备好Github访问秘钥，在执行本脚本!!!"
    exit 1
fi

read -r -p "请输入Github私钥路径(默认为: ~/.ssh/github): " key_path
key_path=${key_path:-"${HOME}/.ssh/github"}

if ! [[ -e "$key_path" ]]; then
    echo "秘钥文件不存在!!!"
fi

chmod 600 "$key_path"

while [[ "$is_write_to_config" != "y" ]] && [[ "$is_write_to_config" != "n" ]]; do
    read -r -p "是否写入到SSH Config文件(如果你已经配置好了Config文件，则选n)(y/n):" is_write_to_config
done

if [[ "$is_write_to_config" == "y" ]]; then
    cat >>"$HOME/.ssh/config" <<EOF
Host flyflas.github.com
  HostName github.com
  AddKeysToAgent yes
  IdentityFile ${key_path}
EOF
fi

# 测试 github 秘钥有效性
ssh -T git@flyflas.github.com >"$SSH_LOG" 2>&1 &
ssh_pid=$!
while ((GITHUB_SSH_TIMEOUT > 0)); do
    printf "\r正在测试秘钥(${key_path})有效性，请稍后...   %d  \t" "$GITHUB_SSH_TIMEOUT"

    sleep 1
    ((GITHUB_SSH_TIMEOUT--))
done

echo ""

if ps -p "$ssh_pid" >/dev/null; then
    kill "$ssh_pid"
fi

if grep "successfully" "$SSH_LOG"; then
    echo "GITHUB 认证成功"
else
    echo "秘钥错误，无法访问仓库!!!!"
    exit
fi

# 安装NodeJS
apt-get update &&
    apt-get install -y ca-certificates curl gnupg &&
    mkdir -p /etc/apt/keyrings &&
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

apt-get update &&
    apt-get install nodejs -y

if npm --version; then
    echo ""
    echo "NodeJS 安装成功"
    echo ""
else
    echo ""
    echo "NodeJS 安装失败!!!"
    echo ""
    exit 1
fi

# 安装 Hexo、pm2
npm install pm2 -g
npm install hexo -g

if ! [[ -e "$WORK_DIR" ]]; then
    mkdir "$WORK_DIR"
fi

# 部署 WebHookServer
cd "$WORK_DIR" &&
    cat >webhooks.js <<'EOF'
const http = require('http')
const createHandler = require('github-webhook-handler');

// 这里的port、path、passwd 需要更改
const port = RandomPort
const path = RandomPath
const passwd = RandomPasswd
const handler = createHandler({ path: path, secret: passwd })

function run_cmd(cmd, args, callback) {
  const spawn = require('child_process').spawn;
  const child = spawn(cmd, args);
  let resp = "";

  child.stdout.on('data', function (buffer) { resp += buffer.toString(); });
  child.stderr.on('data', function (data) {
    console.log('stderr: ' + data);
  });
  child.stdout.on('end', function () { callback(resp) });
}

http.createServer(function (req, res) {

  handler(req, res, function (err) {
    res.statusCode = 404
    res.end('403 Forbidden')
  })
}).listen(port, () => {
  console.log(`${new Date().toLocaleString()} --- WebHooks Listen at ${port}`);
})

handler.on('push', function (event) {
  console.log(`${new Date().toLocaleString()} --- Received a push event for ${event.payload.repository.name} to ${event.payload.ref}`)
    

  // 注意在这里更改 branch
  if (event.payload.ref === 'refs/heads/cdn') {
    console.log(`${new Date().toLocaleString()} --- Deploy Hexo.....`)
    run_cmd('bash', ['./deploy.sh'], function (text) { console.log(text) });
  }
})
EOF

cat >package.json <<EOF
{
  "name": "webhook",
  "version": "1.0.0",
  "main": "webhooks.js",
  "scripts": {
    "start": "node webhooks.js"
  },
  "license": "GPLV3",
  "dependencies": {
    "github-webhook-handler": "^1.0.0"
  }
}
EOF

cat >deploy.sh <<EOF
#!/usr/bin/env bash

DIR="path"

cd "$DIR" &&
git pull &&
hexo clean &&
hexo g
EOF

read -r -p "请输入网站根目录: " web_dir
read -r -p "请输入Server的监听端口: " server_port
read -r -p "请输入Server的监听路径(例如：/demo): " server_path
passwd=$(cat /proc/sys/kernel/random/uuid)

sed -i "s#RandomPort#${server_port}#" webhooks.js
sed -i "s#RandomPath#${server_path}#" webhooks.js
sed -i "s#RandomPasswd#${passwd}#" webhooks.js
sed -i "s#path#${web_dir}#" deploy.sh

# cat "$key_path" >"$HOME/.ssh/hexo" &&
#     cat >>"$HOME/.ssh/config" <<EOF
# Host flyflas.github.com
#   HostName github.com
#   AddKeysToAgent yes
#   IdentityFile ~/.ssh/hexo
# EOF

cd "$web_dir" &&
    git clone -b cdn git@flyflas.github.com:flyflas/Hexo.git &&
    cd "$web_dir/Hexo" &&
    hexo g &&
    cd "$WORK_DIR" &&
    npm i &&
    pm2 start webhooks.js
