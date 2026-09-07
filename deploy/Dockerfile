# syntax=docker/dockerfile:1
#
# 纯 server 模式镜像（无微信、无桌面、无 MITM 代理）。
# 构建：docker compose -f deploy/docker-compose.yml up -d --build
#
# 国内构建加速（默认开启，可用 build-arg 覆盖）：
#   - Go 模块代理：GOPROXY=https://goproxy.cn,direct （+ GOSUMDB=off，go.sum 已在仓库内，安全）
#   - apt 镜像：APT_MIRROR=mirrors.tuna.tsinghua.edu.cn
#   - go mod / 编译缓存跨构建复用（BuildKit cache mount）
# 不需要本机装 Go：编译在下面的 golang 构建阶段里完成。
# 如还要加速基础镜像拉取，配 Docker daemon registry mirror（见 deploy/runbook.md）。

# ---- build stage ----
FROM golang:1.27-bullseye AS build
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY} GOSUMDB=off
WORKDIR /src
COPY . .
ARG TARGETARCH=amd64
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -trimpath \
      -tags "embed_inject,embed_frontend_inject,sqlite_only" \
      -ldflags="-s -w -X main.Mode=release" \
      -o /out/wx_video_download .

# ---- runtime stage ----
FROM debian:stable-slim
# 切国内 apt 镜像（清华），兼容 sources.list 与 debian.sources(DEB822) 两种格式
ARG APT_MIRROR=mirrors.tuna.tsinghua.edu.cn
RUN sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null \
    ; apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/wx_video_download /app/wx_video_download
VOLUME ["/data"]
EXPOSE 2022
ENTRYPOINT ["/app/wx_video_download", "server"]
