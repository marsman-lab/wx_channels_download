# syntax=docker/dockerfile:1
#
# 纯 server 模式镜像（无微信、无桌面、无 MITM 代理）。
# 适配「云端 + 元宝 cookie 解析视频号分享链接」场景。
#
# 构建：docker compose -f deploy/docker-compose.yml up -d --build
# arm64：docker buildx build --platform linux/arm64 -f deploy/Dockerfile -t wx-dl-server:local .
#
# 不需要本机装 Go：编译在下面的 golang 构建阶段里完成。

# ---- build stage ----
FROM golang:1.20-bullseye AS build
WORKDIR /src
COPY . .
ARG TARGETARCH=amd64
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -trimpath \
      -tags "embed_inject,embed_frontend_inject,sqlite_only" \
      -ldflags="-s -w -X main.Mode=release" \
      -o /out/wx_video_download .

# ---- runtime stage ----
FROM debian:stable-slim
# ca-certificates：调 yuanbao.tencent.com 和视频 CDN 必须；
# ffmpeg：仅 MP3 转码 / 直播录制需要，只下 mp4 可删掉省体积。
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/wx_video_download /app/wx_video_download
VOLUME ["/data"]
EXPOSE 2022
ENTRYPOINT ["/app/wx_video_download", "server"]
