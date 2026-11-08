#!/bin/sh
# sdl.sh -- build libSDL3 from its release source, against musl, into OUT.
#
#   sh tools/sdl.sh VERSION SHA256 OUT
#
# OUT/usr/lib gets libSDL3.so.0 and the file it names; OUT/usr/share/doc/SDL3
# gets the licence.  Only the drivers that need no other library are built:
# dummy and offscreen video with SDL's software renderer, dummy and disk
# audio, and the Linux joystick.  Every driver that would dlopen a library the
# root does not carry is off, so none is looked for at run time.
set -e

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "sdl: $*" >&2
	exit "$status"
}

version="$1"
digest="$2"
out="$3"
if [ -z "$version" ] || [ -z "$digest" ] || [ -z "$out" ]; then
	fail 2 "usage: sdl.sh VERSION SHA256 OUT"
fi

work=$(mktemp -d)
tarball="$work/SDL3-$version.tar.gz"
curl -sSfL -o "$tarball" \
	"https://github.com/libsdl-org/SDL/releases/download/release-$version/SDL3-$version.tar.gz"
if ! printf '%s  %s\n' "$digest" "$tarball" | sha256sum -c -s; then
	fail 1 "SDL3-$version.tar.gz is not the release pinned by its digest"
fi
tar -xzf "$tarball" -C "$work"

cmake -S "$work/SDL3-$version" -B "$work/build" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr \
	-DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_UNIX_CONSOLE_BUILD=ON \
	-DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
	-DSDL_DUMMYVIDEO=ON -DSDL_OFFSCREEN=ON \
	-DSDL_DUMMYAUDIO=ON -DSDL_DISKAUDIO=ON \
	-DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF \
	-DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_VULKAN=OFF -DSDL_GPU=OFF \
	-DSDL_ALSA=OFF -DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF \
	-DSDL_SNDIO=OFF -DSDL_OSS=OFF \
	-DSDL_LIBUDEV=OFF -DSDL_DBUS=OFF -DSDL_IBUS=OFF -DSDL_HIDAPI_LIBUSB=OFF \
	-DSDL_LIBURING=OFF -DSDL_CAMERA=OFF
cmake --build "$work/build" -j "$(nproc)"
DESTDIR="$work/install" cmake --install "$work/build"

mkdir -p "$out/usr/lib" "$out/usr/share/doc/SDL3"
soname=libSDL3.so.0
real=$(readlink "$work/install/usr/lib/$soname")
cp "$work/install/usr/lib/$real" "$out/usr/lib/$real"
strip "$out/usr/lib/$real"
ln -s "$real" "$out/usr/lib/$soname"
cp "$work/SDL3-$version/LICENSE.txt" "$out/usr/share/doc/SDL3/LICENSE.txt"

# The library must ask the root for nothing but the C library.
needed=$(objdump -p "$out/usr/lib/$real" | sed -n 's/^ *NEEDED *//p' | grep -v '^libc\.musl' || true)
if [ -n "$needed" ]; then
	fail 1 "$real needs more than musl: $needed"
fi
rm -rf "$work"
echo "sdl: $out/usr/lib/$real, $(wc -c < "$out/usr/lib/$real") bytes"
