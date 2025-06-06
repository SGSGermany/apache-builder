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

action_info() {
    local TAG="${TAGS%% *}"

    echo + "IMAGE=${IMAGE@Q}" >&2
    echo + "TAG=${TAG@Q}" >&2

    echo + "UNIT=${UNIT@Q}" >&2
    echo + "UNIT_TEMPLATE=${UNIT_TEMPLATE@Q}" >&2
    echo + "UNIT_MANAGER=${UNIT_MANAGER@Q}" >&2
    echo + "UNIT_ENABLED=${UNIT_ENABLED@Q}" >&2

    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2

    echo + "CONTAINER=${CONTAINER@Q}" >&2
    echo + "CONTAINER_USERNS=${CONTAINER_USERNS@Q}" >&2
    echo + "CONTAINER_NETWORK=${CONTAINER_NETWORK@Q}" >&2
    echo + "CONTAINER_HOSTNAME=${CONTAINER_HOSTNAME@Q}" >&2
    echo + "CONTAINER_PUBLISH_PORTS=( ${CONTAINER_PUBLISH_PORTS[@]@Q} )" >&2

    echo + "HOST_UID_MAP=( ${HOST_UID_MAP[@]@Q} )" >&2
    echo + "HOST_GID_MAP=( ${HOST_GID_MAP[@]@Q} )" >&2
}

action_exec() {
    uidmap() {
        local HOST_USER="$(printf '%s\n' "${HOST_UID_MAP[@]}" \
            | sed -ne "s/^$(sed -e 's/[]\/$*.^[]/\\&/g' <<< "$1")   *\(.*\)$/\1/p")"
        echo "${HOST_USER:-$1}"
    }

    gidmap() {
        local HOST_GROUP="$(printf '%s\n' "${HOST_GID_MAP[@]}" \
            | sed -ne "s/^$(sed -e 's/[]\/$*.^[]/\\&/g' <<< "$1")   *\(.*\)$/\1/p")"
        echo "${HOST_GROUP:-$1}"
    }

    subid_base_user() {
        local SUBID_BASE="$(awk -F ":" -v USER="$2" -v UID="$(id -u -- "$2")" \
            '($1 == USER || $1 == UID) && ($3 == 65536) { print $2; exit }' \
            "$1")"
        [ -n "$SUBID_BASE" ] || { echo "Unsuitable ${1@Q} for user ${2@Q} to use for rootless containers:" \
            "The $(basename "$1")s don't include a suitable mapping for the base user namespace" >&2; return 1; }
        echo "$SUBID_BASE"
    }

    subid_base_root() {
        local SUBID_MAPS="$(awk -F ":" -v USER="$2" -v UID="$(id -u -- "$2")" \
            '($1 == USER || $1 == UID) { print }' \
            "$1")"
        (( $(wc -l <<< "$SUBID_MAPS") == 1 )) && [[ "$SUBID_MAPS" == *:65536 ]] \
            || { echo "Unsuitable ${1@Q} for user ${2@Q} to use for rootful containers:" \
                "The $(basename "$1") mappings must consist of the base user namespace only" >&2; return 1; }
        echo "$2"
    }

    pathmap() {
        local -n HOST_PATHS="HOST_${3^^}_PATHS"
        local HOST_PATH="$(sed -ne "s/^$(sed -e 's/[]\/$*.^[]/\\&/g' <<< "$1")   *\(.*\)$/\1/p" <<< "${HOST_PATHS[@]:-}")"

        if [ -z "$HOST_PATH" ]; then
            local -n HOST_PATH_PATTERN="HOST_${3^^}_PATH_PATTERN"
            local SITE_VAR_SCRIPT="s/\${SITE}/$(sed -e 's/[\/&]/\\&/g' <<< "$1")/g"
            local SITE_OWNER_VAR_SCRIPT="s/\${SITE_OWNER}/$(sed -e 's/[\/&]/\\&/g' <<< "$2")/g"
            HOST_PATH="$(sed -e "$SITE_VAR_SCRIPT" -e "$SITE_OWNER_VAR_SCRIPT" <<< "${HOST_PATH_PATTERN:-}")"
        fi

        if [ -z "$HOST_PATH" ]; then
            local -n HOST_PATH_STATIC="HOST_${3^^}_PATH"
            HOST_PATH="${HOST_PATH_STATIC:-}"
        fi

        [ -n "$HOST_PATH" ] || { echo "Unable to get host path of $3 directory for site ${1@Q}" >&2; return 1; }
        echo "$HOST_PATH"
    }

    write_unit() {
        echo + "$(quote "$@") >&3" >&2

        "$@" >&3
        return $?
    }

    local TAG="${TAGS%% *}"

    # check Quadlet Systemd unit
    # only root is allowed to work with the Systemd service manager of other users,
    # therefore we either work with files and directories of the running user, or run as root
    local QUADLET_DIR="$(__quadlet_dir)"
    local UNIT_PATH_QUADLET="$QUADLET_DIR/$UNIT.container"

    if [ ! -e "$QUADLET_DIR" ]; then
        cmd mkdir -m 700 "$QUADLET_DIR"
        [ "$UNIT_MANAGER" == "$USER" ] || cmd chown "$UNIT_MANAGER":"$(id -gn -- "$UNIT_MANAGER")" "$QUADLET_DIR"
    fi

    check_path "Invalid Quadlet config dir" "$QUADLET_DIR" -e -d

    [ ! -e "$UNIT_PATH_QUADLET" ] || check_path "Invalid Quadlet Systemd unit ${UNIT@Q} at" "$UNIT_PATH_QUADLET" -f -r -w

    # check for conflicting Systemd unit
    local SYSTEMD_DIR="$(__systemd_dir)"
    local UNIT_PATH_SYSTEMD="$SYSTEMD_DIR/$UNIT.service"

    if [ -e "$SYSTEMD_DIR" ]; then
        check_path "Invalid Systemd user service dir" "$SYSTEMD_DIR" -d

        [ ! -h "$UNIT_PATH_SYSTEMD" ] || [ "$(realpath "$UNIT_PATH_SYSTEMD")" != "/dev/null" ] \
            || { echo "Invalid Quadlet Systemd unit ${UNIT@Q} at ${UNIT_PATH_SYSTEMD@Q}: Unit is masked" >&2; return 1; }
        check_path "Invalid Quadlet Systemd unit ${UNIT@Q} at" "$UNIT_PATH_SYSTEMD" -n
    fi

    # check image
    check_image "$IMAGE:$TAG"

    echo + "IMAGE_ID=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE:$TAG"))\"" >&2
    local IMAGE_ID="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE:$TAG")"

    echo + "DIGEST=\"\$(podman image inspect --format '{{.Digest}}' $(quote "localhost/$IMAGE:$TAG") | sed -ne 's/^sha256:\(.*\)$/\1/p')\"" >&2
    local DIGEST="$(podman image inspect --format '{{.Digest}}' "localhost/$IMAGE:$TAG" | sed -ne 's/^sha256:\(.*\)$/\1/p')"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE:$TAG@$DIGEST"

    local METADATA="$ARCHIVES_PATH/$IMAGE/$DIGEST/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    # make sure the unit template contains either no, or a valid '[Install]' section
    # comments not starting with a space are considered illegal within the '[Install]' section,
    # because we must be able to comment/uncomment this section to disable/enable the unit
    if awk '/\[.+\]/ { found=0 } found { print } /\[Install\]/ { found=1 }' "$UNIT_TEMPLATE" | grep -q '^#\S'; then
        echo "Invalid Quadlet Systemd unit template ${UNIT_TEMPLATE@Q}:" \
            "[Install] section must not contain comments that don't start with whitespaces" >&2
        return 1
    fi

    # write Quadlet Systemd unit file
    local UNIT_TMP="$(mktemp)"

    echo + "exec 3> $(quote "$UNIT_TMP")" >&2
    exec 3> "$UNIT_TMP"

    write_unit awk '/\[Container\]/ { exit } { print }' "$UNIT_TEMPLATE"

    write_unit printf '[Container]\n'
    write_unit printf 'ContainerName=%s\n' "$CONTAINER"
    write_unit printf 'Image=%s\n' "$IMAGE_ID"
    write_unit printf 'PodmanArgs=%s\n' "--tty"

    write_unit printf '\n'
    if [ "$UNIT_MANAGER" != "root" ]; then
        write_unit printf 'UIDMap=%s:%s:%s\n' "0" "@$(subid_base_user "/etc/subuid" "$CONTAINER_USERNS")" "65536"
    else
        write_unit printf 'SubUIDMap=%s\n' "$(subid_base_root "/etc/subuid" "$CONTAINER_USERNS")"
    fi
    while IFS=: read -r CONTAINER_USER CONTAINER_UID; do
        local HOST_USER="$(uidmap "$CONTAINER_USER")"
        local HOST_UID="$(id -u -- "$HOST_USER" 2> /dev/null)"
        [ -n "$HOST_UID" ] || { echo "Unsuitable '/etc/subuid' for user ${CONTAINER_USERNS@Q}: Failed to map" \
            "container user ${CONTAINER_USER@Q} to host user ${HOST_USER@Q}: No such user" >&2; return 1; }

        [ "$UNIT_MANAGER" == "root" ] || HOST_UID="@$HOST_UID"
        write_unit printf 'UIDMap=%s:%s:%s\n' "$CONTAINER_UID" "$HOST_UID" "1"
    done < <(jq -r '.[].RunMeta.IdMaps | to_entries[] | "\(.key):\(.value)"' "$METADATA")

    write_unit printf '\n'
    if [ "$UNIT_MANAGER" != "root" ]; then
        write_unit printf 'GIDMap=%s:%s:%s\n' "0" "@$(subid_base_user "/etc/subgid" "$CONTAINER_USERNS")" "65536"
    else
        write_unit printf 'SubGIDMap=%s\n' "$(subid_base_root "/etc/subgid" "$CONTAINER_USERNS")"
    fi
    while IFS=: read -r CONTAINER_GROUP CONTAINER_GID; do
        local HOST_GROUP="$(gidmap "$CONTAINER_GROUP")"
        local HOST_GID="$(id -g -- "$HOST_GROUP" 2> /dev/null)"
        [ -n "$HOST_GID" ] || { echo "Unsuitable '/etc/subgid' for user ${CONTAINER_USERNS@Q}: Failed to map" \
            "container group ${CONTAINER_GROUP@Q} to host group ${HOST_GROUP@Q}: No such group" >&2; return 1; }

        [ "$UNIT_MANAGER" == "root" ] || HOST_GID="@$HOST_GID"
        write_unit printf 'GIDMap=%s:%s:%s\n' "$CONTAINER_GID" "$HOST_GID" "1"
    done < <(jq -r '.[].RunMeta.IdMaps | to_entries[] | "\(.key):\(.value)"' "$METADATA")

    write_unit printf '\n'
    while IFS= read -r MOUNT_JSON; do
        SITE="$(jq -r '.site' <<< "$MOUNT_JSON")"
        SITE_OWNER="$(jq -r '.owner' <<< "$MOUNT_JSON")"
        PATH_TYPE="$(jq -r '.type' <<< "$MOUNT_JSON")"
        MOUNT_SOURCE="$(pathmap "$SITE" "$SITE_OWNER" "$PATH_TYPE")"
        MOUNT_DESTINATION="$(jq -r '.path' <<< "$MOUNT_JSON")"

        MOUNT_OPTIONS="{}"
        case "$PATH_TYPE" in
            "logs")            ;;
            "ssl")             MOUNT_OPTIONS="$(jq -nc --arg "ro" "true" '$ARGS.named')" ;;
            "htdocs")          MOUNT_OPTIONS="$(jq -nc --arg "ro" "true" '$ARGS.named')" ;;
            "php_fpm")         MOUNT_OPTIONS="$(jq -nc --arg "ro" "true" '$ARGS.named')" ;;
            "acme_challenges") MOUNT_OPTIONS="$(jq -nc --arg "ro" "true" '$ARGS.named')" ;;
        esac

        [ -n "$MOUNT_SOURCE" ] || return 1
        [ -e "$MOUNT_SOURCE" ] || mkdir "$MOUNT_SOURCE"
        check_path "Invalid host setup for virtual host ${SITE@Q}: Invalid $PATH_TYPE directory" "$MOUNT_SOURCE" -e -d

        write_unit jq -nr --arg type "bind" --arg src "$MOUNT_SOURCE" --arg dst "$MOUNT_DESTINATION" --argjson opts "$MOUNT_OPTIONS" \
            '({type: $type, src: $src, dst: $dst} + $opts) | to_entries | map("\(.key)=\(.value)") | join(",") | "Mount=\(.)"'
    done < <(jq -c '.[].RunMeta.Mounts[]' "$METADATA")

    write_unit printf '\n'
    [ -z "$CONTAINER_NETWORK" ] || write_unit printf 'Network=%s\n' "$CONTAINER_NETWORK"
    [ "${#CONTAINER_PUBLISH_PORTS[@]}" -eq 0 ] || write_unit printf 'PublishPort=%s\n' "${CONTAINER_PUBLISH_PORTS[@]}"
    [ -z "$CONTAINER_HOSTNAME" ] || write_unit printf 'HostName=%s\n' "$CONTAINER_HOSTNAME"
    while IFS= read -r HOST; do
        write_unit printf 'AddHost=%s:%s\n' "$HOST" "host-gateway"
    done < <(jq -r '.[].RunMeta.Hosts[]' "$METADATA")

    write_unit awk 'found { print } /\[Container\]/ { found=1 }' "$UNIT_TEMPLATE"

    echo + "exec 3>&-" >&2
    exec 3>&-

    # Systemd can't enable or disable generated Systemd units (like this one)
    # we thus just comment the '[Install]' section if the unit isn't supposed to be enabled
    # note: we intentionally don't check whether the unit can actually be enabled/disabled
    if [ -z "$UNIT_ENABLED" ]; then
        gawk -i inplace '/\[.+\]/ { found=0 } /\[Install\]/ { found=1 }
            found && !/^(\s*|#.*)$/ { print "#" $0 } !found || /^(\s*|#.*)$/ { print }' "$UNIT_TMP"
    fi

    # move Quadlet Systemd unit file in place
    cmd mv -f "$UNIT_TMP" "$UNIT_PATH_QUADLET"

    # reload systemd daemon
    __systemctl daemon-reload
}
