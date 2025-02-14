#!/usr/bin/env bash

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

extra=''
[[ "${CW_CONFIG:-}" = *'boringssl'* ]] && extra="${extra} go nasm"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
brew update >/dev/null
# shellcheck disable=SC2086
brew install coreutils mingw-w64 llvm \
             dos2unix osslsigncode openssh wine-stable ${extra}
wineboot --init

./_build.sh
