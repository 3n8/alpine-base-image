#!/bin/bash

set -e

ourScriptName="${BASH_SOURCE[-1]}"
ourScriptName=$(basename -- "${ourScriptName}")
ourAppName="${ourScriptName%.*}"

defaultLogLevel=info
defaultLogSizeMB=10
defaultLogPath="/tmp/logs"

LOG_LEVEL="${defaultLogLevel}"
LOG_SIZE="${defaultLogSizeMB}"
LOG_PATH="${defaultLogPath}"

function shlog() {
    local log_message_level="${1}"
    shift
    local log_message="$*"

    local log_level_numeric
    local log_entry
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    local log_level_debug=0
    local log_level_info=1
    local log_level_warn=2
    local log_level_error=3

    if [[ -z "${log_message_level}" ]]; then
        echo "[ERROR] ${timestamp} :: No log message level passed to log function"
        return 1
    fi

    if [[ -z "${log_message}" ]]; then
        echo "[ERROR] ${timestamp} :: No log message passed to log function"
        return 1
    fi

    mkdir -p "${LOG_PATH}"
    LOG_FILEPATH="${LOG_PATH}/${ourAppName}.log"

    case "${LOG_LEVEL,,}" in
        'debug') log_level_numeric=0 ;;
        'info') log_level_numeric=1 ;;
        'warn') log_level_numeric=2 ;;
        'error') log_level_numeric=3 ;;
        *) log_level_numeric=0 ;;
    esac

    if [[ ${log_message_level} -ge ${log_level_numeric} ]]; then
        case ${log_message_level} in
            "${log_level_debug}")
                log_entry="[DEBUG] ${timestamp} :: ${log_message}"
                ;;
            "${log_level_info}")
                log_entry="[INFO] ${timestamp} :: ${log_message}"
                ;;
            "${log_level_warn}")
                log_entry="[WARN] ${timestamp} :: ${log_message}"
                ;;
            "${log_level_error}")
                log_entry="[ERROR] ${timestamp} :: ${log_message}"
                ;;
            *)
                log_entry="[UNKNOWN] ${timestamp} :: ${log_message}"
                ;;
        esac

        echo "${log_entry}"
        rotate_log_file
        echo "${log_entry}" >> "${LOG_FILEPATH}"
    fi
}

function rotate_log_file() {
    local log_size_in_bytes=$((LOG_SIZE * 1024 * 1024))

    if [[ -f "${LOG_FILEPATH}" && $(stat -c%s "${LOG_FILEPATH}") -ge ${log_size_in_bytes} ]]; then
        for ((i=LOG_ROTATION-1; i>=1; i--)); do
            if [[ -f "${LOG_FILEPATH}.${i}" ]]; then
                mv "${LOG_FILEPATH}.${i}" "${LOG_FILEPATH}.$((i+1))"
            fi
        done
        mv "${LOG_FILEPATH}" "${LOG_FILEPATH}.1"
        touch "${LOG_FILEPATH}"
    fi
}

function symlink() {
    local src_path=""
    local dst_path=""
    local link_type=""

    while [ "$#" != "0" ]; do
        case "$1" in
            -sp|--src-path) src_path=$2; shift ;;
            -dp|--dst-path) dst_path=$2; shift ;;
            -lt|--link-type) link_type=$2; shift ;;
            *) echo "[WARN] Unrecognised argument '$1'"; return 1 ;;
        esac
        shift
    done

    if [[ -z "${src_path}" || -z "${dst_path}" || -z "${link_type}" ]]; then
        echo "[ERROR] Missing required arguments for symlink"
        return 1
    fi

    if [[ "${link_type}" == "softlink" ]]; then
        link_type="-s"
    elif [[ "${link_type}" == "hardlink" ]]; then
        link_type=""
    else
        echo "[ERROR] Unknown link type '${link_type}'"
        return 1
    fi

    src_path=$(echo "${src_path}" | sed 's:/*$::')
    dst_path=$(echo "${dst_path}" | sed 's:/*$::')

    if [[ -L "${dst_path}" ]]; then
        if [[ ! -e "${dst_path}" ]]; then
            rm -rf "${dst_path}"
        elif [[ "$(readlink -f "${dst_path}")" != "${src_path}" ]]; then
            rm -rf "${dst_path}"
        fi
    fi

    if [[ -f "${dst_path}" || -d "${dst_path}" ]]; then
        if ! test -n "$(find "${dst_path}" -maxdepth 0 -empty)" ; then
            if [[ -f "${dst_path}-backup" || -d "${dst_path}-backup" ]]; then
                rm -rf "${dst_path}-backup"
            fi
            mv "${dst_path}" "${dst_path}-backup"
        fi
    fi

    mkdir -p "$(dirname "${dst_path}")"
    mkdir -p "${src_path}"

    ln ${link_type} "${src_path}" "${dst_path}"

    if [[ -n "${PUID}" && -n "${PGID}" ]]; then
        chown -R "${PUID}":"${PGID}" "${src_path}" "${dst_path}"
    fi
}

function dos2unix() {
    local file_path=""
    while [ "$#" != "0" ]; do
        case "$1" in
            -fp|--file-path) file_path=$2; shift ;;
            *) echo "[WARN] Unrecognised argument '$1'"; return 1 ;;
        esac
        shift
    done

    if [[ -z "${file_path}" ]]; then
        echo "[ERROR] File path not specified"
        return 1
    fi

    if [ ! -f "${file_path}" ]; then
        echo "[ERROR] File path '${file_path}' does not exist"
        return 1
    fi

    sed -i $'s/\r$//' "${file_path}"
}

function trim() {
    local string="$1"
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    echo "${string}"
}

function process_env_var() {
    local var_name="$1"
    local default_value="$2"
    local required="$3"

    local current_value
    current_value=$(eval "echo \"\${${var_name}}\"" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    if [[ ! -z "${current_value}" ]]; then
        export "${var_name}=${current_value}"
        echo "[info] ${var_name} defined as '${current_value}'" | ts '%Y-%m-%d %H:%M:%.S'
    else
        if [[ "${required}" == "true" ]]; then
            echo "[error] ${var_name} not defined via -e ${var_name}), exiting script..." | ts '%Y-%m-%d %H:%M:%.S'
            exit 1
        else
            echo "[info] ${var_name} not defined (via -e ${var_name}), defaulting to '${default_value}'" | ts '%Y-%m-%d %H:%M:%.S'
            export "${var_name}=${default_value}"
        fi
    fi
}

function curl_with_retry() {
    local url="${1}"
    shift
    local max_retries="${1:-3}"
    local retry_delay="${2:-2}"
    shift 2

    local curl_args=("$@")
    local retry_count=0
    local result
    local exit_code

    while [[ "${retry_count}" -lt "${max_retries}" ]]; do
        result=$(curl "${curl_args[@]}" "${url}" 2>/dev/null)
        exit_code=$?

        if [[ "${exit_code}" -eq 0 ]]; then
            echo "${result}"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ ${retry_count} -lt ${max_retries} ]]; then
                sleep "${retry_delay}"
            fi
        fi
    done

    echo "[ERROR] Curl request to '${url}' failed after ${max_retries} attempts" >&2
    return 1
}

function get_vpn_adapter_name() {
    local vpn_adapter_names="${1:-tun.*|tap.*|wg.*}"
    echo "[info] Identifying VPN adapter name..." >&2
    local vpn_adapter_name
    vpn_adapter_name="$(ifconfig | grep 'mtu' | grep -P "${vpn_adapter_names}" | cut -d ':' -f1)"
    if [[ -z "${vpn_adapter_name}" ]]; then
        echo ""
        return 1
    else
        echo "${vpn_adapter_name}"
        return 0
    fi
}

function get_vpn_adapter_ip_address() {
    local vpn_adapter_name="${1}"
    if [[ -z "${vpn_adapter_name}" ]]; then
        echo ""
        return 1
    fi
    echo "[info] Identifying VPN adapter IP address..." >&2
    local vpn_adapter_ip_address
    vpn_adapter_ip_address="$(ifconfig "${vpn_adapter_name}" | grep 'inet ' | awk '{print $2}')"
    if [[ -z "${vpn_adapter_ip_address}" ]]; then
        echo ""
        return 1
    else
        echo "${vpn_adapter_ip_address}"
        return 0
    fi
}
