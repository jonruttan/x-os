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
COPY build/src /src/all
# Every source but the platform is a lang.  All are installed before any is
# imaged, since a lang may require another.  One that writes no image boots
# from source, which the image has no wrapper to do, so that is an error.
RUN for d in /src/all/*/; do \
      [ -f "$d/lang.xon" ] || continue; \
      make -C "$d" install PREFIX=/usr LANG_VERSION="$(cut -c1-12 "$d/.commit")" || exit 1; \
    done
RUN for d in /src/all/*/; do \
      [ -f "$d/lang.xon" ] || continue; \
      lang=$(sed -n 's/^(lang "\(.*\)").*/\1/p' "$d/lang.xon"); \
      x --image -l "$lang" || exit 1; \
      [ -f "/usr/share/x/langs/$lang/.images/$lang.boot.x.ximg" ] \
        || { echo "no state image for $lang" >&2; exit 1; }; \
    done

COPY tools/stream.sh /src/stream.sh
COPY init /src/init
COPY commands.xon /src/commands.xon
RUN sh /src/stream.sh coreutils coreutils \
 && sed -n 's/^(command[[:space:]]\{1,\}\([a-z0-9-]*\)[[:space:]]\{1,\}\([a-z0-9-]*\)).*/\1 \2/p' \
      /src/commands.xon > /src/commands \
 && [ "$(grep -c '^(command' /src/commands.xon)" = "$(grep -c . /src/commands)" ] \
 && while read -r name lang; do sh /src/stream.sh "$lang" "$name" || exit 1; done < /src/commands \
 && sh /src/stream.sh ash init /src/init/init.x \
 && for how in poweroff reboot halt; do \
      sh /src/stream.sh ash "$how" /src/init/power.x "(def %power-how (lit $how))" || exit 1; \
    done

COPY etc /src/etc
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
 && while read -r name lang; do ln -s /usr/libexec/x/launch "/rootfs/bin/$name" || exit 1; done < /src/commands \
 && for how in poweroff reboot halt; do ln -s /usr/libexec/x/launch "/rootfs/bin/$how"; done \
 && sh /src/stream.sh --applets > /tmp/applets \
 && while read -r a; do [ -e "/rootfs/bin/$a" ] || ln -s /usr/libexec/x/launch "/rootfs/bin/$a"; done < /tmp/applets \
 && printf 'root:x:0:0:root:/root:/bin/sh\n' > /rootfs/etc/passwd \
 && printf 'root:x:0:\ndaemon:x:1:\n' > /rootfs/etc/group \
 && cp /src/etc/hello.c /rootfs/etc/hello.c

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
