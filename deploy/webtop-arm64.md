# webtop 部署（arm64：Apple Silicon Mac / arm64 Linux）

容器内运行 arm64 Linux 微信 + SunnyNet MITM，浏览器里浏览视频号并用注入的下载按钮下载。
本机实测环境：Apple Silicon Mac + Docker Desktop。

## 前提

| 项 | 要求 |
|---|---|
| Docker | Docker Desktop（Apple Silicon 原生跑 arm64 容器）或任意 arm64 Linux + Docker |
| Go | **≥ 1.24**（构建期在宿主编译下载器；Mac 默认装在 `/usr/local/go/bin`） |
| 微信 deb | **arm64** 版：官方 https://linux.weixin.qq.com/ 下载 `WeChatLinux_arm64.deb` |

## 构建（arm64 镜像）

```sh
cd <仓库目录>
git pull
export PATH="/Applications/Docker.app/Contents/Resources/bin:/usr/local/go/bin:$PATH"   # Mac

TARGETARCH=arm64 WECHAT_DEB=/path/to/WeChatLinux_arm64.deb IMAGE=wx_video_download:arm \
  bash build/build-webtop-image.sh
```

基础镜像 `lscr.io/linuxserver/webtop:ubuntu-xfce` 为多架构，Mac 上自动选 arm64 变体，可直接拉取。

## 启动容器

```sh
docker rm -f wx_download 2>/dev/null

IMAGE=wx_video_download:arm CONFIG_DIR=~/wx-webtop NETWORK=bridge WEB_PORT=3000 \
  PUID=1000 PGID=1000 \
  bash build/run-webtop-container.sh

open http://127.0.0.1:3000     # Linux 宿主用浏览器直接访问
```

- `CONFIG_DIR`：微信登录态、下载数据的持久化目录（下载文件在 `CONFIG_DIR/Downloads`）
- Mac 本机用 `NETWORK=bridge`；arm64 Linux 服务器要接入已有 docker 网络时传 `NETWORK=<网络名>`
- 要对外访问：nginx 反代 `wx_download:3000` + basic auth（需带 WebSocket Upgrade 头，参考 deploy/README.md 的 nginx 片段）

## 使用

1. 桌面里微信自动启动，扫码登录
2. 浏览公众号文章 / 视频号（内嵌浏览器可正常打开）
3. 视频号视频处有注入的「下载」按钮，点选画质下载
4. 文件落地：`CONFIG_DIR/Downloads/`

## 已固化的关键点（勿改）

| 项 | 原因 |
|---|---|
| `--shm-size 1g`（脚本默认） | 默认 64MB 共享内存导致微信内嵌浏览器（WeChatAppEx）渲染进程崩溃：白屏/闪退/视频放不出 |
| `PUID/PGID=1000`（非 root） | root 下 WeChatAppEx 拒绝启用沙箱 → 公众号文章/视频号全部打不开 |
| 构建 tags 含 `sqlite_only` | CGO_ENABLED=0 下 velo 框架按 `//go:build !sqlite_only` 选中 mattn cgo 桩，下载器启动即 database initialization failed。对齐作者 windows 构建路径的 tag 集合 |

## 故障速查

- 构建报 `exec format error` → 构建机架构与 TARGETARCH 不一致（脚本只支持在 arm64 宿主编 arm64；amd64 见 deploy/webtop-x86.md）
- 起容器报 `Unsupported TARGETARCH` → 用了未解锁的旧脚本，先 `git pull`
- 微信报"无法执行默认网络浏览器" → 检查容器是不是 root 在跑（`docker exec wx_download ps aux | head`），回非 root
- DB 报 `go-sqlite3 requires cgo` → 镜像构建时 tags 缺 `sqlite_only`，重新构建
