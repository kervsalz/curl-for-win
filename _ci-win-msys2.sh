#!/usr/bin/env bash

# Copyright 2016-present Viktor Szakats. See LICENSE.md

set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

pacman --noconfirm --ask 20 --noprogressbar --sync --refresh --sysupgrade --sysupgrade
pacman --noconfirm --ask 20 --noprogressbar --sync --refresh --sysupgrade --sysupgrade
pacman --noconfirm --ask 20 --noprogressbar --sync --needed \
  mingw-w64-{x86_64,i686}-{clang,cmake,jq,python3-pip,rsync,gettext,osslsigncode} \
  zip

./_build.sh
