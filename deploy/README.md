# 纯 server 模式云端部署（无微信，元宝 cookie 解析视频号分享链接）

适用场景：云服务器上跑下载器，不装微信、不开 MITM 代理，靠你提供的元宝 cookie 解析视频号分享链接，下载 + 解密都在云端完成。

## 1. 起服务

首次使用前，从模板复制一份本地配置（真实 `config.yaml` 被 `.gitignore` 忽略，不会进版本库，填了 cookie 也安全）：

```sh
cp deploy/config.example.yaml deploy/config.yaml
```

数据（数据库 + 下载文件）默认落在宿主机 `/var/lib/wx-dl`（脱离项目目录，因此无需改 `.dockerignore`）。换路径用 `WX_DL_DATA_DIR` 前缀：

```sh
docker compose -f deploy/docker-compose.yml up -d --build
# 或换路径：WX_DL_DATA_DIR=/data/wx-dl docker compose -f deploy/docker-compose.yml up -d --build
```

- 日志：`docker compose -f deploy/docker-compose.yml logs -f wx-dl`
- 状态：`docker compose -f deploy/docker-compose.yml exec wx-dl /app/wx_video_download server status`
- server 模式不需要 `--cap-add=NET_ADMIN`、不需要 `/dev/net/tun`、不需要 root。

## 2. 接入你现有的 nginx（basic auth）

`wx-dl` 不对外发布端口，只在 docker 网络 `wx-net` 内可达。

### 把 nginx 容器加入 wx-net

- nginx 由另一个 compose 管 → 在那个 compose 里：
  ```yaml
  services:
    nginx:
      networks: [default, wx-net]
  networks:
    wx-net: { external: true }
  ```
- 或临时连接：`docker network connect wx-net <你的nginx容器名>`

### nginx 配置片段

```nginx
location / {
    auth_basic           "wx";
    auth_basic_user_file  /etc/nginx/.htpasswd;   # 挂载你生成的 htpasswd

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
```

### 生成 htpasswd

```sh
docker run --rm --entrypoint htpasswd httpd:alpine -nbm wx '你设的密码' \
  > /path/to/nginx/conf/.htpasswd
# 把生成的 .htpasswd 挂进 nginx 的 /etc/nginx/.htpasswd（用 -m apr1 MD5；别用 -B bcrypt，nginx 多不支持，会 500）
```

> 你的 nginx 若是 `network_mode: host`：把 compose 里 wx-dl 改成 `ports: ["127.0.0.1:2022:2022"]`，nginx 直接 `proxy_pass http://127.0.0.1:2022;`，省去挂网络。

## 3. 填元宝 cookie

编辑 `deploy/config.yaml`（上一步从 `config.example.yaml` 复制而来），把 `cloudflare.sphCookie` 填上整段 cookie，然后：

```sh
docker compose -f deploy/docker-compose.yml restart wx-dl
```

cookie 会过期，失效后分享链接解析会报「缺少 yuanbao.tencent.com Cookie」；用私号有封号风险，建议小号。

## 4. 触发下载

### 方式 A：MCP 一键（推荐）

`config.yaml` 已开 `mcp.enabled: true`。MCP endpoint = `http://<host>/mcp`（经 nginx 鉴权后）。用 Claude Code 连上，调 `download_wxchannels_video` 工具传分享链接即可，全流程自动（解析 → 下载 → 解密）。

### 方式 B：REST 两步

```sh
# 第 1 步：解析分享链接
curl -u wx:你的密码 -X POST http://<host>/api/scraper/fetch \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://weixin.qq.com/sph/xxxxx","id":"r1"}'

# 第 2 步：轮询拿到结果（status=finished 后取 output.result）
curl -u wx:你的密码 'http://<host>/api/scraper/job?id=r1'

# 第 3 步：用解析结果建任务并启动
curl -u wx:你的密码 -X POST http://<host>/api/v1/download_task/create \
  -H 'Content-Type: application/json' \
  -d '{"objects":[{"platform":"wxchannels","content":<上一步 output.result>,"build_from_fetch":true,"auto_start":true}]}'
```

文件落到 `/var/lib/wx-dl/downloads/`（或你设的 `WX_DL_DATA_DIR`），从宿主机直接取，或经 `/api/file` 下载。

## 文件说明

| 文件 | 作用 |
|---|---|
| `Dockerfile` | 多阶段构建：golang:1.20 编译（CGO=0 + sqlite_only，纯静态）→ debian:stable-slim 运行 |
| `docker-compose.yml` | 只起 wx-dl，不发布端口，挂 wx-net；数据走宿主机绝对路径（`WX_DL_DATA_DIR`，默认 `/var/lib/wx-dl`） |
| `config.example.yaml` | 配置**模板**（监听地址、下载目录、数据库、元宝 cookie 等）；复制为 `config.yaml` 后填写真实 cookie，后者被 .gitignore 忽略、不进版本库 |

## 跟进上游（fork 工作流）

本目录在你 fork 的 `local` 分支上，**全部为 `deploy/` 下新增文件，未改动上游任何已跟踪文件** → rebase 上游时零冲突。同步上游：

```sh
git checkout main && git fetch upstream && git merge --ff-only upstream/main && git push origin main
git checkout local && git rebase main && git push -f origin local
```
