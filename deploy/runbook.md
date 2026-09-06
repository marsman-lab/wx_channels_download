# 云端部署 Runbook（纯 server + 元宝 cookie，无微信）

从零到能用的完整步骤。前提：Linux 服务器已装 Docker + docker compose 插件，有现成的 nginx 容器。

> 快速参考见 `deploy/README.md`；本文是完整服务器部署手册。

## 0. 前置确认

```sh
docker --version && docker compose version    # 两个都要有
git --version
# 记下你 nginx 容器的名字
docker ps --format '{{.Names}}\t{{.Image}}' | grep nginx
```

> fork（`marsman-lab/wx_channels_download`）是 public，服务器上 HTTPS clone 不需要凭证。

## 1. 拉代码

```sh
cd /opt
git clone -b local https://github.com/marsman-lab/wx_channels_download.git wx-dl
cd wx-dl
git branch --show-current && ls deploy/      # 确认在 local 分支、有 deploy/
```

## 2. 填元宝 cookie

```sh
cp deploy/config.example.yaml deploy/config.yaml
vi deploy/config.yaml        # 把 cloudflare.sphCookie 填上整段 cookie（取法见文末附录）
```

最小配置（其余用默认）：
```yaml
cloudflare:
  sphCookie: "整段 Cookie 头"
```
> `deploy/config.yaml` 被 `.gitignore` 忽略，cookie 不会进版本库。

## 3. 构建并启动

```sh
docker compose -f deploy/docker-compose.yml up -d --build
```

> 国内构建已默认加速（goproxy.cn + 清华 apt 镜像 + BuildKit 缓存挂载）；慢或要换源见 **附录 B**。

首次会多阶段编译 Go（几分钟），之后只跑 `debian:stable-slim` 运行时。容器名 `wx-dl`，数据默认落宿主机 `/var/lib/wx-dl`（换路径加 `WX_DL_DATA_DIR=/xxx` 前缀）。

## 4. 服务自检（容器内）

```sh
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs --tail=50 wx-dl
docker compose -f deploy/docker-compose.yml exec wx-dl \
  /app/wx_video_download server status
```

`:2022` 没发布到宿主机，外面摸不到——正常。

## 5. 接入你现有的 nginx（basic auth + 反代）

### 5.1 把 nginx 容器接入 wx-net

`docker compose up` 已创建网络 `wx-net`：

```sh
docker network connect wx-net <你的nginx容器名>
docker exec <你的nginx容器名> getent hosts wx-dl    # 验证能解析
```

### 5.2 生成 htpasswd

```sh
docker run --rm --entrypoint htpasswd httpd:alpine -nbB wx '你设的密码' \
  > /path/to/nginx/conf/wx-dl.htpasswd
# 按你 nginx 的 volume 习惯挂进容器（如 /etc/nginx/wx-dl.htpasswd）
```

### 5.3 nginx location 配置

```nginx
server {
    listen 80;                       # 按你实际改 443 + ssl
    server_name your.domain;

    location / {
        auth_basic            "wx";
        auth_basic_user_file   /etc/nginx/wx-dl.htpasswd;

        proxy_pass http://wx-dl:2022;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;

        # /ws/v1/download_task、/ws/scraper 需要 WebSocket 升级
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";

        # 大文件 / Range 续传 / 直链播放
        proxy_set_header Range          $http_range;
        proxy_set_header Accept-Ranges   $http_accept_ranges;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        client_max_body_size 0;
    }
}
```

### 5.4 重载 nginx

```sh
docker exec <你的nginx容器名> nginx -t && \
docker exec <你的nginx容器名> nginx -s reload
```

> 若你 nginx 是 `network_mode: host`：把 compose 里 wx-dl 改成 `ports: ["127.0.0.1:2022:2022"]`，nginx 直接 `proxy_pass http://127.0.0.1:2022;`，省去挂网络。

## 6. 端到端验证（经 nginx）

```sh
curl -i https://your.domain/api/status                                # 应 401
curl -u wx:'你设的密码' https://your.domain/api/status                # 应返回 JSON
curl -u wx:'你设的密码' https://your.domain/api/scraper/platform/status  # 确认"视频号分享链接"可用
```

"分享链接"显示不可用/缺 cookie → 回第 2 步检查 `sphCookie` 是否填对/过期。

## 7. 触发下载

### 方式 A：MCP 一键（推荐）

`config.yaml` 已开 `mcp.enabled: true`。MCP endpoint = `https://your.domain/mcp`。用 Claude Code 连：
```sh
claude mcp add --transport http wx-dl https://your.domain/mcp \
  --header "Authorization: Basic $(echo -n 'wx:你设的密码' | base64)"
```
连上后调 `download_wxchannels_video` 工具传视频号分享链接，全流程自动。

### 方式 B：REST 两步

```sh
# 1) 解析分享链接
curl -u wx:'你设的密码' -X POST https://your.domain/api/scraper/fetch \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://weixin.qq.com/sph/xxxxx","id":"r1"}'

# 2) 轮询（status=finished 后取 output.result）
curl -u wx:'你设的密码' 'https://your.domain/api/scraper/job?id=r1'

# 3) 用解析结果建任务并自动启动
curl -u wx:'你设的密码' -X POST https://your.domain/api/v1/download_task/create \
  -H 'Content-Type: application/json' \
  -d '{"objects":[{"platform":"wxchannels","content":<上一步 output.result>,"build_from_fetch":true,"auto_start":true}]}'

# 列表/进度
curl -u wx:'你设的密码' 'https://your.domain/api/v1/download_task/list'
```

文件落到宿主机 `/var/lib/wx-dl/downloads/`，或经 `/api/file` 下载。

## 8. 日常运维

**更新到最新（你在 mac 上 push 后，服务器拉取重建）**：
```sh
cd /opt/wx-dl
git pull
docker compose -f deploy/docker-compose.yml up -d --build
```

**只改了 cookie，不用重建镜像**：
```sh
docker compose -f deploy/docker-compose.yml restart wx-dl
```

**看日志 / 进容器**：
```sh
docker compose -f deploy/docker-compose.yml logs -f wx-dl
docker compose -f deploy/docker-compose.yml exec wx-dl bash
```

**数据备份**：`/var/lib/wx-dl`（含 `data.db` + `downloads/`）整体备份。

## 速查表

| 项 | 值 |
|---|---|
| 代码 | `/opt/wx-dl`（branch `local`） |
| 容器 | `wx-dl`（debian-slim，纯 server，无微信/代理/证书） |
| 数据 | `/var/lib/wx-dl`（或 `WX_DL_DATA_DIR`） |
| 配置 | `/opt/wx-dl/deploy/config.yaml`（gitignored，填 sphCookie） |
| 内部端口 | `wx-dl:2022`（仅 wx-net，nginx 反代+basic auth） |
| MCP | `https://your.domain/mcp` |
| 不需要 | root/管理员、证书、系统代理、TUN、微信 |

---

## 附录 A：取元宝 cookie

代码（`pkg/scraper/wxchannels/client.go:100` `resolve_sph_cookie` → `pkg/cookies/persistent.go:34` `HeaderForDomain(".tencent.com")`）取的是 **`.tencent.com` 域的整段 Cookie 头**（所有未过期 cookie 拼成 `name1=val1; name2=val2; ...`），**不是某个单独的 key**。云端模式下你把这整段直接填进 `cloudflare.sphCookie`，代码原样作为 `Cookie` 请求头发给 `yuanbao.tencent.com`。

### 取法

1. 浏览器（Chrome/Edge）打开 https://yuanbao.tencent.com 并**登录**（建议小号）。
2. F12 → **Network** 标签 → 刷新页面。
3. 在请求列表里找任意一个发往 `yuanbao.tencent.com/api/...` 的请求（如 `get_parse_result`、`chat` 等都行）。
4. 点开 → **Request Headers** → 找到 `Cookie:` 这一行。
5. 复制 `Cookie:` 后面的**整串值**（`name1=val1; name2=val2; ...`，可能很长），原样粘进 `config.yaml` 的 `cloudflare.sphCookie`。

```
cloudflare:
  sphCookie: "p_skey=...; skey=...; ptcz=...; uin=...; ..."
```

### 注意

- **整段复制，不要只挑一个 key**。代码会把这串原样发送。
- 其中真正起鉴权作用的一般是腾讯 SSO 的会话 cookie（`p_skey`/`skey`/`ptcz`/`uin` 等），但你不用筛选——全部一起发最稳。
- **会过期**：失效后分享链接解析会报「缺少 yuanbao.tencent.com Cookie」，重新登录复制即可。
- **封号风险**：用私号在服务器侧反复调元宝解析接口有被封风险，建议小号（项目 `docs/releases/260817.md` 自己提醒过）。
- 代码里 `yuanbao.go` 还硬编码了一些设备指纹头（`t-userid`/`x-id`/`x-device-id`/`x-hy92`/`x-hy93`），这些不用你管，已内置；你只需提供 Cookie。

---

## 附录 B：国内构建加速

Dockerfile 默认已开国内加速，`docker compose up --build` 直接就是快的。慢或要换源时用 build-arg 覆盖。

### 默认值

- Go 模块代理：`GOPROXY=https://goproxy.cn,direct`（+ `GOSUMDB=off`，go.sum 已在仓库内）
- apt 镜像：`APT_MIRROR=mirrors.tuna.tsinghua.edu.cn`
- 模块/编译缓存：BuildKit cache mount（`/go/pkg/mod` + `/root/.cache/go-build`），跨构建复用

### 换源

`docker compose up --build` 不接受 `--build-arg`，要换源得先 `build` 再 `up`：

```sh
# apt 换阿里云
docker compose -f deploy/docker-compose.yml build --build-arg APT_MIRROR=mirrors.aliyun.com

# Go 代理换阿里云
docker compose -f deploy/docker-compose.yml build --build-arg GOPROXY=https://mirrors.aliyun.com/goproxy/,direct

# 两个一起
docker compose -f deploy/docker-compose.yml build \
  --build-arg APT_MIRROR=mirrors.aliyun.com \
  --build-arg GOPROXY=https://mirrors.aliyun.com/goproxy/,direct

# build 完再起
docker compose -f deploy/docker-compose.yml up -d
```

### 拉基础镜像慢（host 级，可选）

基础镜像（`golang`、`debian`）首次拉取慢，配 Docker daemon registry mirror。编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": ["https://xxxx.mirror.aliyuncs.com"]
}
```

然后 `sudo systemctl restart docker`。
> 公共 mirror（ustc 等）近年陆续受限；阿里云个人加速器地址需到 https://cr.console.aliyun.com 申请。基础镜像一旦缓存到本地，后续构建不重新拉。
