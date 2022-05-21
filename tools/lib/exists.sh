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

    local METADATA="$ARCHIVES_PATH/$NAME/$TAG/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    echo + "IMAGE_ID=\"\$(jq -r '.[][\"Id\"]' $(quote "$METADATA"))\"" >&2
    IMAGE_ID="$(jq -r '.[]["Id"]' "$METADATA")"

    cmd podman image exists "$IMAGE_ID"
}
