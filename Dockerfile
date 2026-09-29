# The builder is the pre-x floor: it has a shell, a C compiler and make, and
# none of it reaches the final image.  Alpine, so the engine links against musl.
FROM alpine:3.20 AS build
RUN apk add --no-cache build-base git curl
# The platform's tools call `shasum`; Alpine has the digests under their own
# names.
COPY tools/shasum /usr/local/bin/shasum
WORKDIR /src

# The engine is built from source: the published linux artifact is glibc, and
# there is none for arm64.  The prefix is the one the image will have, since a
# state image and a boot stream both carry absolute paths.
COPY build/src/x-lang /src/x-lang
WORKDIR /src/x-lang
# A fetched source has no history to describe itself from, so each is stamped
# with the commit it was pinned at, at install.  The engine is a clone and
# describes itself.
RUN make engine-source
RUN make
RUN make boot
RUN make install PREFIX=/usr X_RELEASE="$(cut -c1-12 .commit)"
# A variable given to make reaches every make under it, so install has
# restamped the engine's declaration with x-lang's commit.  The engine writes
# its own again, and that is the one installed.
RUN rm -f engine/x-engine-build.xon \
 && make -C engine x-engine-build.xon \
 && grep '^(param release "v' engine/x-engine-build.xon \
 && install -m 0644 engine/x-engine-build.xon /usr/libexec/x/x-engine-build.xon

# Out of the checkout: with lib/x.x in the working directory the wrapper runs
# in repo mode and does not see the installed langs.
WORKDIR /src
COPY tools /src/tools
COPY build/src /src/all
RUN sh /src/tools/build.sh install-langs /src/all
RUN sh /src/tools/build.sh image-langs /src/all

# The dialects the x command offers.
ARG DIALECTS="x xe"
RUN sh /src/tools/build.sh image-dialects $DIALECTS

COPY init /src/init
COPY commands.xon /src/commands.xon
RUN sh /src/tools/build.sh streams /src/commands.xon /src/init

COPY launch /src/launch
RUN cc -Os -static -s -o /usr/libexec/x/launch /src/launch/launch.c /src/launch/x.c

COPY etc /src/etc
RUN sh /src/tools/build.sh root /rootfs /src/commands.xon /src/etc

FROM scratch AS root
COPY --from=build /rootfs /
ENV PATH=/usr/bin:/bin HOME=/root
WORKDIR /root
CMD ["/bin/sh"]

# The bootable form: the same root as an initramfs, beside a kernel.  The
# kernel is Alpine's, and /dev/console is there because the kernel opens it
# for init before init can mount devtmpfs.
FROM alpine:3.20 AS initramfs
RUN apk add --no-cache linux-virt
COPY --from=build /rootfs /rootfs
RUN mknod -m 600 /rootfs/dev/console c 5 1 \
 && mkdir /out \
 && cp /boot/vmlinuz-virt /out/vmlinuz \
 && cd /rootfs \
 && find . | cpio -o -H newc | gzip -9 > /out/initramfs.cpio.gz

FROM scratch AS boot
COPY --from=initramfs /out /

# The bootable form as one file: the kernel and the initramfs on an ISO 9660
# image that GRUB starts, from firmware of either kind where the
# architecture has both.  GRUB is the one program aboard that is neither the
# kernel nor x, and it is gone once the kernel runs.
FROM alpine:3.20 AS iso-build
RUN apk add --no-cache grub grub-efi xorriso mtools \
 && if [ "$(uname -m)" = x86_64 ]; then apk add --no-cache grub-bios; fi
COPY tools/iso.sh /src/tools/iso.sh
COPY --from=initramfs /out /boot-files
RUN sh /src/tools/iso.sh /boot-files /out

FROM scratch AS iso
COPY --from=iso-build /out /

# The container image is the default target.
FROM root
