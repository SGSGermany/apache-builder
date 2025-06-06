# unit config
UNIT="${UNIT:-}"

if [ -z "$UNIT_TEMPLATE" ]; then
    if [ -n "$CONFIG" ] && [ -e "$CONFIG_DIR/$CONFIG.container" ]; then
        UNIT_TEMPLATE="$CONFIG_DIR/$CONFIG.container"
    elif [ -e "$CONFIG_DIR/apache.container" ]; then
        UNIT_TEMPLATE="$CONFIG_DIR/apache.container"
    else
        UNIT_TEMPLATE="$LIB_DIR/default-apache.container"
    fi
fi
check_path "Invalid config file ${CONFIG_FILE@Q}: Invalid unit template" "$UNIT_TEMPLATE" -e -f -r

UNIT_MANAGER="$(id -un -- "${UNIT_MANAGER:-$USER}" 2> /dev/null)"
[ -n "$UNIT_MANAGER" ] || { echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable 'UNIT_MANAGER': No such user" >&2; exit 1; }

if [ "$UNIT_MANAGER" != "$USER" ] && [ "$UID" != 0 ]; then
    echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable 'UNIT_MANAGER':" \
        "Running user ${USER@Q} isn't permitted to run \`systemctl\` as ${UNIT_MANAGER@Q}" >&2
    exit 1
fi

[[ "${UNIT_ENABLED:-}" =~ ^(1|y|yes|true)$ ]] \
    && UNIT_ENABLED="y" \
    || UNIT_ENABLED=""

# builder config
BUILDER_USER="$(id -un -- "${BUILDER_USER:-$USER}" 2> /dev/null)"
[ -n "$BUILDER_USER" ] || { echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable 'BUILDER_USER': No such user" >&2; exit 1; }

if [ "$BUILDER_USER" != "$USER" ] && [ "$UID" != 0 ]; then
    echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable 'BUILDER_USER':" \
        "Running user ${USER@Q} isn't permitted to run \`podman\` as ${BUILDER_USER@Q}" >&2
    exit 1
fi

BUILDER_IMAGE="${BUILDER_IMAGE:-ghcr.io/sgsgermany/apache-builder:latest}"

BUILDER_CONTAINER="${BUILDER_CONTAINER:-}"

BUILDER_CONFIG="${BUILDER_CONFIG:-$DATA_DIR/${CONFIG:-config}}"
[ ! -e "$BUILDER_CONFIG" ] || check_path "Invalid config file ${CONFIG_FILE@Q}: Invalid builder config path" "$BUILDER_CONFIG" -d

ARCHIVES_PATH="${ARCHIVES_PATH:-$DATA_DIR/archives}"
[ ! -e "$ARCHIVES_PATH" ] || check_path "Invalid config file ${CONFIG_FILE@Q}: Invalid archives path" "$ARCHIVES_PATH" -d

# user namespace management (i.e. dealing with /etc/subuid and /etc/subgid)
[[ "${MANAGE_SUBIDS:-}" =~ ^(1|y|yes|true)$ ]] \
    && MANAGE_SUBIDS="y" \
    || MANAGE_SUBIDS=""

if [ -n "$MANAGE_SUBIDS" ] && [ "$UID" != 0 ]; then
    echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable 'MANAGE_SUBIDS':" \
        "Running user ${USER@Q} isn't permitted to edit /etc/subuid and /sub/subgid" >&2
    exit 1
fi

__parse_subids() {
    local TYPE="$1"
    local VAR="$2"
    shift 2

    case "$TYPE" in
        "-u") local INFO_NAME="user" INFO_ID="uid" ;;
        "-g") local INFO_NAME="group" INFO_ID="gid" ;;
        *)    return 1 ;;
    esac

    local -n STATIC_SUBIDS="$VAR"
    STATIC_SUBIDS=()

    while (( $# > 0 )); do
        if [[ "$1" =~ ^([0-9]+)(:([0-9]+))?$ ]]; then
            STATIC_SUBIDS+=( "${BASH_REMATCH[1]}":"${BASH_REMATCH[3]:-1}" )
        elif [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_.-]{0,31}$ ]]; then
            local STATIC_SUBID="$(id "$TYPE" -- "$1" 2> /dev/null)"
            [ -n "$STATIC_SUBID" ] || { echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable ${VAR@Q}:" \
                "Invalid static sub$INFO_ID matching no $INFO_NAME: $STATIC_SUBID" >&2; return 1; }
            STATIC_SUBIDS+=( "$STATIC_SUBID":"1" )
        else
            echo "Invalid config file ${CONFIG_FILE@Q}: Invalid config variable ${VAR@Q}:" \
                "Invalid static sub$INFO_ID not matching expected format" \
                "'<$INFO_NAME>|<$INFO_ID>|<$INFO_ID>:<count>': $STATIC_SUBUID" >&2
            return 1
        fi
        shift
    done
}

[ -v STATIC_SUBUIDS ] || STATIC_SUBUIDS=()
__parse_subids -u STATIC_SUBUIDS "${STATIC_SUBUIDS[@]}" || exit 1

[ -v STATIC_SUBGIDS ] || STATIC_SUBGIDS=()
__parse_subids -g STATIC_SUBGIDS "${STATIC_SUBGIDS[@]}" || exit 1

unset -f __parse_subids

# auto-update config
[[ "${AUTO_UPDATE:-}" =~ ^(1|y|yes|true)$ ]] \
    && AUTO_UPDATE="y" \
    || AUTO_UPDATE=""

[[ "${AUTO_START:-}" =~ ^(1|y|yes|true)$ ]] \
    && AUTO_START="y" \
    || AUTO_START=""
