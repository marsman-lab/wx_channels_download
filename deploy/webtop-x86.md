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
