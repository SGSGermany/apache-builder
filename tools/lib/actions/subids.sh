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

    if [ -n "$MANAGE_SUBIDS" ]; then
        echo + "IMAGE=${IMAGE@Q}" >&2
        echo + "TAG=${TAG@Q}" >&2

        echo + "UNIT_MANAGER=${UNIT_MANAGER@Q}" >&2
        echo + "CONTAINER_USERNS=${CONTAINER_USERNS@Q}" >&2

        echo + "MANAGE_SUBIDS=${MANAGE_SUBIDS@Q}" >&2
        echo + "STATIC_SUBUIDS=( ${STATIC_SUBUIDS[@]@Q} )" >&2
        echo + "STATIC_SUBGIDS=( ${STATIC_SUBGIDS[@]@Q} )" >&2

        echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
    else
        echo + "MANAGE_SUBIDS=${MANAGE_SUBIDS@Q}" >&2
    fi
}

action_exec() {
    subid_update() {
        idmap() {
            case "$1" in
                "-u") local -n ID_MAP="HOST_UID_MAP" ;;
                "-g") local -n ID_MAP="HOST_GID_MAP" ;;
                *)    echo "$2"; return 0 ;;
            esac

            local RESULT="$(printf '%s\n' "${ID_MAP[@]}" \
                | sed -ne "s/^$(sed -e 's/[]\/$*.^[]/\\&/g' <<< "$2")   *\(.*\)$/\1/p")"
            echo "${RESULT:-$2}"
        }

        write_subid() {
            echo + "$(quote "$@") >&3" >&2

            "$@" >&3
            return $?
        }

        local TYPE="$1"
        local METADATA="$2"
        shift 2

        case "$TYPE" in
            "-u") local FILE="/etc/subuid" INFO="user" ;;
            "-g") local FILE="/etc/subgid" INFO="group" ;;
            *)    return 1 ;;
        esac

        local CONTAINER_USERNS_UID="$(id -u -- "$CONTAINER_USERNS")"

        # create backup
        local SUBID_BAK="$(mktemp --tmpdir "subuid-.XXXXXXXXXX")"
        cmd cp "$FILE" "$SUBID_BAK"

        # create new subid file
        local SUBID_TMP="$(mktemp --tmpdir "subuid.XXXXXXXXXX")"

        echo + "exec 3> $(quote "$SUBID_TMP")" >&2
        exec 3> "$SUBID_TMP"

        write_subid awk -F ":" -v USER="$CONTAINER_USERNS" -v UID="$CONTAINER_USERNS_UID" \
            '($1 == USER || $1 == UID) { exit } { print }' \
            "$SUBID_BAK"

        # write subids for container users (e.g. site owners)
        while IFS=: read -r CONTAINER_NAME _; do
            local HOST_NAME="$(idmap "$TYPE" "$CONTAINER_NAME")"
            [ "$HOST_NAME" != "$CONTAINER_USERNS" ] || continue

            local HOST_ID="$(id "$TYPE" -- "$HOST_NAME" 2> /dev/null)"
            [ -n "$HOST_ID" ] || { echo "Unsuitable ${FILE@Q} for user ${CONTAINER_USERNS@Q}:" \
                "Failed to map container $INFO ${CONTAINER_NAME@Q} to host $INFO ${HOST_NAME@Q}:" \
                "No such $INFO" >&2; return 1; }

            write_subid printf '%s:%s:%s\n' "$CONTAINER_USERNS" "$HOST_ID" "1"
        done < <(jq -r '.[].RunMeta.IdMaps | to_entries[] | "\(.key):\(.value)"' "$METADATA")

        # write static subids (if configured)
        while (( $# > 0 )); do
            write_subid printf '%s:%s\n' "$CONTAINER_USERNS" "$1"
            shift
        done

        # write base subid range
        local SUBID_BASE="$(awk -F ":" -v USER="$CONTAINER_USERNS" -v UID="$CONTAINER_USERNS_UID" \
            '($1 == USER || $1 == UID) && ($3 == 65536) { print $2; exit }' \
            "$SUBID_BAK")"
        [ -n "$SUBID_BASE" ] || { echo "Unsuitable ${FILE@Q} for user ${CONTAINER_USERNS@Q}:" \
            "The mappings don't include a suitable mapping for the base user namespace" >&2; return 1; }

        write_subid printf '%s:%s:%s\n' "$CONTAINER_USERNS" "$SUBID_BASE" "65536"

        # finish subid file
        write_subid awk -F ":" -v USER="$CONTAINER_USERNS" -v UID="$CONTAINER_USERNS_UID" \
            '{ if ($1 == USER || $1 == UID) { found=1 } else if (found) { print } }' \
            "$SUBID_BAK"

        echo + "exec 3>&-" >&2
        exec 3>&-

        cmd chmod 644 "$SUBID_BAK"
        cmd chmod 644 "$SUBID_TMP"

        # move subid file in place
        cmd cmp -s "$FILE" "$SUBID_BAK"
        if ! cmp -s "$FILE" "$SUBID_BAK"; then
            echo "Failed updating ${FILE@Q}: File has been changed" >&2
            return 1
        fi

        cmd mv -f "$SUBID_BAK" "$FILE-"
        cmd mv -f "$SUBID_TMP" "$FILE"
    }

    local TAG="${TAGS%% *}"

    # check whether subid management is enabled
    # if it is indeed enabled, we run as root, i.e. don't care about permissions
    if [ -z "$MANAGE_SUBIDS" ]; then
        echo "Unable to manage subids in '/etc/subuid' and '/etc/subgid': This feature has been disabled" >&2
        exit 1
    fi

    # check image
    check_image "$IMAGE:$TAG"

    echo + "DIGEST=\"\$(podman image inspect --format '{{.Digest}}' $(quote "$IMAGE:$TAG") | sed -ne 's/^sha256:\(.*\)$/\1/p')\"" >&2
    local DIGEST="$(podman image inspect --format '{{.Digest}}' "$IMAGE:$TAG" | sed -ne 's/^sha256:\(.*\)$/\1/p')"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE:$TAG@$DIGEST"

    local METADATA="$ARCHIVES_PATH/$IMAGE/$DIGEST/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    # update /etc/subuid and /etc/subgid
    subid_update -u "$METADATA" "${STATIC_SUBUIDS[@]}" || return 1
    subid_update -g "$METADATA" "${STATIC_SUBGIDS[@]}" || return 1
}
