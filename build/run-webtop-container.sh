#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ghcr.io/ltaoo/wx_video_download:v260607}"
NAME="${NAME:-wx_download}"
CONFIG_DIR="${CONFIG_DIR:-/var/lib/wx-dl/webtop}"
WEB_PORT="${WEB_PORT:-3000}"
CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-wx-linux}"
TZ_VALUE="${TZ:-Asia/Shanghai}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
# 默认用 root(0/0) 运行：容器内 abc 以 root 身份工作，任意 CONFIG_DIR 都可写，
# 无需手动 mkdir/对齐宿主 uid。需要非 root 时用 PUID/PGID 显式覆盖。
PUID_VALUE="${PUID:-0}"
PGID_VALUE="${PGID:-0}"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "Container already exists: $NAME" >&2
    echo "Use NAME=another_name or remove the existing container first." >&2
    exit 1
fi

run_args=(
    run
    -d
    --name "$NAME"
    --restart=unless-stopped
    --hostname "$CONTAINER_HOSTNAME"
    --security-opt seccomp=unconfined
    --cap-add=NET_ADMIN
    --device /dev/net/tun
    -e "PUID=${PUID_VALUE}"
    -e "PGID=${PGID_VALUE}"
    -e "TZ=${TZ_VALUE}"
    -e "RESOLUTION=${RESOLUTION}"
    -e "WX_VIDEO_AUTOSTART=${WX_VIDEO_AUTOSTART:-true}"
    -e "WECHAT_AUTOSTART=${WECHAT_AUTOSTART:-true}"
    -p "${WEB_PORT}:3000"
    -v "${CONFIG_DIR}:/config"
)

run_args+=("$IMAGE")

container_id="$(docker "${run_args[@]}")"
echo "Started ${NAME}: ${container_id}"
echo "Web desktop: http://127.0.0.1:${WEB_PORT}"
echo "Config volume: ${CONFIG_DIR}"
