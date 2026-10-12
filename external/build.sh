#!/bin/bash
set -e

pushd "$(dirname "$0")"

# Check if environment variables are defined
if [[ -z $NAME || -z $RUNNER_OS || -z $FLAGS ]]; then
    echo "One or more required environment variables are not defined."
    exit 1
fi

# 容器内通常已经是 root 且没有 sudo，这里允许 SUDO 为空（为空则直接执行命令）
SUDO=$(command -v sudo || true)

# 判断当前是否为 Ubuntu 18.04（bionic）环境，该版本已结束标准支持
IsBionic() {
    [[ -f /etc/os-release ]] && grep -q '^VERSION_ID="18.04"' /etc/os-release
}

# 版本号比较：$1 大于等于 $2 时返回 0
VersionGE() {
    [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]
}

# 确保 CMake 不低于 3.16（18.04 自带的 3.10 无法构建 SDL3）
EnsureModernCmake() {
    local required="3.16"
    local target="3.28.3"

    # 复用上一次已解压的版本，避免在增量构建时重复下载
    local cached
    cached=$(ls -d "/opt/cmake-${target}-linux-"* 2>/dev/null | head -n1 || true)
    if [[ -n $cached ]]; then
        export PATH="${cached}/bin:$PATH"
        return 0
    fi

    local version
    version=$(cmake --version 2>/dev/null | head -n1 | awk '{print $NF}')
    if [[ -n $version ]] && VersionGE "$version" "$required"; then
        return 0
    fi

    echo "CMake '${version:-not found}' is older than ${required}, installing ${target}..."

    # 官方仅提供 x86_64/aarch64 预编译包，其余架构（如 armhf）退回源码编译
    local package
    case "$(uname -m)" in
        x86_64)  package="cmake-${target}-linux-x86_64" ;;
        aarch64) package="cmake-${target}-linux-aarch64" ;;
        *)
            InstallCmakeFromSource "$target"
            return 0
            ;;
    esac
    wget -q -O /tmp/cmake.tar.gz \
        "https://github.com/Kitware/CMake/releases/download/v${target}/${package}.tar.gz"
    tar -xzf /tmp/cmake.tar.gz -C /opt
    export PATH="/opt/${package}/bin:$PATH"
}

# 官方没有 armhf 预编译包，只能在目标机源码编译（仅 linux-arm 平台会走到这里）
InstallCmakeFromSource() {
    local target="$1"
    wget -q -O "/tmp/cmake-${target}.tar.gz" \
        "https://github.com/Kitware/CMake/releases/download/v${target}/cmake-${target}.tar.gz"
    tar -xzf "/tmp/cmake-${target}.tar.gz" -C /tmp
    pushd "/tmp/cmake-${target}"
    ./bootstrap --parallel="$(nproc)" -- -DCMAKE_USE_OPENSSL=OFF
    make -j"$(nproc)"
    make install
    popd
}

# 18.04 自带的 libwayland 仅 1.16，低于 SDL3 要求的 1.18，
# 会导致 Wayland 视频后端被静默禁用，这里源码编译 1.22 以保留 Wayland 支持。
# 安装到 /opt 而非默认的 /usr/local，避免污染 pkg-config 默认搜索路径而影响其它架构。
# 32 位目标（i386）需额外以 -m32 编译出 32 位版本，装到独立 prefix
InstallModernWayland() {
    local target="1.22.0"
    local prefix="/opt/wayland-${target}"
    local build_dir="/tmp/wayland-build-${target}"
    local cross_arg=""
    local native_arg=""
    if [[ $TARGET_APT_ARCH == :i386 ]]; then
        prefix="/opt/wayland-${target}-i386"
        build_dir="/tmp/wayland-build-${target}-i386"
        # 让 meson 以 32 位编译，并只搜索 32 位的依赖（如 expat）
        export CFLAGS="-m32"
        export CXXFLAGS="-m32"
        export LDFLAGS="-m32"
        export PKG_CONFIG_LIBDIR="/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig"
    elif [[ -n $CROSS_PREFIX ]]; then
        prefix="/opt/wayland-${target}-${CROSS_TRIPLET%%-*}"
        build_dir="/tmp/wayland-build-${target}-${CROSS_TRIPLET%%-*}"
        # 生成 meson 交叉文件，用目标工具链编译出对应架构的 wayland
        local cross_file="/tmp/meson-cross-${CROSS_TRIPLET}.txt"
        printf '%s\n' \
            '[binaries]' \
            "c = '${CROSS_PREFIX}gcc'" \
            "cpp = '${CROSS_PREFIX}g++'" \
            "ar = '${CROSS_PREFIX}ar'" \
            "strip = '${CROSS_PREFIX}strip'" \
            "pkgconfig = 'pkg-config'" \
            '' \
            '[host_machine]' \
            "system = 'linux'" \
            "cpu_family = '${CROSS_TRIPLET%%-*}'" \
            "cpu = '${CROSS_TRIPLET%%-*}'" \
            "endian = 'little'" > "$cross_file"
        cross_arg="--cross-file=${cross_file}"
    fi

    echo "Building libwayland ${target} into ${prefix} to keep the Wayland backend enabled..."
    python3 -m pip install --upgrade "pip<22"
    python3 -m pip install "meson==0.61.5"   # 0.61.x 是最后支持 Python 3.6 的版本
    wget -q -O "/tmp/wayland-${target}.tar.xz" \
        "https://gitlab.freedesktop.org/wayland/wayland/-/releases/${target}/downloads/wayland-${target}.tar.xz"
    tar -xJf "/tmp/wayland-${target}.tar.xz" -C /tmp

    # 交叉编译时，wayland 要求 build-time 的 wayland-scanner 与源码版本严格一致，
    # 因此先用宿主编译器准备一个可在本机运行的 native scanner
    if [[ -n $CROSS_PREFIX ]]; then
        local native_prefix="/opt/wayland-${target}-native"
        if [[ ! -x "${native_prefix}/bin/wayland-scanner" ]]; then
            echo "Preparing native wayland-scanner ${target} for cross build..."
            rm -rf "/tmp/wayland-native-${target}"
            # 显式限定宿主架构的 pkg-config 路径，避免误用目标架构的依赖
            env -u CFLAGS -u CXXFLAGS -u LDFLAGS -u PKG_CONFIG_PATH \
                PKG_CONFIG_LIBDIR="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/pkgconfig:/usr/share/pkgconfig" \
                meson setup "/tmp/wayland-native-${target}" "/tmp/wayland-${target}" \
                --prefix="${native_prefix}" --libdir=lib \
                -Ddocumentation=false -Dtests=false -Ddtd_validation=false
            ninja -C "/tmp/wayland-native-${target}" install
        fi
        export PATH="${native_prefix}/bin:${PATH}"
        # 交叉构建时 meson 查询 native 依赖（wayland-scanner）会走 native file 指定的 pkg-config 路径，
        # 用它指向 native 1.22 的 .pc，避免取到默认路径里的 1.16 而报版本不符
        printf '%s\n' \
            '[binaries]' \
            "pkgconfig = 'pkg-config'" \
            '' \
            '[built-in options]' \
            "pkg_config_path = '${native_prefix}/lib/pkgconfig:/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/pkgconfig:/usr/share/pkgconfig'" \
            > "/tmp/meson-native-${CROSS_TRIPLET}.txt"
        native_arg="--native-file=/tmp/meson-native-${CROSS_TRIPLET}.txt"
    fi

    rm -rf "${build_dir}"
    # dtd_validation 默认需要 libxml2（会牵出 libicu 依赖，混合架构下易冲突），这里关闭；
    # 它仅影响 scanner 构建时的 XML 校验，不影响产物功能
    meson setup "${build_dir}" "/tmp/wayland-${target}" ${cross_arg} ${native_arg} \
        --prefix="${prefix}" --libdir=lib \
        -Ddocumentation=false -Dtests=false -Ddtd_validation=false
    ninja -C "${build_dir}" install
    # 仅在本进程内生效，供后续 SDL 的配置与构建使用（PKG_CONFIG_PATH 优先于 PKG_CONFIG_LIBDIR）
    export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
}

if [[ $RUNNER_OS == 'Linux' ]]; then
# Setup Linux dependencies
    # 交叉编译模式：通过 CROSS_PREFIX 指定工具链前缀（如 aarch64-linux-gnu- / arm-linux-gnueabihf-）
    if [[ -n $CROSS_PREFIX ]]; then
        CROSS_TRIPLET="${CROSS_PREFIX%-}"

        # arm64/armhf 属 ports 架构，必须由 ports.ubuntu.com 提供软件源；
        # 同时把主归档源限定为 amd64，避免 apt 去主源查找 arm 包（会 404）干扰依赖解析
        $SUDO sed -i -E 's@^deb( \[[^]]*\])? @deb [arch=amd64] @' /etc/apt/sources.list
        printf '%s\n' \
            'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports bionic main restricted universe multiverse' \
            'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports bionic-updates main restricted universe multiverse' \
            'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports bionic-security main restricted universe multiverse' \
            > /tmp/ports.list
        $SUDO cp /tmp/ports.list /etc/apt/sources.list.d/ports.list
    fi

    case "$TARGET_APT_ARCH" in
        :i386)  $SUDO dpkg --add-architecture i386 ;;
        :arm64) $SUDO dpkg --add-architecture arm64 ;;
        :armhf) $SUDO dpkg --add-architecture armhf ;;
    esac

    if [[ $TARGET_APT_ARCH == :i386 ]]; then
        # 多架构环境下 pkg-config 默认优先解析 64 位的 .pc，会让 -m32 编译混入 64 位头文件而失败，
        # 因此限定只搜索 i386 的 pkg-config 目录
        export PKG_CONFIG_LIBDIR="/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig"
    elif [[ -n $CROSS_PREFIX ]]; then
        # 交叉编译：pkg-config 只搜索目标架构目录
        export PKG_CONFIG_LIBDIR="/usr/lib/${CROSS_TRIPLET}/pkgconfig:/usr/share/pkgconfig"
    fi

    $SUDO apt-get update -y -qq

    # if [[ $TARGET_APT_ARCH == :i386 ]]; then
    #     # Workaround GitHub's ubuntu-20.04 image issue <https://github.com/actions/virtual-environments/issues/4589>
    #     $SUDO apt-get install -y --allow-downgrades libpcre2-8-0=10.34-7
    # fi

    if [[ -n $CROSS_PREFIX ]]; then
        # 交叉编译：安装并使用目标工具链（包名形如 gcc-aarch64-linux-gnu）
        GCC="gcc-${CROSS_TRIPLET}"
        GPP="g++-${CROSS_TRIPLET}"
    elif [[ $NAME != 'linux-x86' && $NAME != 'linux-x64' ]]; then
        GCC="gcc"
        GPP="g++"
    else
        GCC="gcc-multilib"
        GPP="g++-multilib"
    fi

    # 混合架构下 apt 一次性批量解析 libpango/libharfbuzz 依赖链偶发失败（"not going to be installed"），
    # 这里先把该依赖链单独装好，避免后续批量安装被牵连
    if [[ -n $CROSS_PREFIX ]]; then
        $SUDO apt-get install -y "libpango1.0-dev$TARGET_APT_ARCH" || true
    fi

    # 注意：pkg-config 是宿主侧构建工具，不能加 $TARGET_APT_ARCH 后缀，
    # 否则目标架构二进制会覆盖 /usr/bin/pkg-config，宿主执行时报 Exec format error
    $SUDO apt-get install -y \
        $GCC \
        $GPP \
        git \
        cmake \
        ninja-build \
        libwayland-bin \
        wayland-protocols \
        meson \
        pkg-config \
        libasound2-dev$TARGET_APT_ARCH \
        libdbus-1-dev$TARGET_APT_ARCH \
        libegl1-mesa-dev$TARGET_APT_ARCH \
        libgl1-mesa-dev$TARGET_APT_ARCH \
        libgles2-mesa-dev$TARGET_APT_ARCH \
        libglu1-mesa-dev$TARGET_APT_ARCH \
        libgtk-3-dev$TARGET_APT_ARCH \
        libibus-1.0-dev$TARGET_APT_ARCH \
        libpango1.0-dev$TARGET_APT_ARCH \
        libpulse-dev$TARGET_APT_ARCH \
        libsndio-dev$TARGET_APT_ARCH \
        libfribidi-dev$TARGET_APT_ARCH \
        libthai-dev$TARGET_APT_ARCH \
        libudev-dev$TARGET_APT_ARCH \
        libwayland-dev$TARGET_APT_ARCH \
        libx11-dev$TARGET_APT_ARCH \
        libxcursor-dev$TARGET_APT_ARCH \
        libxext-dev$TARGET_APT_ARCH \
        libxi-dev$TARGET_APT_ARCH \
        libxinerama-dev$TARGET_APT_ARCH \
        libxkbcommon-dev$TARGET_APT_ARCH \
        libxrandr-dev$TARGET_APT_ARCH \
        libxss-dev$TARGET_APT_ARCH \
        libxt-dev$TARGET_APT_ARCH \
        libxv-dev$TARGET_APT_ARCH \
        libxxf86vm-dev$TARGET_APT_ARCH \
        libdrm-dev$TARGET_APT_ARCH \
        libgbm-dev$TARGET_APT_ARCH \
        libpulse-dev$TARGET_APT_ARCH

    # 18.04 需要额外工具链：新版 CMake（自带 3.10 不满足 SDL3）与满足要求的 Wayland
    if IsBionic; then
        $SUDO apt-get install -y --no-install-recommends wget ca-certificates
        EnsureModernCmake
        # libexpat / libffi 是构建 wayland 的必需依赖，须与目标架构保持一致
        $SUDO apt-get install -y --no-install-recommends \
            python3-pip xz-utils libexpat1-dev$TARGET_APT_ARCH libffi-dev$TARGET_APT_ARCH
        # 交叉编译还需先用宿主工具链构建 native wayland-scanner；
        # 该 native 构建按宿主 pkg-config 路径解析依赖（见 InstallModernWayland），
        # 所以 expat/libffi 的宿主架构版本也必须安装，否则报 Dependency "libffi" not found
        if [[ -n $CROSS_PREFIX ]]; then
            $SUDO apt-get install -y --no-install-recommends libexpat1-dev libffi-dev
        fi
        InstallModernWayland

        # 18.04 的 libsndio-dev 不随包提供 sndio.pc，SDL 会因此检测不到 sndio 音频后端，这里补一个最小 .pc
        if ! pkg-config --exists sndio; then
            printf 'Name: sndio\nDescription: sndio library\nVersion: 1.1.0\nLibs: -lsndio\nCflags:\n' > /tmp/sndio.pc
            $SUDO cp /tmp/sndio.pc /usr/share/pkgconfig/sndio.pc
        fi
    fi

    # if [[ $TARGET_APT_ARCH != :i386 ]]; then
    #     # Build libdecor.
    #     # This is required so that window decorations can work on wayland.
    #     # The support will only be enabled in SDL, but we're not shipping the libdecor binaries
    #     # because making them work from a c# app as everything else does (via runtimes) is too difficult.
    #     # Also skip i386 because attempting to support this for i386 is a pain.
    #     # Special shoutouts to gnome for refusing to support server-side decorations.
    #     git clone https://gitlab.freedesktop.org/libdecor/libdecor.git
    #     cd libdecor
    #     git checkout 0.2.2
    #     meson build --buildtype release
    #     $SUDO meson install -C build
    #     cd ..
    # fi
fi

# Build SDL
pushd SDL
git reset --hard HEAD || echo "Failed to clean up the repository"

if [[ $RUNNER_OS == 'Windows' ]]; then
    echo "Patching SDL to not include gameinput.h"
    sed -i 's/#include <gameinput.h>/#_include <gameinput.h>/g' CMakeLists.txt
fi

# 交叉编译：生成 CMake 工具链文件并追加到参数
if [[ -n $CROSS_PREFIX ]]; then
    TOOLCHAIN_FILE="/tmp/cmake-toolchain-${CROSS_TRIPLET}.cmake"
    # 注意：不要设置 CMAKE_FIND_ROOT_PATH=/usr/<triplet>（那是 Debian 的 sysroot 布局）。
    # Ubuntu 使用多架构布局 /usr/lib/<triplet>，误设后 find_library/find_path 会全部失效，
    # 导致 KMSDRM 等后端退化成静态链接并编译失败。这里只保留 PROGRAM 不重定向（构建工具用宿主）。
    printf '%s\n' \
        'set(CMAKE_SYSTEM_NAME Linux)' \
        "set(CMAKE_SYSTEM_PROCESSOR ${CROSS_TRIPLET%%-*})" \
        "set(CMAKE_C_COMPILER ${CROSS_PREFIX}gcc)" \
        "set(CMAKE_CXX_COMPILER ${CROSS_PREFIX}g++)" \
        'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' > "$TOOLCHAIN_FILE"
    FLAGS="$FLAGS -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE"
fi

cmake -B build $FLAGS -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DSDL_SHARED_ENABLED_BY_DEFAULT=ON -DSDL_STATIC_ENABLED_BY_DEFAULT=ON
cmake --build build/ --config Release
# install_output 位于工作目录内无需提权；且 sudo 会重置 PATH 导致退回系统旧版 cmake
cmake --install build/ --prefix install_output --config Release
popd

# Move build lib into correct folders
if [[ $RUNNER_OS == 'Windows' ]]; then
    cp SDL/install_output/bin/SDL3.dll ../runtimes/$NAME/native/SDL3.dll
elif [[ $RUNNER_OS == 'Linux' ]]; then
    cp SDL/install_output/lib/libSDL3.so ../runtimes/$NAME/native/libSDL3.so
elif [[ $RUNNER_OS == 'macOS' ]]; then
    cp SDL/install_output/lib/libSDL3.dylib ../runtimes/$NAME/native/libSDL3.dylib
fi

popd
