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
    echo + "UNIT=\"$UNIT\"" >&2
}

command_exec() {
    check_unit "$UNIT"
    check_image "$IMAGE"

    echo + "systemctl disable $UNIT" >&2
    __systemctl disable "$UNIT"
}
