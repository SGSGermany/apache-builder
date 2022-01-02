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

__call() {
    local COMMAND="$1"

    if [ ! -f "$LIB_DIR/$COMMAND.sh" ] || [ ! -r "$LIB_DIR/$COMMAND.sh" ]; then
        echo "Invalid command: $COMMAND" >&2
        return 1
    fi

    source "$LIB_DIR/$COMMAND.sh"
    command_exec
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
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"

    if ! podman image exists "$IMAGE"; then
        echo "Invalid Podman image '$NAME': Image '$IMAGE' not found" >&2
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
    local EXEC=(
        podman run --name "$BUILDER_CONTAINER" --pull "always" --replace \
            --uidmap 0:1:65536 --uidmap 65536:0:1 \
            --gidmap 0:1:65536 --gidmap 65536:0:1 \
            --mount type="bind",src="$CONFIG_PATH",dst="/etc/apache-builder",ro="true" \
            --mount type="bind",src="$ARCHIVES_PATH",dst="/var/local/apache-builder/archives" \
            "$BUILDER_IMAGE" "$@"
    )

    if [ "$BUILDER_USER" != "root" ]; then
        sudo --non-interactive --login --user "$BUILDER_USER" -- "${EXEC[@]}"
    else
        "${EXEC[@]}"
    fi
}
