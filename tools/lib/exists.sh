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

command_info() {
    echo + "IMAGE=\"$IMAGE\"" >&2
    echo + "ARCHIVES_PATH=\"$ARCHIVES_PATH\"" >&2
}

command_exec() {
    local NAME="$(basename "$IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)"
    local TAG="$(basename "$IMAGE" | cut -s -d ':' -f 2 | cut -d '@' -f 1)"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE"

    echo + "METADATA=\"$ARCHIVES_PATH/$NAME/$TAG/metadata.json\"" >&2
    local METADATA="$ARCHIVES_PATH/$NAME/$TAG/metadata.json"

    echo + "IMAGE_ID=\"\$(jq -r '.[][\"Id\"]' $METADATA)\"" >&2
    IMAGE_ID="$(jq -r '.[]["Id"]' "$METADATA")"

    echo + "podman image exists $IMAGE_ID" >&2
    podman image exists "$IMAGE_ID"
}
