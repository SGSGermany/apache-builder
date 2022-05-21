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
    echo + "UNIT=${UNIT@Q}" >&2
}

action_exec() {
    check_unit "$UNIT"
    check_image "$IMAGE"

    echo + "systemctl restart $(quote "$UNIT")" >&2
    __systemctl restart "$UNIT"
}
