#!/bin/bash
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

set -eu -o pipefail
export LC_ALL=C

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-archlinux.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

echo + "CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

pkg_install "$CONTAINER" \
    podman \
    buildah \
    skopeo \
    rsync \
    jq

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

user_add "$CONTAINER" apache-builder 65536 "/var/local/apache-builder"

cmd buildah run "$CONTAINER" -- \
    chown -R -h apache-builder:apache-builder "/var/local/apache-builder"

cleanup "$CONTAINER"

cmd buildah config \
    --env BUILDAH_ISOLATION="chroot" \
    "$CONTAINER"

cmd buildah config \
    --volume "/etc/apache-builder" \
    --volume "/var/local/apache-builder/archives" \
    "$CONTAINER"

cmd buildah config \
    --workingdir "/var/local/apache-builder" \
    --entrypoint '[ "/entrypoint.sh" ]' \
    --cmd '[ "apache-builder" ]' \
    --user "apache-builder" \
    "$CONTAINER"

cmd buildah config \
    --annotation org.opencontainers.image.title="Apache Builder" \
    --annotation org.opencontainers.image.description="A container to build Apache containers." \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/apache-builder" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

con_commit "$CONTAINER" "${TAGS[@]}"
