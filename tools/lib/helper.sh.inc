# apache-builder
# A container to build Apache containers.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

quote() {
    local QUOTED=""
    for ARG in "$@"; do
        [ "$(printf '%q' "$ARG")" == "$ARG" ] \
            && QUOTED+=" $ARG" \
            || QUOTED+=" ${ARG@Q}"
    done

    echo "${QUOTED:1}"
}

cmd() {
    echo + "$(quote "$@")" >&2

    "$@"
    return $?
}

__call() {
    local ACTION="$1"
    shift

    if [ ! -e "$LIB_DIR/$ACTION.sh" ]; then
        echo "Invalid action '$ACTION': Action not found" >&2
        return 1
    elif [ ! -f "$LIB_DIR/$ACTION.sh" ] || [ ! -r "$LIB_DIR/$ACTION.sh" ]; then
        echo "Invalid action '$ACTION': Action is invalid" >&2
        return 1
    fi

    source "$LIB_DIR/$ACTION.sh"
    action_exec "$@"
}

__systemctl() {
    systemctl --full --no-legend --no-pager --plain --system "$@"
}

check_oci_archive() {
    if [ ! -e "$ARCHIVES_PATH" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': No such file or directory" >&2
        return 1
    elif [ ! -d "$ARCHIVES_PATH" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid directory structure" >&2
        return 1
    fi
}

check_oci_image() {
    local IMAGE="$1"
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"
    local TAG="$(basename "$IMAGE" | cut -s -d ':' -f 2 | cut -d '@' -f 1)"
    local DIGEST="$(basename "$IMAGE" | cut -s -d '@' -f 2)"

    [ -n "$TAG" ] || [ -n "$DIGEST" ] || TAG="latest"

    if [ ! -e "$ARCHIVES_PATH/$NAME" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$NAME' not found: No such file or directory" >&2
        return 1
    elif [ ! -d "$ARCHIVES_PATH/$NAME" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$NAME' not found: Not a directory" >&2
        return 1
    fi

    if [ -n "$DIGEST" ]; then
        if [ ! -e "$ARCHIVES_PATH/$NAME/$DIGEST" ]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$NAME' with digest '$DIGEST' not found: No such file or directory" >&2
            return 1
        elif [ ! -d "$ARCHIVES_PATH/$NAME/$DIGEST" ]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$NAME' with digest '$DIGEST' not found: Not a directory" >&2
            return 1
        fi
    fi

    if [ -n "$TAG" ]; then
        if [ ! -h "$ARCHIVES_PATH/$NAME/$TAG" ]; then
            if [ ! -e "$ARCHIVES_PATH/$NAME/$TAG" ]; then
                echo "Invalid OCI archive '$ARCHIVES_PATH': Tag '$TAG' of image '$NAME' not found: No such file or directory" >&2
            else
                echo "Invalid OCI archive '$ARCHIVES_PATH': Tag '$TAG' of image '$NAME' is invalid: Not a symbolic link" >&2
            fi
            return 1
        elif [ ! -e "$ARCHIVES_PATH/$NAME/$TAG" ]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Tag '$TAG' of image '$NAME' is invalid: Broken symbolic link" >&2
            return 1
        elif [ ! -d "$ARCHIVES_PATH/$NAME/$TAG" ]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Tag '$TAG' of image '$NAME' is invalid: Symbolic link targets no directory" >&2
            return 1
        fi

        TAG_DIGEST="$(readlink "$ARCHIVES_PATH/$NAME/$TAG")"
        if [ -z "$TAG_DIGEST" ] || [[ "$TAG_DIGEST" == */* ]]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Tag '$TAG' of image '$NAME' is invalid: Invalid symbolic link target '$TAG_DIGEST'" >&2
            return 1
        fi

        if [ -z "$DIGEST" ]; then
            DIGEST="$TAG_DIGEST"
        elif [ "$TAG_DIGEST" != "$DIGEST" ]; then
            echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$IMAGE' not found: Tag '$TAG' references digest '$TAG_DIGEST'" >&2
            return 1
        fi
    fi

    if [ ! -e "$ARCHIVES_PATH/$NAME/$DIGEST/image" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$IMAGE' not found: No such file or directory" >&2
        return 1
    elif [ ! -f "$ARCHIVES_PATH/$NAME/$DIGEST/image" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$IMAGE' not found: Not a file" >&2
        return 1
    elif [ ! -r "$ARCHIVES_PATH/$NAME/$DIGEST/image" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Image '$IMAGE' not found: Permission denied" >&2
        return 1
    fi

    if [ ! -e "$ARCHIVES_PATH/$NAME/$DIGEST/metadata.json" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Metadata of image '$IMAGE' not found: No such file or directory" >&2
        return 1
    elif [ ! -f "$ARCHIVES_PATH/$NAME/$DIGEST/metadata.json" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Metadata of image '$IMAGE' not found: Not a file" >&2
        return 1
    elif [ ! -r "$ARCHIVES_PATH/$NAME/$DIGEST/metadata.json" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Metadata of image '$IMAGE' not found: Permission denied" >&2
        return 1
    fi
}

check_image() {
    local IMAGE="$1"

    if ! podman image exists "$IMAGE"; then
        echo "Invalid Podman image '$IMAGE': Image not found" >&2
        return 1
    fi
}

unit_loaded() {
    [ -n "$(__systemctl list-unit-files "$1" 2> /dev/null ; __systemctl list-units --all "$1" 2> /dev/null)" ]
}

unit_active() {
    __systemctl is-active --quiet "$1"
}

check_unit() {
    local UNIT="$1"
    local UNIT_PATH="/etc/systemd/system/$UNIT"

    if ! unit_loaded "$UNIT"; then
        echo "Invalid Systemd unit '$UNIT': No such unit" >&2
        return 1
    elif [ ! -e "$UNIT_PATH" ]; then
        echo "Invalid Systemd unit '$UNIT': Invalid unit file '$UNIT_PATH': No such file or directory" >&2
        return 1
    elif [ ! -f "$UNIT_PATH" ]; then
        echo "Invalid Systemd unit '$UNIT': Invalid unit file '$UNIT_PATH': Not a file" >&2
        return 1
    fi
}

check_builder() {
    check_oci_archive

    if [ ! -e "$CONFIG_PATH" ]; then
        echo "Invalid builder config directory '$CONFIG_PATH': No such file or directory" >&2
        return 1
    elif [ ! -d "$CONFIG_PATH" ]; then
        echo "Invalid builder config directory '$CONFIG_PATH': Not a directory" >&2
        return 1
    fi
}

run_builder() {
    # prepare `podman run` options
    local OPTIONS=()

    OPTIONS+=( --interactive )

    while [ $# -gt 0 ] && [ "${1:1:1}" == "-" ]; do
        OPTIONS+=( "$1" )
        shift
    done

    OPTIONS+=( --name "$BUILDER_CONTAINER" )
    OPTIONS+=( --pull "always" --rm )
    OPTIONS+=( --log-driver "none" )

    # prepare `podman run` params
    local PARAMS=()

    PARAMS+=( --uidmap 0:1:65536 --uidmap 65536:0:1 )
    PARAMS+=( --gidmap 0:1:65536 --gidmap 65536:0:1 )
    PARAMS+=( --mount type="bind",src="$CONFIG_PATH",dst="/etc/apache-builder",ro="true" )
    PARAMS+=( --mount type="bind",src="$ARCHIVES_PATH",dst="/var/local/apache-builder/archives" )

    # execute `podman run`
    local EXEC=( podman run "${OPTIONS[@]}" "${PARAMS[@]}" "$BUILDER_IMAGE" )

    if [ "$BUILDER_USER" != "$(id -un)" ]; then
        cmd sudo --login --user "$BUILDER_USER" -- "${EXEC[@]}" "$@"
    else
        cmd "${EXEC[@]}" "$@"
    fi
}
