#!/bin/bash

set -e

# component revisions to check out:
vpx_rev="HEAD"
x264_rev="HEAD"
x265_rev="HEAD"
fdk_aac_rev="HEAD"
ffmpeg_rev="HEAD"
# each will be set to the actual commit sha (git describe --abbrev)


while (( $# > 0 )); do
    case $1 in
         --vpx-rev)
             vpx_rev=$2
             shift; shift;;
         --x264-rev)
             x264_rev=$2
             shift; shift;;
         --fdk_aac-rev)
             fdk_aac_rev=$2
             shift; shift;;
         --x265-rev)
             x265_rev=$2
             shift; shift;;
         --ffmpeg-rev)
             ffmpeg_rev=$2
             shift; shift;;
         --help)
             echo "
Build a static executable of ffmpeg, pulling the latest (or specific) revisions of
x264, x265, fdk_aac, vpx. Revisions (see revisions(7), hg()) can be specified with:

 --vpx-rev REV
 --x264-rev REV
 --x265-rev REV
 --fdk_aac-rev REV
 --ffmpeg-rev REV
"
             exit 0
             ;;
    esac
done

echo "
Building ffmpeg with components at revisions:

  libvpx: $vpx_rev
    x264: $x264_rev
    x265: $x265_rev
 fdk_aac: $fdk_aac_rev
  ffmpeg: $ffmpeg_rev
"


PREFIX="$(pwd)/ffmpeg_build"
PATH=$HOME/bin:$PATH

common_config_options="--enable-static --disable-shared"

# this needs to be exported for opus.pc to be found. No idea why.
export CFLAGS="$CFLAGS -fPIC" CXXFLAGS="$CFLAGS"
export LDFLAGS="$LDFLAGS -L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

mkdir -p ffmpeg_sources ffmpeg_build ~/bin


function do_yum {
    sudo -nl yum 2&>1 >/dev/null || { echo "
This script needs to run \`sudo yum\`.
One way to enable the user running this script to do this is by adding a file in /etc/sudoers.d/ with the following contents:

Cmnd_Alias PKG_MANAGERS = /bin/yum
`whoami` ALL=(ALL) NOPASSWD: PKG_MANAGERS

"; exit 1; }

    sudo -n yum -y update
    sudo -n yum -y upgrade

    sudo -n yum install -y \
         epel-release

    sudo -n yum remove -y \
         nasm yasm  # these are too old wrt ffmpeg requirements: we will have to build them from sources

    sudo -n yum install -y \
         autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial pkgconfig zlib-devel \
         libass-devel \
         SDL SDL-devel \
         libva-devel \
         libvdpau-devel \
         libxcb-devel \
         libXfixes-devel
}

function do_apt {
    sudo -nl apt-get 2&>1 >/dev/null || { echo "
This script needs to run \`sudo apt-get\`.
One way to enable the user running this script to do this is by adding a file in /etc/sudoers.d/ with the following contents:

Cmnd_Alias PKG_MANAGERS = /usr/bin/apt-get
$(whoami) ALL=(ALL) NOPASSWD: PKG_MANAGERS

(Do \`apt-get install sudo\` if necessay.)
"; exit 1; }

    sudo -n apt-get update -y
    sudo -n apt-get upgrade -y

    sudo -n apt-get remove -y \
         nasm yasm  # these are too old wrt ffmpeg requirements: we will have to build them from sources

    sudo -n apt-get install -y \
         autoconf automake build-essential libtool pkg-config texinfo cmake git mercurial curl \
         libass-dev \
         libfreetype6-dev \
         libsdl2-dev \
         libtheora-dev \
         libva-dev \
         libvdpau-dev \
         libvorbis-dev \
         libxcb1-dev \
         libxcb-shm0-dev \
         libxcb-xfixes0-dev \
         zlib1g-dev
}




function install_yasm {
    local s=yasm-1.3.0
    local t=$s.tar.gz

    (cd ffmpeg_sources
     curl -O -L http://www.tortall.net/projects/yasm/releases/$t
     tar xzf $t
     (cd $s
      ./configure --prefix="$PREFIX" --bindir="$HOME/bin"
      make
      make install)
     rm -rf $s)
}

function install_nasm {
    local s=nasm-2.14.02
    local t=$s.tar.bz2

    (cd ffmpeg_sources
     curl -O -L http://www.nasm.us/pub/nasm/releasebuilds/2.14.02/$t
     tar xjf $t
     (cd $s
      ./autogen.sh
      ./configure --prefix="$PREFIX" --bindir="$HOME/bin"
      make
      make install)
     rm -rf $s)
}


function is_version_ok {
    (IFS="."
     local v=($1) req=($2)
     if (( ${v[0]} < ${req[0]} )); then false; else
         if (( ${v[0]} > ${req[0]} )); then true; else
             if (( ${v[1]} < ${req[1]} )); then false; else
                 if (( ${v[1]} > ${req[1]} )); then true; else
                     if test -n "${v[2]}" && (( ${v[2]} < ${req[2]} )); then false; else
                         true
                     fi
                 fi
             fi
         fi
     fi)
}


function check_yasm {
    if which yasm >/dev/null 2>&1; then
        local v=$(yasm --version | awk '/^yasm / { print $2 }')
        if is_version_ok "$v" "1.3.0"; then
            echo "found yasm version $v"
        else
            echo "found yasm version $v, which is too old"
            false
        fi
    else
        echo "yasm not found"
        false
    fi
}

function check_nasm {
    if which nasm >/dev/null 2>&1; then
        local v=$(nasm --version | awk '/^NASM / { print $3 }')
        if is_version_ok "$v" "2.14.0"; then
            echo "found nasm version $v"
        else
            echo "found nasm version $v, which is too old"
            false
        fi
    else
        echo "nasm not found"
        false
    fi
}


function check_lame {
    if which lame >/dev/null 2>&1; then
        local v=$(lame --version | awk '/^LAME / { print $4 }')
        if is_version_ok "$v" "3.100"; then
            echo "found lame version $v"
        else
            echo "found lame version $v, which is too old"
            false
        fi
    else
        echo "lame not found"
        false
    fi
}

function check_opus {
    local v=$(pkg-config --modversion opus)
    if test -n "$v"; then
        if is_version_ok "$v" "1.2.1"; then
            echo "found opus version $v"
        else
            echo "found opus version $v, which is too old"
            false
        fi
    else
        echo "opus not found"
        false
    fi
}

function check_libogg {
    local v=$(pkg-config --modversion ogg)
    if test -n "$v"; then
        if is_version_ok "$v" "1.3.3"; then
            echo "found ogg version $v"
        else
            echo "found ogg version $v, which is too old"
            false
        fi
    else
        echo "ogg not found"
        false
    fi
}

function check_libvorbis {
    local v=$(pkg-config --modversion vorbis)
    if test -n "$v"; then
        if is_version_ok "$v" "1.3.5"; then
            echo "found vorbis version $v"
        else
            echo "found vorbis version $v, which is too old"
            false
        fi
    else
        echo "vorbis not found"
        false
    fi
}




function build_lame {
    echo "
- - - -  lame"

    if check_lame; then
        true
    else
        local s="lame-3.100"
        local t=$s.tar.gz

        (cd ffmpeg_sources
         test -r "$t" || curl -O -L http://downloads.sourceforge.net/project/lame/lame/3.100/$t
         test -d $s || tar xzf $t
         (cd $s
          ./configure --prefix="$PREFIX" --bindir="$HOME/bin" --enable-nasm $common_config_options
          make $MAKEOPTS
          make install)
         rm -rf $s)
    fi
}


function build_opus {
    echo "
- - - -  opus"

    if check_opus; then
        true
    else
        local s="opus-1.2.1"
        local t=$s.tar.gz

        (cd ffmpeg_sources
         test -r "$t" || curl -O -L https://archive.mozilla.org/pub/opus/$t
         test -d $s || tar xzf $t
         (cd $s
          ./configure --prefix="$PREFIX" $common_config_options
          make $MAKEOPTS
          make install)
        rm -rf $s)
    fi
}

function build_libogg {
    echo "
- - - -  libogg"

    if check_libogg; then
        true
    else
        local s="libogg-1.3.3"
        local t=$s.tar.gz

        (cd ffmpeg_sources
         test -r "$t" || curl -O -L http://downloads.xiph.org/releases/ogg/$t
         test -d $s || tar xzf $t
         (cd $s
          ./configure --prefix="$PREFIX" --bindir="$HOME/bin" $common_config_options
          make $MAKEOPTS
          make install)
        rm -rf $s)
    fi
}

function build_libvorbis {
    echo "
- - - -  libvorbis"

    if check_libvorbis; then
        true
    else
        local s="libvorbis-1.3.5"
        local t=$s.tar.gz

        (cd ffmpeg_sources
         test -r "$t" || curl -O -L http://downloads.xiph.org/releases/vorbis/$t
         test -d $s || tar xzf $t
         (cd $s
          ./configure --prefix="$PREFIX" --bindir="$HOME/bin" $common_config_options
          make $MAKEOPTS
          make install)
        rm -rf $s)
    fi
}


## pull specific versions for the builds below

function build_x264 {
    echo "
- - - -  x264"
    local d=x264

    cd ffmpeg_sources
    if test -d $d; then
        cd $d
        git pull
        make distclean || :
    else
        git clone https://code.videolan.org/videolan/x264.git
        cd $d
    fi

    git checkout "$x264_rev" || return 1
    export x264_rev=$(git describe --always --abbrev HEAD)

    ./configure --prefix="$PREFIX" --bindir="$HOME/bin" --disable-cli --enable-pic $common_config_options
    make $MAKEOPTS && make install && cd ../..
}


function build_x265 {
    echo "
- - - -  x265"
    local d=x265_git

    cd ffmpeg_sources
    if test -d $d; then
        cd $d
        rm -rf build/linux/*
    else
        git clone https://bitbucket.org/multicoreware/x265_git
        cd $d
    fi

    git checkout "$x265_rev" || return 1
    export x265_rev=$(git describe --always --abbrev HEAD)

    cd build/linux
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_SHARED:bool=off ../../source
    make $MAKEOPTS && make install && mv $PREFIX/bin/x265 $HOME/bin && rmdir $PREFIX/bin && cd ../../..
}


function build_fdk {
    echo "
- - - -  fdk_aac"
    local d=fdk-aac

    cd ffmpeg_sources
    if test -d $d; then
        cd $d
        git pull
        make distclean || :
    else
        git clone https://github.com/mstorsjo/fdk-aac
        cd $d
    fi

    git checkout "$fdk_aac_rev" || return 1
    fdk_aac_rev=$(git describe --always --abbrev HEAD)

    autoreconf -fiv
    ./configure --prefix="$PREFIX" $common_config_options
    make $MAKEOPTS && make install && cd ../..
}


function build_vpx {
    echo "
- - - -  vpx"
    local d=libvpx

    cd ffmpeg_sources
    if test -d $d; then
        cd $d
        git pull
        make distclean || :
    else
        git clone https://chromium.googlesource.com/webm/libvpx.git
        cd $d
    fi

    git checkout "$vpx_rev" || return 1
    export vpx_rev=$(git describe --always --abbrev HEAD)

    ./configure --prefix="$PREFIX" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm --enable-pic $common_config_options
    make $MAKEOPTS && make install && cd ../..
}


function build_ffmpeg {
    echo "
- - - -  ffmpeg
"
    local d=ffmpeg

    cd ffmpeg_sources
    if test -d $d; then
        cd $d
        git pull
        make distclean || :
    else
        git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
        cd $d
    fi

    git checkout "$ffmpeg_rev" || return 1
    export ffmpeg_rev=$(git describe --always --abbrev HEAD)

    ./configure \
        --prefix="$PREFIX" \
        --pkg-config-flags="--static" \
        --extra-libs="-lm -lpthread" \
        --enable-pic \
        --bindir="$HOME/bin" \
        --extra-cflags="-I$PREFIX/include -static" \
        --enable-gpl \
        --enable-libass \
        --enable-libfreetype \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libvorbis \
        --enable-libvpx \
        --enable-libfdk_aac \
        --enable-libfdk-aac \
        --enable-libx264 \
        --enable-nonfree \
        --enable-static
    make $MAKEOPTS && make install &&
    echo "
Build successfully completed: ffmpeg installed in $PREFIX
" && cd ../..
}

test -r /etc/redhat-release && do_yum
test -r /etc/debian_version && do_apt

check_yasm || install_yasm || { echo "Failed to build yasm"; exit 3; }
check_nasm || install_nasm || { echo "Failed to build nasm"; exit 3; }

# these are at static versions
build_lame
build_opus
build_libogg
build_libvorbis

# some others are pulled newest
build_x264 || exit 2
build_x265 || exit 2
build_fdk || exit 2
build_vpx || exit 2

build_ffmpeg || exit 2

echo

ffmpeg -version || exit 4

echo "
ffmpeg binary successfully built with these components:

  libvpx: $vpx_rev
    x264: $x264_rev
    x265: $x265_rev
 fdk_aac: $fdk_aac_rev
  ffmpeg: $ffmpeg_rev

"
