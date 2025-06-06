MAIN_CONFIG_VARS=(
    'UNIT'
    'UNIT_TEMPLATE'
    'UNIT_MANAGER'
    'UNIT_ENABLED'

    'BUILDER_USER'
    'BUILDER_IMAGE'
    'BUILDER_CONTAINER'
    'BUILDER_CONFIG'

    'MANAGE_SUBIDS'
    'STATIC_SUBUIDS[]'
    'STATIC_SUBGIDS[]'

    'ARCHIVES_PATH'
    'AUTO_UPDATE'
)

IMAGE_CONFIG_VARS=(
    'BASE_IMAGE'
    'IMAGE'
    'TAGS'
    'ANNOTATIONS[]'
)

CONTAINER_CONFIG_VARS=(
    'CONTAINER'
    'CONTAINER_USERNS'
    'CONTAINER_NETWORK'
    'CONTAINER_HOSTNAME'
    'CONTAINER_PUBLISH_PORTS[]'
)

APACHE_CONFIG_VARS=(
    'SITES[]'
    'SITES_ALIASES[]'
    'SITES_URLS[]'

    'DEFAULT_SITE_MODE'
    'DEFAULT_SITE_URL'
    'DEFAULT_SITE_SSL'

    'HOST_HTDOCS_PATH_PATTERN'
    'HOST_HTDOCS_PATHS[]'
    'HOST_DEFAULT_HTDOCS_PATH'

    'HOST_LOGS_PATH_PATTERN'
    'HOST_LOGS_PATHS[]'
    'HOST_DEFAULT_LOGS_PATH'

    'HOST_SSL_PATH_PATTERN'
    'HOST_SSL_PATHS[]'
    'HOST_DEFAULT_SSL_PATH'

    'HOST_PHP_FPM_PATH_PATTERN'
    'HOST_PHP_FPM_PATHS[]'

    'HOST_ACME_CHALLENGES_PATH'

    'HOST_UID_MAP[]'
    'HOST_GID_MAP[]'

    'APACHE_MODULES[]'
    'APACHE_CONFIGS[]'
)

source_config() {
    local __USER="$1"
    local __FILE="$2"
    shift 2

    local __UID="$(id -u -- "$__USER")"
    local __GID="$(id -g -- "$__USER")"

    if [ -z "$__UID" ] || [ -z "$__GID" ]; then
        echo "Invalid argument for \`source_config\`: Invalid user ${__USER@Q}: No such user" >&2
        return 1
    fi

    if [ ! -e "$__FILE" ]; then
        echo "Invalid argument for \`source_config\`: Invalid config file ${__FILE@Q}: No such file or directory" >&2
        return 1
    elif [ ! -f "$__FILE" ]; then
        echo "Invalid argument for \`source_config\`: Invalid config file ${__FILE@Q}: Not a file" >&2
        return 1
    elif [ ! -r "$__FILE" ]; then
        echo "Invalid argument for \`source_config\`: Invalid config file ${__FILE@Q}: Permission denied" >&2
        return 1
    elif [ "$(stat -c '%u:%g' "$__FILE")" != "$__UID:$__GID" ]; then
        echo "Invalid argument for \`source_config\`: Invalid config file ${__FILE@Q}: Invalid file ownership," \
            "expecting '$__UID:$__GID', got '$(stat -c '%u:%g' "$__FILE")'" >&2
        return 1
    fi

    local -a __ENV=()
    local -a __VARS=()
    while [ $# -gt 0 ]; do
        if [ "$1" == "--env" ]; then
            [[ "${2:-}" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?(\ ([a-zA-Z][a-zA-Z0-9_]*)(\[\])?)*$ ]] \
                || { echo "Invalid argument for \`source_config --env\`: ${2:-}" >&2; return 1; }

            local __ARG
            for __ARG in $2; do
                [[ "$__ARG" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?$ ]]
                __ENV+=( "$(declare -p "${BASH_REMATCH[1]}")" )
            done
            shift 2
        else
            [[ "$1" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?$ ]] \
                || { echo "Invalid argument for \`source_config\`: $1" >&2; return 1; }

            __VARS+=( "$1" )
            shift
        fi
    done

    __read_vars() {
        source /variables.sh

        local __ARG __VALUE
        for __ARG in "$@"; do
            [[ "$__ARG" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?$ ]] || continue

            if [ -v "${BASH_REMATCH[1]}" ]; then
                local -n __REF="${BASH_REMATCH[1]}"
                if [ -n "${BASH_REMATCH[2]}" ]; then
                    for __VALUE in "${__REF[@]}"; do
                        printf '%s=%s\0' "$__ARG" "$__VALUE"
                    done
                elif [ -n "$__REF" ]; then
                    printf '%s=%s\0' "$__ARG" "$__REF"
                fi
            fi
        done
    }

    __parse_vars() {
        local -a __VARS
        readarray -d '' -t __VARS

        local -a __RAW
        while [ $# -gt 0 ]; do
            [[ "$1" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?$ ]] || continue
            readarray -d '' -t __RAW < <(printf '%s\0' "${__VARS[@]}" \
                | sed -z -ne "s/^$(sed -e 's/[]\/$*.^[]/\\&/g' <<< "$1")=\(.*\)$/\1/p")

            if [ "${#__RAW[@]}" -gt 0 ] || [ ! -v "${BASH_REMATCH[1]}" ]; then
                if [ -n "${BASH_REMATCH[2]}" ]; then
                    local -n __REF="${BASH_REMATCH[1]}"
                    declare -g -a "${BASH_REMATCH[1]}"
                    __REF=( "${__RAW[@]}" )
                else
                    declare -g "${BASH_REMATCH[1]}"="${__RAW:-}"
                fi
            fi
            shift
        done
    }

    local -a __BWRAP_INVOC_OPTS=(
        --unshare-all
        --uid "$__UID"
        --gid "$__GID"
    )

    local -a __BWRAP_FS_OPTS=(
        --symlink usr/bin /bin
        --dev /dev
        --dir /etc
        --symlink usr/lib /lib
        --symlink usr/lib64 /lib64
        --proc /proc
        --symlink usr/sbin /sbin
        --dir /tmp
        --ro-bind /usr /usr
        --dir /var
        --symlink ../tmp var/tmp
    )

    local -a __BWRAP_ENV_OPTS=(
        --chdir /
        --clearenv
    )

    local -a __BWRAP_COMMAND=(
        "$(declare -f "__read_vars")"
        "${__ENV[@]}"
        '__read_vars "$@"'
    )

    __parse_vars "${__VARS[@]}" < <(bwrap \
        --die-with-parent \
        "${__BWRAP_INVOC_OPTS[@]}" \
        "${__BWRAP_FS_OPTS[@]}" \
        --file 11 /etc/passwd \
        --file 12 /etc/group \
        --file 13 /variables.sh \
        "${__BWRAP_ENV_OPTS[@]}" \
        /usr/bin/bash -c "$(printf '%s\n' "${__BWRAP_COMMAND[@]}")" _ "${__VARS[@]}" \
        11< <(getent passwd "$__UID" 65534) \
        12< <(getent group "$__GID" 65534) \
        13< <(cat "$__FILE"))
}
