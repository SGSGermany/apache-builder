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
    echo + "IMAGE=${IMAGE@Q}" >&2
    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
}

action_exec() {
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"
    local TAG="$(basename "$IMAGE" | cut -s -d ':' -f 2 | cut -d '@' -f 1)"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE"

    echo + "DIGEST=\"\$(readlink $(quote "$ARCHIVES_PATH/$NAME/$TAG"))\"" >&2
    local DIGEST="$(readlink "$ARCHIVES_PATH/$NAME/$TAG")"

    # delete old images in OCI archive
    echo + "for CHECK_TAG in $(quote "$ARCHIVES_PATH/$NAME/")*; do … ; done" >&2

    for CHECK_TAG in "$ARCHIVES_PATH/$NAME/"*; do
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
    echo + "    < <(podman images --filter reference=$(quote "$NAME") --format '{{.Id}} {{.Digest}}' | sort -k 1 -u)" >&2

    while IFS=' ' read -r CHECK_IMAGE_ID CHECK_DIGEST; do
        [ "$(sed -ne 's/^sha256:\(.*\)$/\1/p' <<< "$CHECK_DIGEST")" != "$DIGEST" ] || continue

        cmd podman rmi "$CHECK_IMAGE_ID"
    done < <(podman images --filter reference="$NAME" --format '{{.Id}} {{.Digest}}' | sort -k 1 -u)
}
