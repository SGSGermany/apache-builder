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
    echo + "BASE_IMAGE=${BASE_IMAGE@Q}" >&2
    echo + "IMAGE=${IMAGE@Q}" >&2
    echo + "TAGS=${TAGS@Q}" >&2

    echo + "BUILDER_USER=${BUILDER_USER@Q}" >&2
    echo + "BUILDER_IMAGE=${BUILDER_IMAGE@Q}" >&2
    echo + "BUILDER_CONTAINER=${BUILDER_CONTAINER@Q}" >&2
    echo + "BUILDER_CONFIG=${BUILDER_CONFIG@Q}" >&2
    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
}

action_exec() {
    check_builder
    run_builder apache-check-updates --verbose
}
