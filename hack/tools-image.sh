#!/bin/bash

set -eu

release_image=$("${INSTALL_DIR}/openshift-install" version | awk '/^release image/{print $3}')
tools_sha=$("${INSTALL_DIR}/oc" adm release info "$release_image" | awk '/^\s*tools\s+/{print $2}')

echo "quay.io/okd/scos-content@${tools_sha}"
