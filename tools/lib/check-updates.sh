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
    echo + "BUILDER_USER=\"$BUILDER_USER\"" >&2
    echo + "BUILDER_IMAGE=\"$BUILDER_IMAGE\"" >&2
    echo + "ARCHIVES_PATH=\"$ARCHIVES_PATH\"" >&2
    echo + "CONFIG_PATH=\"$CONFIG_PATH\"" >&2
}

command_exec() {
    check_builder

    echo + "podman run --name $CONTAINER … $IMAGE apache-check-updates --verbose" >&2
    run_builder apache-check-updates --verbose
}
