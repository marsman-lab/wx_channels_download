#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ghcr.io/ltaoo/wx_video_download:v260607}"
NAME="${NAME:-wx_download}"
CONFIG_DIR="${CONFIG_DIR:-/var/lib/wx-dl/webtop}"
WEB_PORT="${WEB_PORT:-3000}"
NETWORK="${NETWORK:-shared_net}"
CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-wx-linux}"
TZ_VALUE="${TZ:-Asia/Shanghai}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
# 非 root(1000) 运行：微信内嵌浏览器内核(WeChatAppEx)在 root 下拒绝启用沙箱，
# 表现为公众号文章/视频号打不开。上游默认 1000 即为此。
PUID_VALUE="${PUID:-1000}"
PGID_VALUE="${PGID:-1000}"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "Container already exists: $NAME" >&2
    echo "Use NAME=another_name or remove the existing container first." >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR" 2>/dev/null || {
    echo "无法创建 $CONFIG_DIR（权限不足）。用 sudo 预建并 chown 给 PUID 对应用户，或改用 CONFIG_DIR= 指定可写目录。" >&2
    exit 1
}

run_args=(
    run
    -d
    --name "$NAME"
    --network "$NETWORK"
    --shm-size "${SHM_SIZE:-1g}"
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
