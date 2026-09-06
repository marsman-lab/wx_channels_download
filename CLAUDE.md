# 本仓库

个人 fork of `ltaoo/wx_channels_download`（微信视频号下载器），托管于 `marsman-lab/wx_channels_download`。solo 维护，**不向上游提 PR**；目标：跟住上游 + 保留私有改动。

# Remotes 与分支（fork-and-rebase）

- `upstream` = `https://github.com/ltaoo/wx_channels_download.git`（原仓库，只读，仅拉更新）
- `origin` = `git@github.com:marsman-lab/wx_channels_download.git`（你的 fork，push 到这）
- `main` = `upstream/main` 的干净镜像，fast-forward only，**永不 commit**
- `local` = 开发主线，携带私有改动 + `deploy/` + 本文件，fork 默认分支，定期 rebase 到 `main`
- 不用 release/feature/hotfix 分支；大改动临时开 `topic/*` 再 squash 回 `local`
- `rerere` 已开（`git config rerere.enabled true`），重复冲突自动复用旧解

# 常用命令

- 同步上游（main 快进）：`git checkout main && git fetch upstream && git merge --ff-only upstream/main && git push origin main`
- 同步上游（local rebase）：`git checkout local && git rebase main && git push -f origin local`
- patch 体检：`git log upstream/main..local`（看自己有哪些私有改动；上游新增功能若让其变多余就 `git rebase -i` drop）
- 首次配置：`cp deploy/config.example.yaml deploy/config.yaml`（真实 `config.yaml` 被 gitignore）
- 构建（从 local）：`docker compose -f deploy/docker-compose.yml up -d --build`
- 换数据路径：`WX_DL_DATA_DIR=/your/path docker compose -f deploy/docker-compose.yml up -d`

# 提交规范

- 前缀：`local:`（私有源码补丁）/ `deploy:`（部署文件）/ `docs:`（文档）/ `chore:`（杂项）
- **优先扩展点，不改上游 .go**：下载名/完成动作用 `download.hooksScript`；页面 JS/UI 用 `inject.globalScript`/`inject.contentScript`；平台私有配置用插件 config（`channels.*`/`mp.*`，见 `internal/config/plugin.go`）；私有构建变体用 build tag
- **保持加法**：能新增文件实现的别改上游已跟踪文件（当前 `local` 相对 `upstream/main` 是纯新增，维持）
- 原子提交，一个 commit 一个 concern；message 写"为什么 + 上游什么功能出现后可删"
- 不提交 `deploy/config.yaml`（含 cookie）；配置改动只改 `deploy/config.example.yaml`

# 项目速记

- Go 1.20；入口 `main.go` → cobra（`cmd/`）
- 运行态：裸执行=本地 MITM（需微信+根证书+管理员）；`server`=云端无头 API（关代理/证书）；`mcp`=MCP stdio
- 视频号两条下载路径：本地 MITM（不需 cookie）/ 分享链接（需 `cloudflare.sphCookie` 调 `yuanbao.tencent.com`）；**云端只能走分享链接**
- 解密=ISAAC64 异或文件前 128KB，种子=`decode_key`（`pkg/scraper/wxchannels/decrypt.go`）
- 元宝 cookie 从 `yuanbao.tencent.com` 浏览器 F12 复制 Cookie 头；会过期，私号有封号风险，用小号
- **API 零鉴权**（`internal/api/middleware.go` 只有 CORS）→ 绝不暴露 `:2022` 到公网，必须 nginx+basic auth 或防火墙
- 核心层（api/services/adapter/hermes/flowengine）几乎无测试，改动靠类型/编译兜底
- 部署细节见 `deploy/README.md`

# 禁忌

- 不在 `main` 上 commit；不对 `main` force-push；不 push 到 `upstream`
- 不向原仓库提 PR
- 不提交 `deploy/config.yaml`（含真实 cookie）；`config.yaml` 填了 cookie 后不 `git add -A`
- 不把 `:2022` 直接暴露公网

> 私人备忘写 `CLAUDE.local.md`（untracked，不入库，Claude Code 也会加载）。
