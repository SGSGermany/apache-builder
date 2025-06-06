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

    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
}

action_exec() {
    local TAG="${TAGS%% *}"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE:$TAG"

    echo + "DIGEST=\"\$(readlink $(quote "$ARCHIVES_PATH/$IMAGE/$TAG"))\"" >&2
    local DIGEST="$(readlink "$ARCHIVES_PATH/$IMAGE/$TAG")"

    # delete old images in OCI archive
    echo + "for CHECK_TAG in $(quote "$ARCHIVES_PATH/$IMAGE/")*; do … ; done" >&2

    for CHECK_TAG in "$ARCHIVES_PATH/$IMAGE/"*; do
        if [ -h "$CHECK_TAG" ]; then
            [ "$(readlink "$CHECK_TAG")" != "$DIGEST" ] || continue

            cmd rm -f "$CHECK_TAG"
        elif [ -d "$CHECK_TAG" ]; then
            [ "$(basename "$CHECK_TAG")" != "$DIGEST" ] || continue

            cmd rm -rf "$CHECK_TAG"
        else
            cmd rm -f "$CHECK_TAG"
        fi
    done

    # delete old images in Podman storage
    echo + "while IFS=' ' read -r CHECK_IMAGE_ID CHECK_DIGEST; do … ; done \\" >&2
    echo + "    < <(podman images --filter reference=$(quote "$IMAGE") --format '{{.Id}} {{.Digest}}' | sort -k 1 -u)" >&2

    while IFS=' ' read -r CHECK_IMAGE_ID CHECK_DIGEST; do
        [ "$(sed -ne 's/^sha256:\(.*\)$/\1/p' <<< "$CHECK_DIGEST")" != "$DIGEST" ] || continue

        echo + "[ \"\$(podman ps --filter ancestor=$CHECK_DIGEST --filter status=running --format running)\" == \"running\" ]" >&2
        if [ "$(podman ps --filter ancestor="$CHECK_DIGEST" --filter status="running" --format 'running')" == "running" ]; then
            continue
        fi

        cmd podman rmi "$CHECK_IMAGE_ID"
    done < <(podman images --filter reference="$IMAGE" --format '{{.Id}} {{.Digest}}' | sort -k 1 -u)
}
