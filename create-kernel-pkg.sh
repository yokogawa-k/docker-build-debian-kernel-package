#!/bin/bash
# vi: ts=4 sw=4 sts=0 et:

set -e
set -u
#set -x

LATEST=${LATEST:-$(curl -sL https://www.kernel.org/finger_banner | awk '/^The latest stable/ {print $11} ')}

BASEURL=${BASEURL:-"https://cdn.kernel.org/pub/linux/kernel/"}
#BASEURL=${BASEURL:-"http://ftp.jaist.ac.jp/pub/Linux/kernel.org/linux/kernel"}
#BASEURL=${BASEURL:-"http://ftp.iij.ad.jp/pub/linux/kernel/linux/kernel"}
BASEDIR=/usr/src
KERNEL_DIR=${BASEDIR}/linux-${LATEST}
AUFS_REPOS=${BASEDIR}/aufs4-standalone
CUSTOM_NAME=${CUSTOM_NAME:-'aufs'}
CUSTOM_REVISION=${CUSTOM_REVISION:-1}

function _get_kernel_source() {
    ARCFILE=${BASEDIR}/linux-${LATEST}.tar.xz
    echo "get kernel files(${LATEST})"
    curl "${BASEURL}/${URL_PATH}/linux-${LATEST}.tar.xz" -o "${ARCFILE}"
    echo "extract kernel files"
    tar xJf "${ARCFILE}" -C "${BASEDIR}"
}

function _patch_aufs() {
    git clone https://github.com/sfjro/aufs4-standalone.git ${AUFS_REPOS}
    cd ${AUFS_REPOS}
    git fetch --all --tags
    git checkout -f "origin/${AUFS_VERSION}"
    if patch -sN -p1 -u -d "${KERNEL_DIR}" -i ${AUFS_REPOS}/aufs4-kbuild.patch; then
        patch -sN -p1 -u -d "${KERNEL_DIR}" -i ${AUFS_REPOS}/aufs4-base.patch
        patch -sN -p1 -u -d "${KERNEL_DIR}" -i ${AUFS_REPOS}/aufs4-mmap.patch
        patch -sN -p1 -u -d "${KERNEL_DIR}" -i ${AUFS_REPOS}/aufs4-standalone.patch
        cp -av ${AUFS_REPOS}/Documentation/* "${KERNEL_DIR}/Documentation"
        cp -av ${AUFS_REPOS}/fs/* "${KERNEL_DIR}/fs/"
        cp -av ${AUFS_REPOS}/include/uapi/linux/aufs_type.h "${KERNEL_DIR}/include/uapi/linux/"
    fi
}

function setup() {
    _get_kernel_source
    _patch_aufs
    cp -v ${BASEDIR}/kernel-config "${KERNEL_DIR}/.config"
    cd "${KERNEL_DIR}"
    make olddefconfig
}

function _check_kernel_config_for_docker() {
    local URL="https://raw.githubusercontent.com/docker/docker/master/contrib/check-config.sh"
    local CHK_CONFIG_SH=/usr/src/check-config.sh
    curl ${URL} -o ${CHK_CONFIG_SH}
    chmod +x ${CHK_CONFIG_SH}
    ${CHK_CONFIG_SH} "${KERNEL_DIR}/.config"
}

function _check_kernel_config_for_personal() {
    local CHK_CONFIG_SH=/usr/src/check-kernel-config.sh
    ${CHK_CONFIG_SH} "${KERNEL_DIR}/.config"
}

function check() {
    if [ -f "${KERNEL_DIR}/.config" ]; then
        :
    else
        echo >&2 "${KERNEL_DIR}/.config not found."
        echo >&2 "Setup kernel .config."
        setup
    fi
    _check_kernel_config_for_docker
    _check_kernel_config_for_personal
}

function _exec_make_kpkg() {
    local TARGET=$1
    time make-kpkg --rootcmd fakeroot --jobs "$(nproc)" --append-to-version "-${CUSTOM_REVISION}-${CUSTOM_NAME}" --revision "${REVISION}" --initrd "${TARGET}"
}

function build() {
    if [ -f "${KERNEL_DIR}/.config" ]; then
        :
    else
        check
    fi
    cd "${KERNEL_DIR}"
    _exec_make_kpkg kernel_image
    _exec_make_kpkg kernel_headers
}

function usage() {
    echo >&2 "Usage: ${0} COMMAND"
    echo >&2 ""
    echo >&2 "Commands:"
    echo >&2 "    all     setup, check, build"
    echo >&2 "    setup   download kernel source and apply aufs-patch"
    echo >&2 "    check   check '.config'(kernel config)"
    echo >&2 "    build   build Debian kernel packages"
    exit 3
}

## MAIN 

case ${LATEST} in
    *rc*)
        KERNEL_VERSION=${LATEST}
        AUFS_VERSION=aufs4.x-rcN
        URL_PATH=v4.x/testing
        ;;
    4.[0-9]*.[0-9]*)
        KERNEL_VERSION=${LATEST}
        AUFS_VERSION=aufs${KERNEL_VERSION%\.*}
        URL_PATH=v4.x
        ;;
    4.[0-9]*)
        KERNEL_VERSION=${LATEST}.0
        AUFS_VERSION=aufs${KERNEL_VERSION%\.*}
        URL_PATH=v4.x
        ;;
    *)
        echo >&2 "${LATEST} is unsupportd kernel version."
        exit 4
        ;;
esac

if [ "$#" -ne 1 ]; then
    usage
fi

REVISION=${KERNEL_VERSION}+${CUSTOM_REVISION}.${CUSTOM_NAME/-/+}

case "${1}" in
    all)
        setup
        check
        build
        ;;
    setup)
        setup
        ;;
    check)
        check
        ;;
    build)
        build
        ;;
    *)
        usage
esac
