# Changelog

本文件记录个人 fork（`local` 分支）相对上游的功能与修复变更，按日期倒序。
格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## 2026-09-08

### Fixed

- **webtop 构建链路回归上游作者原版**，仅同步上游新版 `build/build-go.sh`
  的跨架构修复（作者已自行修复 `go run buildgo` 继承 GOOS/GOARCH 导致
  交叉构建时 exec format error 的问题；fork 的旧快照缺少该修复）。
  至此 webtop 构建脚本、Dockerfile 与上游零差异（0241163、c3586d4）
- **webtop 构建 tags 对齐作者其它 CGO=0 构建路径**，补
  `embed_inject,sqlite_only`：CGO_ENABLED=0 下 velo 框架按
  `//go:build !sqlite_only` 选中 mattn/go-sqlite3 的 cgo 桩，下载器启动即
  `database initialization failed`（服务器与 Mac 双端复现后定位）
  （c338aef）
- **webtop 构建恢复 TARGETARCH=amd64 支持**：守卫接受 arm64|amd64、deb
  复制名去架构化，x86 服务器可构建原生可跑的 amd64 镜像（bde66f7）
- **run-webtop-container.sh 回滚 root 默认**：恢复非 root（PUID/PGID=1000）
  运行与 `mkdir -p`。root 下微信内嵌浏览器内核（WeChatAppEx）拒绝启用
  沙箱，表现为公众号文章/视频号全部打不开（cbe5636）

### Changed

- `run-webtop-container.sh`：CONFIG_DIR 默认值恢复上游语义（`/config`）；
  NETWORK 恢复默认不挂网、改为可选参数（显式传 `NETWORK=xxx` 才接入）
  （c042ae2）
- 保留 `--shm-size 1g` 默认值：容器默认 64MB 共享内存导致 WeChatAppEx
  渲染进程崩溃（白屏/闪退/视频放不出），实测必需（579fa47 引入，保留）

### Removed

- webtop 容器实验性修复（tun MTU 常驻循环、QUIC/UDP 443 拦截、chromium
  .desktop 补丁）：实测均非必需，回滚使镜像行为回归上游（312204f）
- webtop 构建的中途方案（宿主 go 直接交叉编译、BASE_IMAGE 参数化、
  华为云基础镜像硬编码）：被上游 build-go.sh 修复取代，一并回滚（0241163）

### Added

- `deploy/webtop-arm64.md`、`deploy/webtop-x86.md`：webtop 双架构
  （arm64 / x86_64）部署文档，含前提、构建/启动命令、固化关键点与故障
  速查（de06070）

## 2026-09-07

### Fixed

- **bilibili BV 下载 403**：网页 REST / MCP 的 `build_from_fetch` 建任务
  路径拿不到页面 URL，下载端点 Referer 为空被 B 站 CDN 拒绝；改为
  source_url 为空时从 VideoInfo 反推 `https://www.bilibili.com/video/<bvid>`
  兜底，覆盖全部建任务入口（bdcf262）
- **bilibili 下载无声**：B 站 DASH 音视频分离为两个文件；为 bilibili
  adapter 实现 `Postprocessor`，下载完成后用 `ffmpeg -c copy` 把音轨合并
  进视频、删除音频资源，任务交付单个含音轨的 mp4。ffmpeg 缺失/失败仅
  告警并保留两文件（5049285）
- webtop 构建（首次引入，次日调整，最终形态见 2026-09-08）：补
  `sqlite_only` tag 修 CGO=0 下 go-sqlite3 桩导致下载器 DB 起不来
  （07cdf69）、amd64 构建支持（c5a3dda）、同步上游 build-go.sh 前的临时
  方案（f6be086，次日回滚）

### Added

- 配置项 `bilibili.dashMerge`（默认开启）控制上述合并行为，文档见
  `deploy/config.example.yaml`（008cc3d）

### Changed

- `deploy/docker-compose.yml` 网络从自建 `wx-net` 改为共享外部网络
  `shared_net`，对齐服务器实际部署；README/runbook 同步（215bbf8、d0eb45f）
- Go 工具链统一 1.27（`deploy/Dockerfile`），go.mod `go` 指令抬至 1.24
  （依赖 tklauser/go-sysconf 要求 go>=1.24）（2cdd61a）
- webtop run 脚本与构建脚本的多轮默认值调整（root 默认、CONFIG_DIR、
  shared_net 等中间状态，均于次日回滚定稿，见 2026-09-08）
