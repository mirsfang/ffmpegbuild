#!/bin/bash

set -e
set -x

export TARGET=$1
export PREFIX=$2

if [ "$NDK" = "" ] || [ ! -d $NDK ]; then
	echo "NDK variable not set or path to NDK is invalid, exiting..."
	exit 1
fi

ARM_PLATFORM=$NDK/platforms/android-16/arch-arm/
ARM_PREBUILT=$NDK/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64

ARM64_PLATFORM=$NDK/platforms/android-21/arch-arm64/
ARM64_PREBUILT=$NDK/toolchains/aarch64-linux-android-4.9/prebuilt/darwin-x86_64

X86_PLATFORM=$NDK/platforms/android-16/arch-x86/
X86_PREBUILT=$NDK/toolchains/x86-4.9/prebuilt/darwin-x86_64

X86_64_PLATFORM=$NDK/platforms/android-21/arch-x86_64/
X86_64_PREBUILT=$NDK/toolchains/x86_64-4.9/prebuilt/darwin-x86_64

MIPS_PLATFORM=$NDK/platforms/android-16/arch-mips/
MIPS_PREBUILT=$NDK/toolchains/mipsel-linux-android-4.9/prebuilt/darwin-x86_64

MIPS64_PLATFORM=$NDK/platforms/android-21/arch-mips64/
MIPS64_PREBUILT=$NDK/toolchains/mips64el-linux-android-4.9/prebuilt/darwin-x86_64


FFMPEG_VERSION="4.1"
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    # 需要更新版本时打开下载功能
     echo "Downloading ffmpeg-${FFMPEG_VERSION}.tar.bz2"
     curl -LO http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2
    echo "extracting ffmpeg-${FFMPEG_VERSION}.tar.bz2"
    tar -xvf ffmpeg-${FFMPEG_VERSION}.tar.bz2
else
    echo "Using existing `pwd`/ffmpeg-${FFMPEG_VERSION}"
fi


if [ ! -d "x264" ]; then
    echo "Cloning x264"
    git clone git://git.videolan.org/x264.git x264
    # need `x264_bit_depth` in ffmpeg http://git.videolan.org/?p=x264.git;a=commit;h=71ed44c7312438fac7c5c5301e45522e57127db4
    cd x264 && git reset --hard 2451a72 && cd ..
else
    echo "Using existing `pwd`/x264"
fi


function build_one
{
if [ $ARCH == "arm" ]
then
    PLATFORM=$ARM_PLATFORM
    HOST=arm-linux-androideabi
    export CROSS_PREFIX=$ARM_PREBUILT/bin/$HOST-
#added by alexvas
elif [ $ARCH == "arm64" ]
then
    PLATFORM=$ARM64_PLATFORM
    HOST=aarch64-linux-android
    export CROSS_PREFIX=$ARM64_PREBUILT/bin/$HOST-
elif [ $ARCH == "mips" ]
then
    PLATFORM=$MIPS_PLATFORM
    HOST=mipsel-linux-android
    export CROSS_PREFIX=$MIPS_PREBUILT/bin/$HOST-
elif [ $ARCH == "mips64" ]
then
    PLATFORM=$MIPS64_PLATFORM
    HOST=mips64el-linux-android
    export CROSS_PREFIX=$MIPS64_PREBUILT/bin/$HOST-
elif [ $ARCH == "x86_64" ]
then
    PLATFORM=$X86_64_PLATFORM
    HOST=x86_64-linux-android
    export CROSS_PREFIX=$X86_64_PREBUILT/bin/$HOST-
elif [ $ARCH == "i686" ]
then
    PLATFORM=$X86_PLATFORM
    HOST=i686-linux-android
    export CROSS_PREFIX=$X86_PREBUILT/bin/$HOST-
fi

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CPP="${CROSS_PREFIX}cpp"
export CXX="${CROSS_PREFIX}g++"
export CC="${CROSS_PREFIX}gcc"
export LD="${CROSS_PREFIX}ld"
export AR="${CROSS_PREFIX}ar"
export NM="${CROSS_PREFIX}nm"
export RANLIB="${CROSS_PREFIX}ranlib"
export LDFLAGS="-L$PREFIX/lib -fPIE -pie "
export CFLAGS="$OPTIMIZE_CFLAGS -I$PREFIX/include --sysroot=$PLATFORM -fPIE "
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="--sysroot=$PLATFORM "
export STRIP=${CROSS_PREFIX}strip


pushd x264
./configure \
    --cross-prefix=$CROSS_PREFIX \
    --sysroot=$PLATFORM \
    --host=$HOST \
    --enable-pic \
    --enable-static \
    --disable-cli \
    --bit-depth=8 \
    --chroma-format=420 \
    --disable-interlaced \
    --prefix=$PREFIX \
    $ADDITIONAL_CONFIGURE_FLAG
# seems no log2 in android
sed -i '' 's/HAVE_LOG2F 1/HAVE_LOG2F 0/g' config.h
make clean
make -j8
make install
popd

pushd fdk-aac
./configure --host=$HOST --enable-static --disable-shared --enable-static   --target=android --disable-asm --enable-pic --prefix=$PREFIX 
make clean
make -j8
make install
popd

pushd ffmpeg-$FFMPEG_VERSION
./configure --prefix=$PREFIX \
    --target-os=android \
    --arch=$ARCH \
    --cross-prefix=$CROSS_PREFIX \
    --enable-cross-compile \
    --sysroot=$PLATFORM \
    --pkg-config=/usr/local/bin/pkg-config \
    --pkg-config-flags="--static" \
    --enable-pic \
    --enable-small \
    --enable-gpl \
    --enable-jni \
    --enable-mediacodec \
    \
    --enable-decoder=h264_mediacodec \
    \
    --disable-shared \
    --enable-static \
    --enable-neon \
    \
    --disable-ffmpeg \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-postproc \
    --disable-symver \
    --disable-stripping \
    --enable-swscale \
    --disable-network \
    \
    --disable-protocols \
    --enable-protocol='file' \
    --enable-protocol='pipe' \
    \
    --disable-demuxers \
    --disable-muxers \
    --enable-demuxer='aac,avi,dnxhd,flac,flv,gif,h261,h263,h264,image2,matroska,webm,mov,mp3,mp4,mpeg,ogg,srt,wav,webvtt' \
    --enable-muxer='3gp,dnxhd,flac,flv,gif,image2,matroska,webm,mov,mp3,mp4,mpeg,ogg,opus,srt,wav,webvtt' \
    \
    --disable-encoders \
    --disable-decoders \
    --enable-libx264 \
    --enable-libfdk_aac \
    --enable-encoder='libfdk_aac,mediacodec,h264_mediacodec,h264,flv,h264_videotoolbox,libx264,libx264rgb,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4,aac,wmav1,wmav2,wavpack,pcm_alaw_at,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_mulaw,pcm_mulaw_at,pcm_s16be,pcm_s16be_planar,pcm_s16le,pcm_s16le_planar,pcm_s24be,pcm_s24daud,pcm_s24le,pcm_s24le_planar,pcm_s32be,pcm_s32le,pcm_s32le_planar,pcm_s64be,pcm_s64le,pcm_s8,pcm_s8_planar,pcm_u16be,pcm_u16le,pcm_u24be,pcm_u24le,pcm_u32be,pcm_u32le,pcm_u8,pcm_zork' \
    --enable-decoder='h264_mediacodec,8bps,aic,flv,h264,mpeg4,msmpeg4v1,msmpeg4v2,vp7,vp8,vp9,aac,mp3,pcm_alaw,pcm_alaw_at,pcm_bluray,pcm_dvd,pcm_f16le,pcm_f24le,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_lxf,pcm_mulaw,pcm_mulaw_at,pcm_s16be,pcm_s16be_planar,pcm_s16le,pcm_s16le_planar,pcm_s24be,pcm_s24daud,pcm_s24le,pcm_s24le_planar,pcm_s32be,pcm_s32le,pcm_s32le_planar,pcm_s64be,pcm_s64le,pcm_s8,pcm_s8_planar,pcm_u16be,pcm_u16le,pcm_u24be,pcm_u24le,pcm_u32be,pcm_u32le,pcm_u8,pcm_zork,wavpack,wmav1,wmav2' \
    \
    --disable-filters \
    --enable-filter='fps,scale,aformat,aresample,asetnsamples' \
    \
    --enable-bsf=aac_adtstoasc \
    \
    --disable-debug \
    --disable-doc \
    \
    --extra-cflags='-I$PREFIX/include' \
    --extra-ldflags='-I$PREFIX/lib' \
    --enable-nonfree \
    \
    $ADDITIONAL_CONFIGURE_FLAG

make clean
make -j8
make install V=1
popd
}

if [ $TARGET == 'arm-v5te' ]; then
    #arm v5te
    CPU=armv5te
    ARCH=arm
    OPTIMIZE_CFLAGS="-marm -march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm-v6' ]; then
    #arm v6
    CPU=armv6
    ARCH=arm
    OPTIMIZE_CFLAGS="-marm -march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm-v7vfpv3' ]; then
    #arm v7vfpv3
    CPU=armv7-a
    ARCH=arm
    OPTIMIZE_CFLAGS="-mfloat-abi=softfp -mfpu=vfpv3-d16 -marm -march=$CPU -Os -O3 "
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm-v7vfp' ]; then
    #arm v7vfp
    CPU=armv7-a
    ARCH=arm
    OPTIMIZE_CFLAGS="-mfloat-abi=softfp -mfpu=vfp -marm -march=$CPU -Os -O3 "
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm-v7n' ]; then
    #arm v7n
    CPU=armv7-a
    ARCH=arm
    OPTIMIZE_CFLAGS="-mfloat-abi=softfp -mfpu=neon -marm -mtune=cortex-a8 -march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=--enable-neon
    build_one
elif [ $TARGET == 'arm-v6+vfp' ]; then
    #arm v6+vfp
    CPU=armv6
    ARCH=arm
    OPTIMIZE_CFLAGS="-DCMP_HAVE_VFP -mfloat-abi=softfp -mfpu=vfp -marm -march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm64-v8a' ]; then
    #arm64-v8a
    CPU=armv8-a
    ARCH=arm64
    OPTIMIZE_CFLAGS="-march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'x86_64' ]; then
    #x86_64
    CPU=x86-64
    ARCH=x86_64
    OPTIMIZE_CFLAGS="-fomit-frame-pointer -march=$CPU -Os -O3"
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'i686' ]; then
    #x86
    CPU=i686
    ARCH=i686
    OPTIMIZE_CFLAGS="-fomit-frame-pointer -march=$CPU -Os -O3"
    # disable asm to fix
    ADDITIONAL_CONFIGURE_FLAG=' --disable-asm --disable-cuvid'
    build_one
elif [ $TARGET == 'mips' ]; then
    #mips
    CPU=mips32
    ARCH=mips
    OPTIMIZE_CFLAGS="-march=$CPU -Os -O3"
    #"-std=c99 -O3 -Wall -pipe -fpic -fasm -ftree-vectorize -ffunction-sections -funwind-tables -fomit-frame-pointer -funswitch-loops -finline-limit=300 -finline-functions -fpredictive-commoning -fgcse-after-reload -fipa-cp-clone -Wno-psabi -Wa,--noexecstack"
    ADDITIONAL_CONFIGURE_FLAG=' --disable-asm'
    build_one
elif [ $TARGET == 'mips64' ]; then
    #mips
    CPU=mips64r6
    ARCH=mips64
    OPTIMIZE_CFLAGS="-march=$CPU -Os -O3"
    #"-std=c99 -O3 -Wall -pipe -fpic -fasm -ftree-vectorize -ffunction-sections -funwind-tables -fomit-frame-pointer -funswitch-loops -finline-limit=300 -finline-functions -fpredictive-commoning -fgcse-after-reload -fipa-cp-clone -Wno-psabi -Wa,--noexecstack"
    ADDITIONAL_CONFIGURE_FLAG=' --disable-asm'
    build_one
elif [ $TARGET == 'armv7-a' ]; then
    #arm armv7-a
    CPU=armv7-a
    ARCH=arm
    OPTIMIZE_CFLAGS="-mfloat-abi=softfp -marm -march=$CPU -Os -O3 "
    ADDITIONAL_CONFIGURE_FLAG=
    build_one
elif [ $TARGET == 'arm' ]; then
    #arm
    CPU=armv5te
    ARCH=arm
    OPTIMIZE_CFLAGS="-march=$CPU -Os -O3 "
    ADDITIONAL_CONFIGURE_FLAG=' --disable-asm'
    build_one
fi
