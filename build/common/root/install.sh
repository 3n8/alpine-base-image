#!/bin/bash

set -e

echo "[info] Setting up Alpine base image..."

echo "[info] Installing additional packages for locale..."
apk add --no-cache musl-locales

echo "[info] Setting locale..."
export LC_ALL=en_GB.UTF-8
export LANG=en_GB.UTF-8

echo "en_GB.UTF-8" > /etc/locale.conf

echo "[info] Creating user 'nobody' and group 'users'..."
getent group users > /dev/null 2>&1 || groupadd -g 100 users
id nobody > /dev/null 2>&1 || useradd -u 99 -g users -G nobody -d /home/nobody -s /bin/bash nobody

echo "[info] Setting shell for nobody..."
chsh -s /bin/bash nobody

echo "[info] Creating directory structure..."
mkdir -p /usr/local/bin/system
mkdir -p /usr/local/bin/run/scripts
mkdir -p /usr/local/bin/run/configs
mkdir -p /usr/local/bin/run/utils
mkdir -p /config
mkdir -p /data
mkdir -p /etc/supervisor/conf.d

echo "[info] Setting permissions..."
chown -R nobody:users /usr/local/bin/run
chmod -R 775 /usr/local/bin/run
chown -R nobody:users /home/nobody 2>/dev/null || true
chmod -R 775 /home/nobody 2>/dev/null || true

echo "[info] Cleaning up..."
rm -rf /var/cache/apk/*
rm -rf /tmp/*

echo "[info] Alpine base image setup complete"
