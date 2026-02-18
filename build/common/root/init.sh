#!/bin/bash

set -e

exec 3>&1 4>&2 &> >(tee -a /config/supervisord.log)

source '/usr/local/bin/system/scripts/docker/utils.sh'

cat << "EOF"
Created by...
___.   .__       .__
\_ |__ |__| ____ |  |__   ____ ___  ___
 | __ \|  |/    \|  |  \_/ __ \\  \/  /
 | \_\ \  |   |  \   Y  \  ___/ >    <
 |___  /__|___|  /___|  /\___  >__/\_ \
     \/        \/     \/     \/      \/
   https://hub.docker.com/u/binhex/

EOF

source '/etc/image-build-info'

if [[ "${HOST_OS,,}" == "unraid" ]]; then
    echo "[info] Host is running unRAID" | ts '%Y-%m-%d %H:%M:%.S'
fi

echo "[info] System information: $(uname -a)" | ts '%Y-%m-%d %H:%M:%.S'

echo "[info] Image architecture: '${TARGETARCH}'" | ts '%Y-%m-%d %H:%M:%.S'

echo "[info] Base image release tag: '${BASE_RELEASE_TAG}'" | ts '%Y-%m-%d %H:%M:%.S'

export PUID=$(echo "${PUID}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${PUID}" ]]; then
    echo "[info] PUID defined as '${PUID}'" | ts '%Y-%m-%d %H:%M:%.S'
else
    echo "[warn] PUID not defined (via -e PUID), defaulting to '1050'" | ts '%Y-%m-%d %H:%M:%.S'
    export PUID="1050"
fi

sed -i 's/^passwd:.*/passwd: files/' /etc/nsswitch.conf
sed -i 's/^group:.*/group: files/' /etc/nsswitch.conf

current_uid=$(id -u nobody 2>/dev/null || echo "99999")
if [[ "${current_uid}" != "${PUID}" ]]; then
    echo "[info] Executing usermod for PUID '${PUID}'..." | ts '%Y-%m-%d %H:%M:%.S'
    usermod -o -u "${PUID}" nobody 2>/dev/null || true
    echo "[info] usermod completed successfully" | ts '%Y-%m-%d %H:%M:%.S'
else
    echo "[info] User 'nobody' already has UID '${PUID}', skipping usermod" | ts '%Y-%m-%d %H:%M:%.S'
fi

export PGID=$(echo "${PGID}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${PGID}" ]]; then
    echo "[info] PGID defined as '${PGID}'" | ts '%Y-%m-%d %H:%M:%.S'
else
    echo "[warn] PGID not defined (via -e PGID), defaulting to '1050'" | ts '%Y-%m-%d %H:%M:%.S'
    export PGID="1050"
fi

current_gid=$(getent group users 2>/dev/null | cut -d: -f3 || echo "100")
if [[ "${current_gid}" != "${PGID}" ]]; then
    echo "[info] Executing groupmod for PGID '${PGID}'..." | ts '%Y-%m-%d %H:%M:%.S'
    groupmod -o -g "${PGID}" users 2>/dev/null || true
    echo "[info] groupmod completed successfully" | ts '%Y-%m-%d %H:%M:%.S'
else
    echo "[info] Group 'users' already has GID '${PGID}', skipping groupmod" | ts '%Y-%m-%d %H:%M:%.S'
fi

if [[ ! -z "${UMASK}" ]]; then
    echo "[info] UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
    sed -i -e "s~umask.*~umask = ${UMASK}~g" /etc/supervisor/conf.d/*.conf 2>/dev/null || true
else
    echo "[warn] UMASK not defined (via -e UMASK), defaulting to '000'" | ts '%Y-%m-%d %H:%M:%.S'
    sed -i -e "s~umask.*~umask = 000~g" /etc/supervisor/conf.d/*.conf 2>/dev/null || true
fi

if [[ ! -f "/config/perms.txt" ]]; then
    if [[ -d "/config" ]]; then
        echo "[info] Setting ownership and permissions recursively on '/config'..." | ts '%Y-%m-%d %H:%M:%.S'
        set +e
        chown -R "${PUID}":"${PGID}" "/config" 2>/dev/null
        exit_code_chown=$?
        chmod -R 775 "/config" 2>/dev/null
        exit_code_chmod=$?
        set -e

        if (( exit_code_chown != 0 || exit_code_chmod != 0 )); then
            echo "[warn] Unable to chown/chmod '/config', assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[info] Successfully set ownership and permissions on '/config'" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[info] '/config' directory does not exist, skipping" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    if [[ -d "/data" ]]; then
        echo "[info] Setting ownership and permissions non-recursively on '/data'..." | ts '%Y-%m-%d %H:%M:%.S'
        set +e
        chown "${PUID}":"${PGID}" "/data" 2>/dev/null
        exit_code_chown=$?
        chmod 775 "/data" 2>/dev/null
        exit_code_chmod=$?
        set -e

        if (( exit_code_chown != 0 || exit_code_chmod != 0 )); then
            echo "[info] Unable to chown/chmod '/data', assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[info] Successfully set ownership and permissions on '/data'" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[info] '/data' directory does not exist, skipping" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    echo "This file prevents ownership and permissions from being applied/re-applied to '/config' and '/data'" > /config/perms.txt 2>/dev/null || true
else
    echo "[info] Permissions file '/config/perms.txt' exists, skipping" | ts '%Y-%m-%d %H:%M:%.S'
fi

disk_usage_tmp=$(du -s /tmp 2>/dev/null | awk '{print $1}' || echo "0")
if [ "${disk_usage_tmp}" -gt 1073741824 ]; then
    echo "[warn] /tmp directory contains 1GB+ of data, skipping clear down" | ts '%Y-%m-%d %H:%M:%.S'
    ls -al /tmp 2>/dev/null || true
else
    echo "[info] Deleting files in /tmp (non recursive)..." | ts '%Y-%m-%d %H:%M:%.S'
    rm -f /tmp/* > /dev/null 2>&1 || true
fi

echo "[info] Starting Supervisor..." | ts '%Y-%m-%d %H:%M:%.S'

exec 1>&3 2>&4

exec /usr/bin/supervisord -c /etc/supervisord.conf -n
