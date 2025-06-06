CONTAINER="${CONTAINER:-$IMAGE}"

CONTAINER_USERNS="$(id -un -- "${CONTAINER_USERNS:-$UNIT_MANAGER}" 2> /dev/null)"
[ -n "$CONTAINER_USERNS" ] || { echo "Invalid config file ${CONTAINER_CONFIG@Q}: Invalid config variable 'CONTAINER_USERNS': No such user" >&2; exit 1; }

if [ "$UNIT_MANAGER" == "root" ]; then
    if [ "$CONTAINER_USERNS" == "root" ]; then
        echo "Invalid config file ${CONTAINER_CONFIG@Q}: Invalid config variable 'CONTAINER_USERNS':" \
            "You must configure an unprivileged user's user namespace to use when running the container as root" >&2
        exit 1
    fi
elif [ "$CONTAINER_USERNS" != "$UNIT_MANAGER" ]; then
    echo "Invalid config file ${CONTAINER_CONFIG@Q}: Invalid config variable 'CONTAINER_USERNS':" \
        "Can't configure a different user namespace when running the container as user ${UNIT_MANAGER@Q}" >&2
    exit 1
fi

CONTAINER_NETWORK="${CONTAINER_NETWORK:-}"

CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-}"

[ -v CONTAINER_PUBLISH_PORTS ] || CONTAINER_PUBLISH_PORTS=()
