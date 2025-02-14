#!/bin/sh

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# https://cmake.org/cmake/help/latest/manual/cmake-properties.7.html
# https://cmake.org/cmake/help/latest/manual/cmake-variables.7.html

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

export _NAM _VER _OUT _BAS _DST

_NAM="$(basename "$0" | cut -f 1 -d '.' | sed 's/-cmake//')"
_VER="$1"

(
  cd "${_NAM}"  # mandatory component

if [ "${CURL_VER_}" = '8.2.1' ]; then

  cache='CMakeCache.txt'
  rm -f "${cache}"

  rm -r -f "${_PKGDIR}" "${_BLDDIR}-shared" "${_BLDDIR}-static"

  # Build

  # CMake cannot build everything in one pass. With BUILD_SHARED_LIBS enabled,
  # it does not build a static lib, and links curl.exe against libcurl DLL
  # with no option to change this. We need to split it into two passes:
  #   1. build shared libcurl DLL + implib + .def
  #   2. build static libcurl lib + statically linked curl EXE
  for pass in shared static; do

    options=''
    CPPFLAGS=''

    [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ] && options="${options} -DCMAKE_AR=${AR_NORMALIZE}"

    LIBS=''
    LDFLAGS=''
    LDFLAGS_BIN="${_LDFLAGS_BIN_GLOBAL}"
    LDFLAGS_LIB=''

    if [ ! "${_BRANCH#*unicode*}" = "${_BRANCH}" ]; then
      options="${options} -DENABLE_UNICODE=ON"
    fi

    if [ "${pass}" = 'shared' ]; then
      options="${options} -DCMAKE_SHARED_LIBRARY_SUFFIX_C=${_CURL_DLL_SUFFIX}.dll"
      _DEF_NAME="libcurl${_CURL_DLL_SUFFIX}.def"
      LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--output-def,${_DEF_NAME}"
    fi

    if [ "${CW_MAP}" = '1' ]; then
      if [ "${pass}" = 'shared' ]; then
        _MAP_NAME_LIB="libcurl${_CURL_DLL_SUFFIX}.map"
        LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,-Map,${_MAP_NAME_LIB}"
      else
        _MAP_NAME_BIN='curl.map'
        LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,-Map,${_MAP_NAME_BIN}"
      fi
    fi

    # Ugly hack. Everything breaks without this due to the accidental ordering
    # of libs and objects, and offering no universal way to (re)insert libs at
    # specific positions. Linker complains about a missing --end-group, then
    # adds it automatically anyway.
    if [ "${_LD}" = 'ld' ]; then
      LDFLAGS="${LDFLAGS} -Wl,--start-group"
    fi

    # Link lib dependencies in static mode. Implied by `-static` for curl,
    # but required for libcurl, which would link to shared libs by default.
    LDFLAGS="${LDFLAGS} -Wl,-Bstatic"

    if [ ! "${_BRANCH#*werror*}" = "${_BRANCH}" ]; then
      options="${options} -DCURL_WERROR=ON"
    fi

    if [ ! "${_BRANCH#*debug*}" = "${_BRANCH}" ]; then
      options="${options} -DENABLE_DEBUG=ON"
    fi

    if [ ! "${_BRANCH#*pico*}" = "${_BRANCH}" ] || \
       [ ! "${_BRANCH#*nano*}" = "${_BRANCH}" ]; then
      options="${options} -DCURL_DISABLE_ALTSVC=ON"
    fi

    if [ ! "${_BRANCH#*pico*}" = "${_BRANCH}" ]; then
      options="${options} -DCURL_DISABLE_CRYPTO_AUTH=ON"
      options="${options} -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON"
      options="${options} -DCURL_DISABLE_FTP=ON"
      options="${options} -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_SMTP=ON"
      options="${options} -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON"
    else
      [ "${_BRANCH#*noftp*}" != "${_BRANCH}" ] && options="${options} -DCURL_DISABLE_FTP=ON"
      LIBS="${LIBS} -lwldap32"
    fi

    if [ -n "${_ZLIB}" ]; then
      options="${options} -DUSE_ZLIB=ON"
      options="${options} -DZLIB_INCLUDE_DIR=${_TOP}/${_ZLIB}/${_PP}/include"
      options="${options} -DZLIB_LIBRARY=${_TOP}/${_ZLIB}/${_PP}/lib/libz.a"
    else
      options="${options} -DUSE_ZLIB=OFF"
    fi
    if [ -d ../brotli ] && [ "${_BRANCH#*nobrotli*}" = "${_BRANCH}" ]; then
      options="${options} -DCURL_BROTLI=ON"
      options="${options} -DBROTLI_INCLUDE_DIR=${_TOP}/brotli/${_PP}/include"
      options="${options} -DBROTLIDEC_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlidec.a"
      options="${options} -DBROTLICOMMON_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlicommon.a"
    else
      options="${options} -DCURL_BROTLI=OFF"
    fi
    if [ -d ../zstd ] && [ "${_BRANCH#*nozstd*}" = "${_BRANCH}" ]; then
      options="${options} -DCURL_ZSTD=ON"
      options="${options} -DZstd_INCLUDE_DIR=${_TOP}/zstd/${_PP}/include"
      options="${options} -DZstd_LIBRARY=${_TOP}/zstd/${_PP}/lib/libzstd.a"
    else
      options="${options} -DCURL_ZSTD=OFF"
    fi

    h3=0

    if [ -n "${_OPENSSL}" ]; then
      options="${options} -DCURL_USE_OPENSSL=ON"
      options="${options} -DOPENSSL_ROOT_DIR=${_TOP}/${_OPENSSL}/${_PP}"
      options="${options} -DCURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG=ON"
      if [ "${_OPENSSL}" = 'boringssl' ]; then
        CPPFLAGS="${CPPFLAGS} -DCURL_BORINGSSL_VERSION=\\\"$(printf '%.8s' "${BORINGSSL_VER_}")\\\""
        CPPFLAGS="${CPPFLAGS} -DHAVE_SSL_SET0_WBIO"
        if [ "${_TOOLCHAIN}" = 'mingw-w64' ] && [ "${_CPU}" = 'x64' ] && [ "${_CRT}" = 'ucrt' ]; then  # FIXME
          LIBS="${LIBS} -Wl,-Bdynamic -lpthread -Wl,-Bstatic"
        else
          LIBS="${LIBS} -lpthread"
        fi
        h3=1
      elif [ "${_OPENSSL}" = 'libressl' ]; then
        h3=1
      elif [ "${_OPENSSL}" = 'quictls' ] || [ "${_OPENSSL}" = 'openssl' ]; then
        CPPFLAGS="${CPPFLAGS} -DHAVE_SSL_SET0_WBIO"
        [ "${_OPENSSL}" = 'quictls' ] && h3=1
      fi
    else
      options="${options} -DCURL_USE_OPENSSL=OFF"
    fi

    if [ -d ../wolfssl ]; then
      options="${options} -DCURL_USE_WOLFSSL=ON"
      options="${options} -DWolfSSL_INCLUDE_DIR=${_TOP}/wolfssl/${_PP}/include"
      options="${options} -DWolfSSL_LIBRARY=${_TOP}/wolfssl/${_PP}/lib/libwolfssl.a"
      CPPFLAGS="${CPPFLAGS} -DSIZEOF_LONG_LONG=8"
      h3=1
    fi

    if [ -d ../mbedtls ]; then
      options="${options} -DCURL_USE_MBEDTLS=ON"
      options="${options} -DMBEDTLS_INCLUDE_DIRS=${_TOP}/mbedtls/${_PP}/include"
      options="${options} -DMBEDTLS_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedtls.a"
      options="${options} -DMBEDX509_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedx509.a"
      options="${options} -DMBEDCRYPTO_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedcrypto.a"
    fi

    options="${options} -DCURL_USE_SCHANNEL=ON"
    CPPFLAGS="${CPPFLAGS} -DHAS_ALPN"

    if [ -d ../wolfssh ] && [ -d ../wolfssl ]; then
      # No native support, enable it manually.
      options="${options} -DCURL_USE_WOLFSSH=ON"
      CPPFLAGS="${CPPFLAGS} -DUSE_WOLFSSH"
      CPPFLAGS="${CPPFLAGS} -I${_TOP}/wolfssh/${_PP}/include"
      LDFLAGS="${LDFLAGS} -L${_TOP}/wolfssh/${_PP}/lib"
      LIBS="${LIBS} -lwolfssh"
    elif [ -d ../libssh ]; then
      # Detection picks OS-native copy. Only a manual configuration worked
      # to defeat CMake's wisdom.
      options="${options} -DCURL_USE_LIBSSH=OFF"
      options="${options} -DCURL_USE_LIBSSH2=OFF"
      CPPFLAGS="${CPPFLAGS} -DUSE_LIBSSH"
      CPPFLAGS="${CPPFLAGS} -DLIBSSH_STATIC"
      CPPFLAGS="${CPPFLAGS} -I${_TOP}/libssh/${_PP}/include"
      LDFLAGS="${LDFLAGS} -L${_TOP}/libssh/${_PP}/lib"
      LIBS="${LIBS} -lssh"
    elif [ -d ../libssh2 ]; then
      options="${options} -DCURL_USE_LIBSSH2=ON"
      options="${options} -DCURL_USE_LIBSSH=OFF"
      options="${options} -DLIBSSH2_INCLUDE_DIR=${_TOP}/libssh2/${_PP}/include"
      options="${options} -DLIBSSH2_LIBRARY=${_TOP}/libssh2/${_PP}/lib/libssh2.a"

      if [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ]; then
        # By passing -lssh2 _before_ -lcrypto (of openssl/libressl) to the
        # linker, DLL size becomes closer/identical to autotools/gnumake-built
        # DLLs. Otherwise this is not necessary, and there should not be any
        # functional difference. Could not find the reason for it.
        # File-offset-stripped-then-sorted .map files are identical either way.
        # It would be useful to have a linker option to sort object/lib inputs
        # to make output deterministic (these builds do not rely on ordering
        # side-effects.)
        LDFLAGS="${LDFLAGS} -L${_TOP}/libssh2/${_PP}/lib"
        LIBS="${LIBS} -lssh2"
      fi
    else
      options="${options} -DCURL_USE_LIBSSH=OFF"
      options="${options} -DCURL_USE_LIBSSH2=OFF"
    fi

    if [ -d ../nghttp2 ]; then
      options="${options} -DUSE_NGHTTP2=ON"
      options="${options} -DNGHTTP2_INCLUDE_DIR=${_TOP}/nghttp2/${_PP}/include"
      options="${options} -DNGHTTP2_LIBRARY=${_TOP}/nghttp2/${_PP}/lib/libnghttp2.a"
      CPPFLAGS="${CPPFLAGS} -DNGHTTP2_STATICLIB"
    else
      options="${options} -DUSE_NGHTTP2=OFF"
    fi

    [ "${_BRANCH#*noh3*}" = "${_BRANCH}" ] || h3=0

    if [ "${h3}" = '1' ] && [ -d ../nghttp3 ] && [ -d ../ngtcp2 ]; then
      options="${options} -DUSE_NGHTTP3=ON"
      options="${options} -DNGHTTP3_INCLUDE_DIR=${_TOP}/nghttp3/${_PP}/include"
      options="${options} -DNGHTTP3_LIBRARY=${_TOP}/nghttp3/${_PP}/lib/libnghttp3.a"
      CPPFLAGS="${CPPFLAGS} -DNGHTTP3_STATICLIB"

      options="${options} -DUSE_NGTCP2=ON"
      options="${options} -DNGTCP2_INCLUDE_DIR=${_TOP}/ngtcp2/${_PP}/include"
      options="${options} -DNGTCP2_LIBRARY=${_TOP}/ngtcp2/${_PP}/lib/libngtcp2.a"
      options="${options} -DCMAKE_LIBRARY_PATH=${_TOP}/ngtcp2/${_PP}/lib"
      CPPFLAGS="${CPPFLAGS} -DNGTCP2_STATICLIB"
    else
      options="${options} -DUSE_NGHTTP3=OFF"
      options="${options} -DUSE_NGTCP2=OFF"
    fi
    if [ -d ../cares ]; then
      options="${options} -DENABLE_ARES=ON"
      options="${options} -DCARES_INCLUDE_DIR=${_TOP}/cares/${_PP}/include"
      options="${options} -DCARES_LIBRARY=${_TOP}/cares/${_PP}/lib/libcares.a"
      CPPFLAGS="${CPPFLAGS} -DCARES_STATICLIB"
    fi
    if [ -d ../gsasl ]; then
      CPPFLAGS="${CPPFLAGS} -DUSE_GSASL"
      CPPFLAGS="${CPPFLAGS} -I${_TOP}/gsasl/${_PP}/include"
      LDFLAGS="${LDFLAGS} -L${_TOP}/gsasl/${_PP}/lib"
      LIBS="${LIBS} -lgsasl"
    fi
    if [ -d ../libidn2 ]; then
      options="${options} -DUSE_LIBIDN2=ON"
      CPPFLAGS="${CPPFLAGS} -I${_TOP}/libidn2/${_PP}/include"
      LDFLAGS="${LDFLAGS} -L${_TOP}/libidn2/${_PP}/lib"
      LIBS="${LIBS} -lidn2"

      if [ -d ../libpsl ] && [ -d ../libiconv ] && [ -d ../libunistring ]; then
        options="${options} -DUSE_LIBPSL=ON"
        options="${options} -DLIBPSL_INCLUDE_DIR=${_TOP}/libpsl/${_PP}/include"
        options="${options} -DLIBPSL_LIBRARY=${_TOP}/libpsl/${_PP}/lib/libpsl.a;${_TOP}/libiconv/${_PP}/lib/libiconv.a;${_TOP}/libunistring/${_PP}/lib/libunistring.a"
      fi

      if [ -d ../libiconv ]; then
        LDFLAGS="${LDFLAGS} -L${_TOP}/libiconv/${_PP}/lib"
        LIBS="${LIBS} -liconv"
      fi
      if [ -d ../libunistring ]; then
        LDFLAGS="${LDFLAGS} -L${_TOP}/libunistring/${_PP}/lib"
        LIBS="${LIBS} -lunistring"
      fi
    elif [ "${_BRANCH#*pico*}" = "${_BRANCH}" ]; then
      options="${options} -DUSE_LIBIDN2=OFF"
      options="${options} -DUSE_WIN32_IDN=ON"
    fi

    # Official method correctly enables the manual, but with the side-effect
    # of rebuilding tool_hugehelp.c (with empty content). We work around this
    # by enabling the manual directly via its C flag.
  # options="${options} -DUSE_MANUAL=ON"
    CPPFLAGS="${CPPFLAGS} -DUSE_MANUAL=1"

    if [ "${pass}" = 'shared' ]; then
      options="${options} -DBUILD_SHARED_LIBS=ON"
      options="${options} -DBUILD_CURL_EXE=OFF"
    else
      options="${options} -DBUILD_SHARED_LIBS=OFF"
      options="${options} -DBUILD_CURL_EXE=ON"
    fi

    if [ "${CW_DEV_LLD_REPRODUCE:-}" = '1' ] && [ "${_LD}" = 'lld' ]; then
      LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-exe.tar"
      LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-dll.tar"
    fi

    if [ -f "${cache}" ]; then
      mkdir "${_BLDDIR}-${pass}"
      mv "${cache}" "${_BLDDIR}-${pass}"
      # Keep certain "detected" values only. This also drops the line
      # '# For build in directory: <dir>', to avoid a warning about
      # a different than original build directory.
      grep -a -E '^(HAVE_|CMAKE_HAVE_|SIZEOF_|USE_WINCRYPT:)' "${_BLDDIR}-${pass}/${cache}" > "${_BLDDIR}-${pass}/${cache}.new"
      mv "${_BLDDIR}-${pass}/${cache}.new" "${_BLDDIR}-${pass}/${cache}"
    fi

    # shellcheck disable=SC2086
    cmake . -B "${_BLDDIR}-${pass}" ${_CMAKE_GLOBAL} ${options} \
      '-DCURL_CA_PATH=none' \
      '-DCURL_CA_BUNDLE=none' \
      '-DENABLE_THREADED_RESOLVER=ON' \
      '-DBUILD_TESTING=OFF' \
      '-DCURL_HIDDEN_SYMBOLS=ON' \
      '-DENABLE_WEBSOCKETS=ON' \
      "-DCMAKE_RC_FLAGS=${_RCFLAGS_GLOBAL}" \
      "-DCMAKE_C_FLAGS=${_CFLAGS_GLOBAL_CMAKE} ${_CFLAGS_GLOBAL} ${_CPPFLAGS_GLOBAL} ${CPPFLAGS} ${_LDFLAGS_GLOBAL} ${_LIBS_GLOBAL}" \
      "-DCMAKE_C_STANDARD_LIBRARIES=${LIBS}" \
      "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_BIN} ${LIBS}" \
      "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_LIB} ${LIBS}"  # --debug-find --debug-trycompile

    if [ "${pass}" = 'static' ]; then
      # When doing an out of tree build, this is necessary to avoid make
      # re-generating the embedded manual with blank content.
      if [ -f src/tool_hugehelp.c ]; then
        cp -p src/tool_hugehelp.c "${_BLDDIR}-${pass}/src/"
      elif [ -f src/tool_hugehelp.c.cvs ]; then
        # Copy the dummy replacement when building from a raw source tree.
        cp -p src/tool_hugehelp.c.cvs "${_BLDDIR}-${pass}/src/tool_hugehelp.c"
      fi
    fi

    make --directory="${_BLDDIR}-${pass}" --jobs="${_JOBS}" install "DESTDIR=$(pwd)/${_PKGDIR}" VERBOSE=1

    mv "${_BLDDIR}-${pass}/${cache}" .

    # Manual copy to DESTDIR

    if [ "${pass}" = 'shared' ]; then
      cp -p "${_BLDDIR}-${pass}/lib/${_DEF_NAME}" "${_PP}"/bin/
    fi

    if [ "${CW_MAP}" = '1' ]; then
      if [ "${pass}" = 'shared' ]; then
        cp -p "${_BLDDIR}-${pass}/lib/${_MAP_NAME_LIB}" "${_PP}"/bin/
      else
        cp -p "${_BLDDIR}-${pass}/src/${_MAP_NAME_BIN}" "${_PP}"/bin/
      fi
    fi
  done

else

  rm -r -f "${_PKGDIR}" "${_BLDDIR}"

  # Build

  options=''
  CPPFLAGS=''

  [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ] && options="${options} -DCMAKE_AR=${AR_NORMALIZE}"

  LIBS=''
  LDFLAGS=''
  LDFLAGS_BIN="${_LDFLAGS_BIN_GLOBAL}"
  LDFLAGS_LIB=''

  if [ ! "${_BRANCH#*unicode*}" = "${_BRANCH}" ]; then
    options="${options} -DENABLE_UNICODE=ON"
  fi

  options="${options} -DCMAKE_SHARED_LIBRARY_SUFFIX_C=${_CURL_DLL_SUFFIX}.dll"
  _DEF_NAME="libcurl${_CURL_DLL_SUFFIX}.def"
  LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--output-def,${_DEF_NAME}"

  if [ "${CW_MAP}" = '1' ]; then
    _MAP_NAME_LIB="libcurl${_CURL_DLL_SUFFIX}.map"
    LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,-Map,${_MAP_NAME_LIB}"
    _MAP_NAME_BIN='curl.map'
    LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,-Map,${_MAP_NAME_BIN}"
  fi

  # Ugly hack. Everything breaks without this due to the accidental ordering
  # of libs and objects, and offering no universal way to (re)insert libs at
  # specific positions. Linker complains about a missing --end-group, then
  # adds it automatically anyway.
  if [ "${_LD}" = 'ld' ]; then
    LDFLAGS="${LDFLAGS} -Wl,--start-group"
  fi

  # Link lib dependencies in static mode. Implied by `-static` for curl,
  # but required for libcurl, which would link to shared libs by default.
  LDFLAGS="${LDFLAGS} -Wl,-Bstatic"

  if [ ! "${_BRANCH#*werror*}" = "${_BRANCH}" ]; then
    options="${options} -DCURL_WERROR=ON"
  fi

  if [ ! "${_BRANCH#*debug*}" = "${_BRANCH}" ]; then
    options="${options} -DENABLE_DEBUG=ON"
  fi

  if [ ! "${_BRANCH#*pico*}" = "${_BRANCH}" ] || \
     [ ! "${_BRANCH#*nano*}" = "${_BRANCH}" ]; then
    options="${options} -DCURL_DISABLE_ALTSVC=ON"
  fi

  if [ ! "${_BRANCH#*pico*}" = "${_BRANCH}" ]; then
    options="${options} -DCURL_DISABLE_CRYPTO_AUTH=ON"
    options="${options} -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON"
    options="${options} -DCURL_DISABLE_FTP=ON"
    options="${options} -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_SMTP=ON"
    options="${options} -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON"
  else
    [ "${_BRANCH#*noftp*}" != "${_BRANCH}" ] && options="${options} -DCURL_DISABLE_FTP=ON"
    LIBS="${LIBS} -lwldap32"
  fi

  if [ -n "${_ZLIB}" ]; then
    options="${options} -DUSE_ZLIB=ON"
    options="${options} -DZLIB_INCLUDE_DIR=${_TOP}/${_ZLIB}/${_PP}/include"
    options="${options} -DZLIB_LIBRARY=${_TOP}/${_ZLIB}/${_PP}/lib/libz.a"
  else
    options="${options} -DUSE_ZLIB=OFF"
  fi
  if [ -d ../brotli ] && [ "${_BRANCH#*nobrotli*}" = "${_BRANCH}" ]; then
    options="${options} -DCURL_BROTLI=ON"
    options="${options} -DBROTLI_INCLUDE_DIR=${_TOP}/brotli/${_PP}/include"
    options="${options} -DBROTLIDEC_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlidec.a"
    options="${options} -DBROTLICOMMON_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlicommon.a"
  else
    options="${options} -DCURL_BROTLI=OFF"
  fi
  if [ -d ../zstd ] && [ "${_BRANCH#*nozstd*}" = "${_BRANCH}" ]; then
    options="${options} -DCURL_ZSTD=ON"
    options="${options} -DZstd_INCLUDE_DIR=${_TOP}/zstd/${_PP}/include"
    options="${options} -DZstd_LIBRARY=${_TOP}/zstd/${_PP}/lib/libzstd.a"
  else
    options="${options} -DCURL_ZSTD=OFF"
  fi

  h3=0

  if [ -n "${_OPENSSL}" ]; then
    options="${options} -DCURL_USE_OPENSSL=ON"
    options="${options} -DOPENSSL_ROOT_DIR=${_TOP}/${_OPENSSL}/${_PP}"
    options="${options} -DCURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG=ON"
    if [ "${_OPENSSL}" = 'boringssl' ]; then
      CPPFLAGS="${CPPFLAGS} -DCURL_BORINGSSL_VERSION=\\\"$(printf '%.8s' "${BORINGSSL_VER_}")\\\""
      if [ "${_TOOLCHAIN}" = 'mingw-w64' ] && [ "${_CPU}" = 'x64' ] && [ "${_CRT}" = 'ucrt' ]; then  # FIXME
        LIBS="${LIBS} -Wl,-Bdynamic -lpthread -Wl,-Bstatic"
      else
        LIBS="${LIBS} -lpthread"
      fi
      h3=1
    elif [ "${_OPENSSL}" = 'quictls' ] || [ "${_OPENSSL}" = 'libressl' ]; then
      h3=1
    fi
  else
    options="${options} -DCURL_USE_OPENSSL=OFF"
  fi

  if [ -d ../wolfssl ]; then
    options="${options} -DCURL_USE_WOLFSSL=ON"
    options="${options} -DWolfSSL_INCLUDE_DIR=${_TOP}/wolfssl/${_PP}/include"
    options="${options} -DWolfSSL_LIBRARY=${_TOP}/wolfssl/${_PP}/lib/libwolfssl.a"
    CPPFLAGS="${CPPFLAGS} -DSIZEOF_LONG_LONG=8"
    h3=1
  fi

  if [ -d ../mbedtls ]; then
    options="${options} -DCURL_USE_MBEDTLS=ON"
    options="${options} -DMBEDTLS_INCLUDE_DIRS=${_TOP}/mbedtls/${_PP}/include"
    options="${options} -DMBEDTLS_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedtls.a"
    options="${options} -DMBEDX509_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedx509.a"
    options="${options} -DMBEDCRYPTO_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedcrypto.a"
  fi

  options="${options} -DCURL_USE_SCHANNEL=ON"
  CPPFLAGS="${CPPFLAGS} -DHAS_ALPN"

  if [ -d ../wolfssh ] && [ -d ../wolfssl ]; then
    # No native support, enable it manually.
    options="${options} -DCURL_USE_WOLFSSH=ON"
    CPPFLAGS="${CPPFLAGS} -DUSE_WOLFSSH"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/wolfssh/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/wolfssh/${_PP}/lib"
    LIBS="${LIBS} -lwolfssh"
  elif [ -d ../libssh ]; then
    # Detection picks OS-native copy. Only a manual configuration worked
    # to defeat CMake's wisdom.
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DCURL_USE_LIBSSH2=OFF"
    CPPFLAGS="${CPPFLAGS} -DUSE_LIBSSH"
    CPPFLAGS="${CPPFLAGS} -DLIBSSH_STATIC"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/libssh/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/libssh/${_PP}/lib"
    LIBS="${LIBS} -lssh"
  elif [ -d ../libssh2 ]; then
    options="${options} -DCURL_USE_LIBSSH2=ON"
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DLIBSSH2_INCLUDE_DIR=${_TOP}/libssh2/${_PP}/include"
    options="${options} -DLIBSSH2_LIBRARY=${_TOP}/libssh2/${_PP}/lib/libssh2.a"

    if [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ]; then
      # By passing -lssh2 _before_ -lcrypto (of openssl/libressl) to the
      # linker, DLL size becomes closer/identical to autotools/gnumake-built
      # DLLs. Otherwise this is not necessary, and there should not be any
      # functional difference. Could not find the reason for it.
      # File-offset-stripped-then-sorted .map files are identical either way.
      # It would be useful to have a linker option to sort object/lib inputs
      # to make output deterministic (these builds do not rely on ordering
      # side-effects.)
      LDFLAGS="${LDFLAGS} -L${_TOP}/libssh2/${_PP}/lib"
      LIBS="${LIBS} -lssh2"
    fi
  else
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DCURL_USE_LIBSSH2=OFF"
  fi

  if [ -d ../nghttp2 ]; then
    options="${options} -DUSE_NGHTTP2=ON"
    options="${options} -DNGHTTP2_INCLUDE_DIR=${_TOP}/nghttp2/${_PP}/include"
    options="${options} -DNGHTTP2_LIBRARY=${_TOP}/nghttp2/${_PP}/lib/libnghttp2.a"
    CPPFLAGS="${CPPFLAGS} -DNGHTTP2_STATICLIB"
  else
    options="${options} -DUSE_NGHTTP2=OFF"
  fi

  [ "${_BRANCH#*noh3*}" = "${_BRANCH}" ] || h3=0

  if [ "${h3}" = '1' ] && [ -d ../nghttp3 ] && [ -d ../ngtcp2 ]; then
    options="${options} -DUSE_NGHTTP3=ON"
    options="${options} -DNGHTTP3_INCLUDE_DIR=${_TOP}/nghttp3/${_PP}/include"
    options="${options} -DNGHTTP3_LIBRARY=${_TOP}/nghttp3/${_PP}/lib/libnghttp3.a"
    CPPFLAGS="${CPPFLAGS} -DNGHTTP3_STATICLIB"

    options="${options} -DUSE_NGTCP2=ON"
    options="${options} -DNGTCP2_INCLUDE_DIR=${_TOP}/ngtcp2/${_PP}/include"
    options="${options} -DNGTCP2_LIBRARY=${_TOP}/ngtcp2/${_PP}/lib/libngtcp2.a"
    options="${options} -DCMAKE_LIBRARY_PATH=${_TOP}/ngtcp2/${_PP}/lib"
    CPPFLAGS="${CPPFLAGS} -DNGTCP2_STATICLIB"
  else
    options="${options} -DUSE_NGHTTP3=OFF"
    options="${options} -DUSE_NGTCP2=OFF"
  fi
  if [ -d ../cares ]; then
    options="${options} -DENABLE_ARES=ON"
    options="${options} -DCARES_INCLUDE_DIR=${_TOP}/cares/${_PP}/include"
    options="${options} -DCARES_LIBRARY=${_TOP}/cares/${_PP}/lib/libcares.a"
    CPPFLAGS="${CPPFLAGS} -DCARES_STATICLIB"
  fi
  if [ -d ../gsasl ]; then
    CPPFLAGS="${CPPFLAGS} -DUSE_GSASL"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/gsasl/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/gsasl/${_PP}/lib"
    LIBS="${LIBS} -lgsasl"
  fi
  if [ -d ../libidn2 ]; then
    options="${options} -DUSE_LIBIDN2=ON"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/libidn2/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/libidn2/${_PP}/lib"
    LIBS="${LIBS} -lidn2"

    if [ -d ../libpsl ] && [ -d ../libiconv ] && [ -d ../libunistring ]; then
      options="${options} -DUSE_LIBPSL=ON"
      options="${options} -DLIBPSL_INCLUDE_DIR=${_TOP}/libpsl/${_PP}/include"
      options="${options} -DLIBPSL_LIBRARY=${_TOP}/libpsl/${_PP}/lib/libpsl.a;${_TOP}/libiconv/${_PP}/lib/libiconv.a;${_TOP}/libunistring/${_PP}/lib/libunistring.a"
    fi

    if [ -d ../libiconv ]; then
      LDFLAGS="${LDFLAGS} -L${_TOP}/libiconv/${_PP}/lib"
      LIBS="${LIBS} -liconv"
    fi
    if [ -d ../libunistring ]; then
      LDFLAGS="${LDFLAGS} -L${_TOP}/libunistring/${_PP}/lib"
      LIBS="${LIBS} -lunistring"
    fi
  elif [ "${_BRANCH#*pico*}" = "${_BRANCH}" ]; then
    options="${options} -DUSE_LIBIDN2=OFF"
    options="${options} -DUSE_WIN32_IDN=ON"
  fi

  # Official method correctly enables the manual, but with the side-effect
  # of rebuilding tool_hugehelp.c (with empty content). We work around this
  # by enabling the manual directly via its C flag.
  # options="${options} -DUSE_MANUAL=ON"
  CPPFLAGS="${CPPFLAGS} -DUSE_MANUAL=1"

  if [ "${CW_DEV_LLD_REPRODUCE:-}" = '1' ] && [ "${_LD}" = 'lld' ]; then
    LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-exe.tar"
    LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-dll.tar"
  fi

  # shellcheck disable=SC2086
  cmake . -B "${_BLDDIR}" ${_CMAKE_GLOBAL} ${options} \
    '-DCURL_CA_PATH=none' \
    '-DCURL_CA_BUNDLE=none' \
    '-DBUILD_SHARED_LIBS=ON' \
    '-DBUILD_STATIC_LIBS=ON' \
    '-DBUILD_CURL_EXE=ON' \
    '-DBUILD_STATIC_CURL=ON' \
    '-DENABLE_THREADED_RESOLVER=ON' \
    '-DBUILD_TESTING=OFF' \
    '-DCURL_HIDDEN_SYMBOLS=ON' \
    '-DENABLE_WEBSOCKETS=ON' \
    "-DCMAKE_RC_FLAGS=${_RCFLAGS_GLOBAL}" \
    "-DCMAKE_C_FLAGS=${_CFLAGS_GLOBAL_CMAKE} ${_CFLAGS_GLOBAL} ${_CPPFLAGS_GLOBAL} ${CPPFLAGS} ${_LDFLAGS_GLOBAL} ${_LIBS_GLOBAL}" \
    "-DCMAKE_C_STANDARD_LIBRARIES=${LIBS}" \
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_BIN} ${LIBS}" \
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_LIB} ${LIBS}"  # --debug-find --debug-trycompile

  # When doing an out of tree build, this is necessary to avoid make
  # re-generating the embedded manual with blank content.
  if [ -f src/tool_hugehelp.c ]; then
    cp -p src/tool_hugehelp.c "${_BLDDIR}/src/"
  elif [ -f src/tool_hugehelp.c.cvs ]; then
    # Copy the dummy replacement when building from a raw source tree.
    cp -p src/tool_hugehelp.c.cvs "${_BLDDIR}/src/tool_hugehelp.c"
  fi

  make --directory="${_BLDDIR}" --jobs="${_JOBS}" install "DESTDIR=$(pwd)/${_PKGDIR}" VERBOSE=1

  # Manual copy to DESTDIR

  cp -p "${_BLDDIR}/lib/${_DEF_NAME}" "${_PP}"/bin/

  if [ "${CW_MAP}" = '1' ]; then
    cp -p "${_BLDDIR}/lib/${_MAP_NAME_LIB}" "${_PP}"/bin/
    cp -p "${_BLDDIR}/src/${_MAP_NAME_BIN}" "${_PP}"/bin/
  fi

fi

  . ../curl-pkg.sh
)
