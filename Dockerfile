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
# with the commit it was pinned at.
RUN make engine-source
RUN make X_RELEASE="$(cut -c1-12 .commit)"
RUN make boot X_RELEASE="$(cut -c1-12 .commit)"
RUN make install PREFIX=/usr X_RELEASE="$(cut -c1-12 .commit)"

# Out of the checkout: with lib/x.x in the working directory the wrapper runs
# in repo mode and does not see the installed langs.
WORKDIR /src
COPY build/src/x-ash /src/x-ash
COPY build/src/x-coreutils /src/x-coreutils
RUN make -C /src/x-coreutils install PREFIX=/usr \
      LANG_VERSION="$(cut -c1-12 /src/x-coreutils/.commit)" \
 && x --image -l coreutils
RUN make -C /src/x-ash install PREFIX=/usr \
      LANG_VERSION="$(cut -c1-12 /src/x-ash/.commit)"

COPY tools/stream.sh /src/stream.sh
COPY init /src/init
RUN sh /src/stream.sh ash sh && sh /src/stream.sh coreutils coreutils \
 && sh /src/stream.sh ash init /src/init/init.x \
 && for how in poweroff reboot halt; do \
      sh /src/stream.sh ash "$how" /src/init/power.x "(def %power-how (lit $how))" || exit 1; \
    done

COPY launch /src/launch
RUN cc -Os -static -s -o /usr/libexec/x/launch /src/launch/launch.c

# The root: the loader, the engine, the library, the langs, and links.
RUN mkdir -p /rootfs/lib /rootfs/bin /rootfs/usr/libexec /rootfs/usr/share \
      /rootfs/tmp /rootfs/root /rootfs/proc /rootfs/sys /rootfs/dev /rootfs/etc \
 && chmod 1777 /rootfs/tmp \
 && cp /lib/ld-musl-*.so.1 /rootfs/lib/ \
 && cp -R /usr/libexec/x /rootfs/usr/libexec/x \
 && cp -R /usr/share/x /rootfs/usr/share/x \
 && rm -rf /rootfs/usr/share/x/tests \
 && mkdir -p /rootfs/run \
 && ln -s /usr/libexec/x/launch /rootfs/init \
 && ln -s /usr/libexec/x/launch /rootfs/bin/sh \
 && for how in poweroff reboot halt; do ln -s /usr/libexec/x/launch "/rootfs/bin/$how"; done \
 && sh /src/stream.sh --applets > /tmp/applets \
 && while read -r a; do [ -e "/rootfs/bin/$a" ] || ln -s /usr/libexec/x/launch "/rootfs/bin/$a"; done < /tmp/applets \
 && printf 'root:x:0:0:root:/root:/bin/sh\n' > /rootfs/etc/passwd \
 && printf 'root:x:0:\n' > /rootfs/etc/group

FROM scratch AS root
COPY --from=build /rootfs /
ENV PATH=/bin HOME=/root
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
 && cd /rootfs && find . | cpio -o -H newc | gzip -9 > /out/initramfs.cpio.gz

FROM scratch AS boot
COPY --from=initramfs /out /

# The container image is the default target.
FROM root
