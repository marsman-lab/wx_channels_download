#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ghcr.io/ltaoo/wx_video_download:v260607}"
NAME="${NAME:-wx_download}"
CONFIG_DIR="${CONFIG_DIR:-/config}"
WEB_PORT="${WEB_PORT:-3000}"
CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-wx-linux}"
TZ_VALUE="${TZ:-Asia/Shanghai}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
# 默认跟随调用用户，而不是写死 1000：容器内 abc(uid 1000) 需要能写 CONFIG_DIR，
# 而 CONFIG_DIR 通常落在调用者自己的目录，所以用当前用户的 uid/gid 才写得进去。
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
PUID_VALUE="${PUID:-${CURRENT_UID}}"
PGID_VALUE="${PGID:-${CURRENT_GID}}"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "Container already exists: $NAME" >&2
    echo "Use NAME=another_name or remove the existing container first." >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR"

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
