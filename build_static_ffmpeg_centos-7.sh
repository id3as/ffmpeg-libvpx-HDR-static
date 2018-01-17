#!/bin/sh

set -e

PREFIX="$(pwd)/ffmpeg_build"
PATH=$HOME/bin:$PATH
export CFLAGS="$CFLAGS -fPIC" CXXFLAGS="$CFLAGS"
export LDFLAGS="$LDFLAGS -L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export common_config_options="--enable-static --disable-shared"


mkdir -p ffmpeg_sources ffmpeg_build ~/bin


function do_yum {
    sudo -n yum install -y \
         epel-release

    # nasm yasm \  these are too old wrt ffmpeg requirements: we will have to build them from sources
    sudo -n yum install -y \
         autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial pkgconfig zlib-devel \
         libass-devel \
         SDL SDL-devel \
         libva-devel \
         libvdpau-devel \
         libxcb-devel \
         libXfixes-devel
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
    local s=nasm-2.13.02
    local t=$s.tar.bz2

    (cd ffmpeg_sources
     curl -O -L http://www.nasm.us/pub/nasm/releasebuilds/2.13.02/$t
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
        local v=`yasm --version | awk '/^yasm / { print $2 }'`
        if is_version_ok "$v" "1.3.0"; then
            echo "found yasm version $v"
        else
            echo "found yasm version $v, which is too old"
        fi
    else
        echo "yasm not found"
        false
    fi
}

function check_nasm {
    if which nasm >/dev/null 2>&1; then
        local v=`nasm --version | awk '/^NASM / { print $3 }'`
        if is_version_ok "$v" "2.13.0"; then
            echo "found nasm version $v"
        else
            echo "found nasm version $v, which is too old"
        fi
    else
        echo "nasm not found"
        false
    fi
}


function check_lame {
    if which lame >/dev/null 2>&1; then
        local v=`lame --version | awk '/^LAME / { print $4 }'`
        if is_version_ok "$v" "3.100"; then
            echo "found lame version $v"
        else
            echo "found lame version $v, which is too old"
        fi
    else
        echo "lame not found"
        false
    fi
}

function check_opus {
    local v=`pkg-config --modversion opus`
    if test -n "$v"; then
        if is_version_ok "$v" "1.2.1"; then
            echo "found opus version $v"
        else
            echo "found opus version $v, which is too old"
        fi
    else
        echo "opus not found"
        false
    fi
}

function check_libogg {
    local v=`pkg-config --modversion ogg`
    if test -n "$v"; then
        if is_version_ok "$v" "1.3.3"; then
            echo "found ogg version $v"
        else
            echo "found ogg version $v, which is too old"
        fi
    else
        echo "ogg not found"
        false
    fi
}

function check_libvorbis {
    local v=`pkg-config --modversion vorbis`
    if test -n "$v"; then
        if is_version_ok "$v" "1.3.5"; then
            echo "found vorbis version $v"
        else
            echo "found vorbis version $v, which is too old"
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




function build_newest_fdk {
    echo "
- - - -  newest fdk_aac"
    local d=fdk-aac

    (cd ffmpeg_sources
     if test -d $d; then
         cd $d
         git pull
         make distclean || :
     else
         git clone --depth 1 https://github.com/mstorsjo/fdk-aac
         cd $d
     fi
     autoreconf -fiv
     ./configure --prefix="$PREFIX" $common_config_options
     make $MAKEOPTS
     make install)
}


function build_newest_x264 {
    echo "
- - - -  newest x264"
    local d=x264

    (cd ffmpeg_sources
     if test -d $d; then
         cd $d
         git pull
         make distclean || :
     else
         git clone --depth 1 http://git.videolan.org/git/x264
         cd $d
     fi
     ./configure --prefix="$PREFIX" --bindir="$HOME/bin" $common_config_options
     make $MAKEOPTS
     make install)
}

function build_newest_x265 {
    echo "
- - - -  newest x265"
    local d=x265

    (cd ffmpeg_sources
     if test -d $d; then
         cd $d
         rm -rf build/linux/*
         hg update
     else
         hg clone https://bitbucket.org/multicoreware/x265
         cd $d
     fi
     cd build/linux
     cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_SHARED:bool=off ../../source
     make $MAKEOPTS
     make install
     mv $PREFIX/bin/x265 $HOME/bin
     rmdir $PREFIX/bin)
}

function build_newest_vpx {
    echo "
- - - -  newest vpx"
    local d=libvpx

    (cd ffmpeg_sources
     if test -d $d; then
         cd $d
         git pull
         make distclean || :
     else
         git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
         cd $d
     fi
     ./configure --prefix="$PREFIX" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm --enable-pic $common_config_options
     make $MAKEOPTS
     make install)
}


function build_ffmpeg {
    echo "
- - - -  newest ffmpeg
"
    (cd ffmpeg_sources
     curl -O -L https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2
     tar xjf ffmpeg-snapshot.tar.bz2
     cd ffmpeg
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
         --disable-ffserver \
         --enable-libx264 \
         --enable-nonfree \
         --enable-static
     make $MAKEOPTS
     make install
     hash -r)
}





sudo -nl yum >/dev/null || { echo "
This script needs to run \`sudo yum\`.
One way to enable the user running this script to do this is by adding a file in /etc/sudoers.d/ with the following contents:

  Cmnd_Alias PKG_MANAGERS = /bin/yum, /bin/rpm
  `whoami` ALL=(ALL) NOPASSWD: PKG_MANAGERS

"; exit 1; }

do_yum
check_yasm || install_yasm || { echo "Failed to build yasm"; exit 3; }
check_nasm || install_nasm || { echo "Failed to build nasm"; exit 3; }

# these are at static versions
build_lame
build_opus
build_libogg
build_libvorbis
# some others are pulled newest
build_newest_x264
build_newest_x265
build_newest_fdk
build_newest_vpx
build_ffmpeg
