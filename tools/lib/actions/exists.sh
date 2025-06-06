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

    local METADATA="$ARCHIVES_PATH/$IMAGE/$TAG/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    echo + "IMAGE_ID=\"\$(jq -r '.[][\"Id\"]' $(quote "$METADATA"))\"" >&2
    IMAGE_ID="$(jq -r '.[]["Id"]' "$METADATA")"

    cmd podman image exists "$IMAGE_ID"
}
