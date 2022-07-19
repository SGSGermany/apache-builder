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
    local TAG="${TAGS%% *}"

    # check OCI archive
    check_oci_archive
    check_oci_image "$IMAGE:$TAG"

    echo + "DIGEST=\"\$(readlink $(quote "$ARCHIVES_PATH/$IMAGE/$TAG"))\"" >&2
    local DIGEST="$(readlink "$ARCHIVES_PATH/$IMAGE/$TAG")"

    local ARCHIVE="$ARCHIVES_PATH/$IMAGE/$DIGEST/image"
    echo + "ARCHIVE=${ARCHIVE@Q}" >&2

    local METADATA="$ARCHIVES_PATH/$IMAGE/$DIGEST/metadata.json"
    echo + "METADATA=${METADATA@Q}" >&2

    # check image metadata
    if ! jq -e --arg NAME "$IMAGE" '.[]["Name"] == $NAME' "$METADATA" > /dev/null; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid image '$IMAGE:$TAG': Invalid image name in OCI archive" >&2
        exit 1
    fi

    if ! jq -e --arg TAG "$TAG" '.[]["Tags"] | index($TAG)' "$METADATA" > /dev/null; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid image '$IMAGE:$TAG': Invalid image tags in OCI archive" >&2
        exit 1
    fi

    if [ "sha256:$DIGEST" != "$(skopeo inspect --format '{{.Digest}}' "oci-archive:$ARCHIVE")" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid image '$IMAGE:$TAG': Image digest mismatch" >&2
        exit 1
    fi

    # import image
    echo + "IMAGE_ID=\"\$(podman pull $(quote "oci-archive:$ARCHIVE"))\"" >&2
    local IMAGE_ID="$(podman pull "oci-archive:$ARCHIVE" || true)"

    if [ -z "$IMAGE_ID" ]; then
        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid image '$IMAGE:$TAG': \`podman pull\` failed" >&2
        exit 1
    fi

    if [ "$IMAGE_ID" != "$(jq -r '.[]["Id"]' "$METADATA")" ]; then
        cmd podman rmi "$IMAGE_ID" || true

        echo "Invalid OCI archive '$ARCHIVES_PATH': Invalid image '$IMAGE:$TAG': Image ID mismatch" >&2
        exit 1
    fi

    # tag image
    echo + "IMPORT_TAGS=( \$(jq -r '.[][\"Tags\"]' $(quote "$METADATA")) )" >&2

    local IMPORT_TAGS=()
    for (( INDEX=0, MAX="$(jq '.[]["Tags"] | length' "$METADATA")" ; INDEX < MAX ; INDEX++ )); do
        IMPORT_TAGS+=( "$(jq -r --argjson INDEX "$INDEX" '.[]["Tags"][$INDEX]' "$METADATA")" )
    done

    for IMPORT_TAG in "${IMPORT_TAGS[@]}"; do
        cmd podman tag "$IMAGE_ID" "$IMAGE:$IMPORT_TAG"
    done
}
