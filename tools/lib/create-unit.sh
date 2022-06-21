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

envsubst() {
    local VARIABLES="$(for ARG in "$@"; do
        awk 'match($0, /^([a-zA-Z_][a-zA-Z0-9_]*)=/, m) {print sprintf("${%s}", m[1])}' <<< "$ARG"
    done)"

    env -i -C "/" "$@" \
        sh -c 'envsubst "$1"' 'envsubst' "$VARIABLES"
}

systemd_escape() {
    local RESULT=""
    local QUOTE_REGEX="$(printf '[ \t\n\"]')"
    for ARG in "$@"; do
        ARG="$(sed -e 's/\$/\$\$/g' -e 's/%/%%/g' -e 's/\\/\\\\/g' <<< "$ARG")"
        ! [[ "$ARG" =~ $QUOTE_REGEX ]] || ARG="\"$(sed -e 's/\t/\\t/g' -e 's/"/\\"/g' <<< "$ARG")\""
        RESULT+=" $ARG"
    done

    echo "${RESULT:1}"
}

action_info() {
    echo + "IMAGE=${IMAGE@Q}" >&2
    echo + "UNIT=${UNIT@Q}" >&2
    echo + "UNIT_TEMPLATE=${UNIT_TEMPLATE@Q}" >&2
    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
}

action_exec() {
    local UNIT_PATH="/etc/systemd/system/$UNIT"
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"

    # check systemd unit
    if [ -h "$UNIT_PATH" ] && [ "$(realpath "$UNIT_PATH")" == "/dev/null" ]; then
        echo "Invalid Systemd unit '$UNIT': Unit is masked" >&2
        exit 1
    else
        if unit_loaded "$UNIT"; then
            if [ ! -e "$UNIT_PATH" ]; then
                echo "Invalid Systemd unit '$UNIT': Unit is loaded, but unit file '$UNIT_PATH' is invalid: No such file or directory" >&2
                exit 1
            elif [ ! -f "$UNIT_PATH" ]; then
                echo "Invalid Systemd unit '$UNIT': Unit is loaded, but unit file '$UNIT_PATH' is invalid: Not a file" >&2
                exit 1
            fi
        elif [ -e "$UNIT_PATH" ]; then
            if [ ! -f "$UNIT_PATH" ]; then
                echo "Invalid Systemd unit '$UNIT': Invalid unit file '$UNIT_PATH': Not a file" >&2
                exit 1
            else
                echo "Invalid Systemd unit '$UNIT': Invalid unit file '$UNIT_PATH': Unit not loaded" >&2
                exit 1
            fi
        fi
    fi

    # check image
    check_image "$IMAGE"

    echo + "IMAGE_ID=\"\$(podman inspect --format '{{.Id}}' $(quote "$IMAGE"))\"" >&2
    local IMAGE_ID="$(podman inspect --format '{{.Id}}' "$IMAGE")"

    echo + "DIGEST=\"\$(podman inspect --format '{{.Digest}}' $(quote "$IMAGE") | sed -ne 's/^sha256:\(.*\)$/\1/p')\"" >&2
    local DIGEST="$(podman inspect --format '{{.Digest}}' "$IMAGE" | sed -ne 's/^sha256:\(.*\)$/\1/p')"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE@$DIGEST"

    local METADATA="$ARCHIVES_PATH/$NAME/$DIGEST/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    # read create command
    echo + "CREATE_COMMAND=( \$(jq -r '.[][\"CreateCommand\"]' $(quote "$METADATA")) )" >&2

    local CREATE_COMMAND=()
    for (( INDEX=0, MAX="$(jq '.[]["CreateCommand"] | length' "$METADATA")" ; INDEX < MAX ; INDEX++ )); do
        CREATE_COMMAND+=( "$(jq -r --argjson INDEX "$INDEX" '.[]["CreateCommand"][$INDEX]' "$METADATA")" )
    done

    if [ "${CREATE_COMMAND[0]}" != "podman" ] || [ "${CREATE_COMMAND[1]}" != "create" ] || [ "${CREATE_COMMAND[-1]}" != "$IMAGE_ID" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid metadata of image '$IMAGE': Invalid create command: ${CREATE_COMMAND[@]}" >&2
        exit 1
    fi

    # write systemd unit
    echo + "SYSTEMD_EXEC=\"\$(systemd_escape -d \"\${CREATE_COMMAND[@]:2}\")\"" >&2
    SYSTEMD_EXEC="$(systemd_escape -d "${CREATE_COMMAND[@]:2}")"

    if [ ! -e "$UNIT_TEMPLATE" ]; then
        echo "Invalid Systemd unit template '$UNIT_TEMPLATE': No such file or directory" >&2
        exit 1
    elif [ ! -f "$UNIT_TEMPLATE" ]; then
        echo "Invalid Systemd unit template '$UNIT_TEMPLATE': Not a file" >&2
        exit 1
    elif [ ! -r "$UNIT_TEMPLATE" ]; then
        echo "Invalid Systemd unit template '$UNIT_TEMPLATE': Permission denied" >&2
        exit 1
    fi

    echo + "envsubst '…' < $(quote "./systemd-templates/container-unit.service") > $(quote "$UNIT_PATH")" >&2
    envsubst \
        IMAGE="$IMAGE" \
        CONTAINER="$CONTAINER" \
        UNIT="$UNIT" \
        PODMAN_RUN_ARGS="$SYSTEMD_EXEC" \
        < "$UNIT_TEMPLATE" \
        > "$UNIT_PATH"

    # reload systemd daemon
    echo + "systemctl daemon-reload" >&2
    __systemctl daemon-reload
}
