# webtop 部署（x86_64 云服务器）

在 x86_64 Linux 服务器上构建并运行 webtop（amd64 镜像 + x86_64 微信），
通过已有 nginx（basic auth）对外访问。本机实测环境：Ubuntu 22.04 + Docker。

## 前提

| 项 | 要求 |
|---|---|
| Docker | 已安装（legacy builder 或 buildx 均可） |
| Go | **≥ 1.24**（构建期在服务器宿主编译下载器） |
| 微信 deb | **x86_64** 版：官方 https://linux.weixin.qq.com/ 下载 `WeChatLinux_x86_64.deb` |
| 网络 | 可拉取基础镜像（见下），或能访问 lscr.io |

## 基础镜像（服务器拉不动 lscr.io 时）

```sh
docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/lscr.io/linuxserver/webtop:ubuntu-xfce
docker tag swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/lscr.io/linuxserver/webtop:ubuntu-xfce \
           lscr.io/linuxserver/webtop:ubuntu-xfce
```

服务器能直连 lscr.io 则跳过此步。注意 Dockerfile 的 FROM 是写死的
`lscr.io/linuxserver/webtop:ubuntu-xfce`，重打 tag 即可让本地构建命中。

## 构建（amd64 镜像）

```sh
cd <仓库目录>
git pull
go version   # 需 >= 1.24

TARGETARCH=amd64 WECHAT_DEB=/path/to/WeChatLinux_x86_64.deb IMAGE=wx_video_download:x86 \
  bash build/build-webtop-image.sh
```

- 服务器上 host==target（linux/amd64），无跨机问题
- `TARGETARCH` 与 deb 架构必须一致（arm64 deb 配 amd64 构建会在安装步报 exec format error）

## 启动容器

```sh
# 若之前用 root 跑过，先修数据属主（微信登录态保留）
sudo chown -R 1000:1000 /var/lib/wx-dl/webtop

docker rm -f wx_download 2>/dev/null

IMAGE=wx_video_download:x86 CONFIG_DIR=/var/lib/wx-dl/webtop NETWORK=shared_net WEB_PORT=3000 \
  PUID=1000 PGID=1000 \
  bash build/run-webtop-container.sh
```

- `NETWORK=shared_net`：接入宿主机共享网络（由 docker-network-init.service 预建），nginx 按容器名访问；没有该网络就去掉此参数并改用 `-p` 端口映射
- 对外访问：nginx 反代 `wx_download:3000` + basic auth（需带 WebSocket Upgrade 头），参考 deploy/README.md 的 nginx 片段

## 使用

同 deploy/webtop-arm64.md 的「使用」一节：微信登录 → 浏览公众号/视频号 → 点注入的下载按钮 → 文件落地 `CONFIG_DIR/Downloads/`。

## 分享链接 API（可选）：与 server 版能力对齐

webtop 容器与 server 版是同一二进制，2022 端口的 REST API 同样注册。
配置元宝 cookie 后，分享链接解析（`/api/scraper/fetch`）即可用——已实测
全链路：fetch → create → 下载完成 → `/api/file` 取回本地。

### 配置元宝 cookie

```sh
# 从云端 server 的配置（挂载在 /var/lib/wx-dl/config.yaml）取 cookie
COOKIE=$(grep 'sphCookie:' /var/lib/wx-dl/config.yaml | head -1 | sed 's/.*sphCookie: *"//; s/".*//')

# 写入 webtop 容器的运行时配置（种子模板里 cloudflare.sphCookie 默认为空）
sudo sed -i "s|sphCookie: \"\"|sphCookie: \"$COOKIE\"|" /var/lib/wx-dl/webtop/wx_video_download/config.yaml

# 重启下载器（微信不用动；config 启动时读取）
docker exec wx_download bash -c 'pkill -f wx_video_download; sleep 2'
docker exec -d wx_download /usr/local/bin/wx-start-downloader
```

### 通过 nginx 暴露 REST（`/wxapi/` 前缀，basic auth 后）

webtop 的 server 块里加（`/wxapi/` 前缀避免与 KasmVNC 桌面路由冲突）：

```nginx
    location /wxapi/ {
        proxy_pass http://wx_download:2022/;     # 末尾斜杠 = 去掉 /wxapi 前缀
        proxy_set_header Host $host;
    }
```

### 已实测的 REST 链路（2026-09-08）

```sh
BASE=https://wx.ihuloo.com/wxapi   # 换成你的域名

# 1. 分享链接解析
curl -u wx:*** -X POST $BASE/api/scraper/fetch -H 'Content-Type: application/json' \
  -d '{"url":"https://weixin.qq.com/sph/xxxx","id":"t1"}'
curl -u wx:*** $BASE/api/scraper/job?id=t1        # 轮询至 completed

# 2. 建任务（content 用上一步 output.result，build_from_fetch=true）
curl -u wx:*** -X POST $BASE/api/v1/download_task/create -H 'Content-Type: application/json' \
  -d '{"objects":[{"platform":"wxchannels","content":<result>,"build_from_fetch":true,
       "auto_start":true,"config":{"existing_action":"duplicate"}}]}'

# 3. 进度与文件
curl -u wx:*** "$BASE/api/v1/download_task/detail?id=<id>"   # files[].file_path, status=5 为完成
curl -u wx:*** -G --data-urlencode "path=<file_path>" $BASE/api/file -o video.mp4
```

> **维护提醒**：元宝 cookie 会过期，server 与 webtop **两处各存一份**，
> 失效时需同时更新（见 deploy/config.example.yaml 的获取说明；私号有封号风险，用小号）。

## 已固化的关键点（勿改）

与 arm64 相同的三条（shm 1g、非 root、构建 tags 含 `sqlite_only`），原因见
deploy/webtop-arm64.md。另有一条 x86 特有：

- **deb 架构必须与 TARGETARCH 一致**：arm64 deb 装进 amd64 镜像会在
  `apt-get install` 步报架构不匹配

## 故障速查

- 构建报 `Only TARGETARCH=arm64 is supported` → 脚本未更新到支持 amd64 的版本，先 `git pull`
- Docker build 报 `exec format error`（平台不匹配 Warning）→ TARGETARCH 用了 arm64，服务器上应使用 `TARGETARCH=amd64`
- DB 报 `go-sqlite3 requires cgo` → 镜像构建时 tags 缺 `sqlite_only`，重新构建
- 微信报"无法执行默认网络浏览器" → 容器在用 root 跑，回 PUID=1000 并 chown 数据目录
