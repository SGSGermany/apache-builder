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

    check_path "Invalid action script" "$LIB_DIR/actions/$ACTION.sh" -e -f -r

    echo + "__call $(quote "$ACTION" "$@")" >&2
    source "$LIB_DIR/actions/$ACTION.sh"
    action_exec "$@"
}

__systemctl() {
    if [ "$UNIT_MANAGER" != "$USER" ]; then
        # only root is allowed to get here, i.e. this must be root working with an unprivileged user's Systemd service manager
        echo + "sudo -i -u $(quote "$UNIT_MANAGER") -- systemctl --user $(quote "$@")" >&2
        sudo -i -u "$UNIT_MANAGER" -- systemctl --full --no-legend --no-pager --plain --user "$@"
    elif [ "$UNIT_MANAGER" == "root" ]; then
        echo + "systemctl --system $(quote "$@")" >&2
        systemctl --full --no-legend --no-pager --plain --system "$@"
    else
        echo + "systemctl --user $(quote "$@")" >&2
        systemctl --full --no-legend --no-pager --plain --user "$@"
    fi
}

__systemd_dir() {
    if [ "$UNIT_MANAGER" == "root" ]; then
        echo "/etc/systemd/system"
    else
        UNIT_MANAGER_HOME="$(bash -c "cd ~$(printf '%q' "$UNIT_MANAGER") 2> /dev/null && pwd")"
        [ -n "$UNIT_MANAGER_HOME" ] || { echo "Invalid Systemd service manager ${UNIT_MANAGER@Q}: Failed to determine home directory path" >&2; exit 1; }
        echo "$UNIT_MANAGER_HOME/.config/systemd/user"
    fi
}

__quadlet_dir() {
    if [ "$UNIT_MANAGER" == "root" ]; then
        echo "/etc/containers/systemd"
    else
        UNIT_MANAGER_HOME="$(bash -c "cd ~$(printf '%q' "$UNIT_MANAGER") 2> /dev/null && pwd")"
        [ -n "$UNIT_MANAGER_HOME" ] || { echo "Invalid Systemd service manager ${UNIT_MANAGER@Q}: Failed to determine home directory path" >&2; exit 1; }
        echo "$UNIT_MANAGER_HOME/.config/containers/systemd"
    fi
}

check_oci_archive() {
    [ -e "$ARCHIVES_PATH" ] || [ -h "$ARCHIVES_PATH" ] || mkdir "$ARCHIVES_PATH"
    check_path "Invalid OCI archive" "$ARCHIVES_PATH" -e -d
}

check_oci_image() {
    local IMAGE="$1"
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"
    local TAG="$(basename "$IMAGE" | cut -s -d ':' -f 2 | cut -d '@' -f 1)"
    local DIGEST="$(basename "$IMAGE" | cut -s -d '@' -f 2)"

    [ -n "$TAG" ] || [ -n "$DIGEST" ] || TAG="latest"

    check_path "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} at" "$ARCHIVES_PATH/$NAME" -e -d
    [ -z "$DIGEST" ] || check_path "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} with digest ${DIGEST@Q} at" "$ARCHIVES_PATH/$NAME/$DIGEST" -e -d

    if [ -n "$TAG" ]; then
        local TAG_PATH="$ARCHIVES_PATH/$NAME/$TAG"

        check_path "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} tagged ${TAG@Q} at" "$TAG_PATH" -h -e -d

        TAG_DIGEST="$(readlink "$TAG_PATH")"
        if [ -z "$TAG_DIGEST" ] || [[ "$TAG_DIGEST" == */* ]]; then
            echo "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} tagged ${TAG@Q} at ${TAG_PATH@Q}:" \
                "Invalid symbolic link target: $TAG_DIGEST" >&2
            return 1
        fi

        if [ -z "$DIGEST" ]; then
            DIGEST="$TAG_DIGEST"
        elif [ "$TAG_DIGEST" != "$DIGEST" ]; then
            echo "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} tagged ${TAG@Q} at ${TAG_PATH@Q}:" \
                "Tag digest ${TAG_DIGEST@Q} does not match expected digest ${DIGEST@Q}" >&2
            return 1
        fi
    fi

    check_path "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting image ${NAME@Q} at" "$ARCHIVES_PATH/$NAME/$DIGEST/image" -e -f -r
    check_path "Invalid OCI archive ${ARCHIVES_PATH@Q}: Expecting metadata of image ${NAME@Q} at" "$ARCHIVES_PATH/$NAME/$DIGEST/metadata.json" -e -f -r
}

check_image() {
    cmd podman image exists "$1" || { echo "Invalid Podman image ${1@Q}: Image not found" >&2; return 1; }
}

unit_loaded() {
    echo + "unit_loaded $(quote "$1")" >&2
    [ -n "$(__systemctl list-unit-files "$1" 2> /dev/null ; __systemctl list-units --all "$1" 2> /dev/null)" ]
}

unit_active() {
    echo + "unit_active $(quote "$1")" >&2
    __systemctl is-active --quiet "$1" 2> /dev/null
}

check_unit() {
    check_container_unit "$@"
    check_service_unit "$@"
}

check_container_unit() {
    local UNIT="$1"
    local QUADLET_DIR="$(__quadlet_dir)"

    check_path "Invalid Quadlet config dir" "$QUADLET_DIR" -e -d
    check_path "Invalid Quadlet Systemd unit ${UNIT@Q} at" "$QUADLET_DIR/$UNIT.container" -e -f
}

check_service_unit() {
    local UNIT="$1"
    local UNIT_PATH_SYSTEMD="$(__systemd_dir)/$UNIT.service"

    [ ! -h "$UNIT_PATH_SYSTEMD" ] || [ "$(realpath "$UNIT_PATH_SYSTEMD")" != "/dev/null" ] \
        || { echo "Invalid Quadlet Systemd unit ${UNIT@Q} at ${UNIT_PATH_SYSTEMD@Q}: Unit is masked" >&2; exit 1; }
    check_path "Invalid Quadlet Systemd unit ${UNIT@Q} at" "$UNIT_PATH_SYSTEMD" -n

    unit_loaded "$UNIT.service" 2> /dev/null || { echo "Invalid Quadlet Systemd unit ${UNIT@Q}: Unit is not loaded" >&2; return 1; }
}

check_builder() {
    check_oci_archive

    [ -e "$BUILDER_CONFIG" ] || [ -h "$BUILDER_CONFIG" ] || mkdir "$BUILDER_CONFIG"
    check_path "Invalid builder config directory" "$BUILDER_CONFIG" -e -d

    [ ! -e "$BUILDER_CONFIG/ssl" ] \
        || check_path "Invalid builder config directory: Invalid Apache SSL directory" "$BUILDER_CONFIG/sites" -d
    [ ! -e "$BUILDER_CONFIG/mods" ] \
        || check_path "Invalid builder config directory: Invalid Apache modules directory" "$BUILDER_CONFIG/mods" -d
    [ ! -e "$BUILDER_CONFIG/conf" ] \
        || check_path "Invalid builder config directory: Invalid Apache configs directory" "$BUILDER_CONFIG/conf" -d
    [ ! -e "$BUILDER_CONFIG/sites" ] \
        || check_path "Invalid builder config directory: Invalid virtual hosts config directory" "$BUILDER_CONFIG/sites" -d
    [ ! -e "$BUILDER_CONFIG/sites-templates" ] \
        || check_path "Invalid builder config directory: Invalid virtual hosts template directory" "$BUILDER_CONFIG/sites-templates" -d

    [ ! -e "$BUILDER_CONFIG/src" ] \
        || check_path "Invalid builder config directory: Invalid custom source files directory" "$BUILDER_CONFIG/src" -d
    [ ! -e "$BUILDER_CONFIG/build.sh" ] \
        || check_path "Invalid builder config directory: Invalid custom build script" "$BUILDER_CONFIG/build.sh" -f
}

create_builder_config() {
    local CONFIG_FILE="$(mktemp)"

    while [ $# -gt 0 ]; do
        [[ "$1" =~ ^([a-zA-Z][a-zA-Z0-9_]*)(\[\])?$ ]] \
            || { echo "Invalid argument for \`create_builder_config\`: $1" >&2; return 1; }
        declare -p "${BASH_REMATCH[1]}" >> "$CONFIG_FILE"
        shift
    done

    if [ "$BUILDER_USER" != "$USER" ]; then
        cmd chown "$BUILDER_USER":"$(id -gn "$BUILDER_USER")" "$CONFIG_FILE"
    fi

    echo + "create_builder_config > $(quote "$CONFIG_FILE")" >&2
    echo "$CONFIG_FILE"
}

run_builder() {
    # prepare `podman run` options
    local OPTIONS=()

    while [ $# -gt 0 ] && [ "${1:1:1}" == "-" ]; do
        OPTIONS+=( "$1" )
        shift
    done

    OPTIONS+=( --name "$BUILDER_CONTAINER" )
    OPTIONS+=( --pull "always" )
    OPTIONS+=( --rm )
    OPTIONS+=( --log-driver "none" )
    OPTIONS+=( --privileged )

    # prepare `podman run` params
    local PARAMS=()

    [ ! -e "$BUILDER_CONFIG/ssl" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/ssl",dst="/etc/apache-builder/ssl",ro="true" )
    [ ! -e "$BUILDER_CONFIG/mods" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/mods",dst="/etc/apache-builder/mods",ro="true" )
    [ ! -e "$BUILDER_CONFIG/conf" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/conf",dst="/etc/apache-builder/conf",ro="true" )
    [ ! -e "$BUILDER_CONFIG/sites" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/sites",dst="/etc/apache-builder/sites",ro="true" )
    [ ! -e "$BUILDER_CONFIG/sites-templates" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/sites-templates",dst="/etc/apache-builder/sites-templates",ro="true" )

    [ ! -e "$BUILDER_CONFIG/src" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/src",dst="/etc/apache-builder/src",ro="true" )
    [ ! -e "$BUILDER_CONFIG/build.sh" ] \
        || PARAMS+=( --mount type="bind",src="$BUILDER_CONFIG/build.sh",dst="/etc/apache-builder/build.sh",ro="true" )

    PARAMS+=( --mount type="bind",src="$ARCHIVES_PATH",dst="/var/local/apache-builder/archives",relabel="shared" )
    PARAMS+=( --volume "/var/lib/containers" )

    # create and mount `apache-builder` config
    local CONFIG_FILE="$(create_builder_config "${IMAGE_CONFIG_VARS[@]}" "${APACHE_CONFIG_VARS[@]}")"
    PARAMS+=( --mount type="bind",src="$CONFIG_FILE",dst="/run/apache-builder/config.conf",ro="true" )

    # execute `podman run`
    if [ "$BUILDER_USER" != "$USER" ]; then
        cmd sudo -i -u "$BUILDER_USER" -- podman run -i "${OPTIONS[@]}" "${PARAMS[@]}" "$BUILDER_IMAGE" "$@"
    else
        cmd podman run -i "${OPTIONS[@]}" "${PARAMS[@]}" "$BUILDER_IMAGE" "$@"
    fi

    # remove `apache-builder` config
    cmd rm -f "$CONFIG_FILE"
}
