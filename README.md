# x-os

The Linux kernel, [x](https://github.com/jonruttan/x-lang) and its languages,
as a container and as a bootable image. It boots into
[x-ash](https://github.com/jonruttan/x-ash) and its commands are
[x-coreutils](https://github.com/jonruttan/x-coreutils).

```
$ docker run -it x-os
ASH Shell v0.1.0 on x-lang 9e0b1d04b5ef, engine v0.2.14
exit or ctrl-d to leave
# uname -m
aarch64
```

## Getting it

The container, for `linux/amd64` and `linux/arm64`, is on
[Docker Hub](https://hub.docker.com/r/jonruttan/x-os):

```bash
docker run -it jonruttan/x-os
```

The bootable image is an ISO image, one an architecture, on the
[latest release](https://github.com/jonruttan/x-os/releases/tag/latest):

| Machine | Image | Started by |
|---|---|---|
| x86-64 | [x-os-amd64.iso](https://github.com/jonruttan/x-os/releases/download/latest/x-os-amd64.iso) | BIOS or UEFI |
| arm64 | [x-os-arm64.iso](https://github.com/jonruttan/x-os/releases/download/latest/x-os-arm64.iso) | UEFI |

It boots as a disc in a virtual machine. It needs
4 GB of memory. Under QEMU:

```bash
qemu-system-x86_64 -m 4096 -cdrom x-os-amd64.iso
```

The menu's first entry puts the shell on the screen, and its second on the
serial line.

## What is in it

| Path | What |
|---|---|
| `/lib/ld-musl-*.so.1` | musl: the loader and the C library, one file |
| `/usr/lib/libssl.so.3`, `/usr/lib/libcrypto.so.3` | OpenSSL, Alpine's, which x's Tls opens for https |
| `/etc/ssl/cert.pem` | the CA bundle Tls checks a server's certificate against |
| `/usr/libexec/x/x-bin` | the engine |
| `/usr/libexec/x/launch` | the launcher |
| `/usr/share/x` | the library, the langs and their state images |
| `/usr/share/x/launch` | one boot stream a command |
| `/usr/bin`, `/init` | links to the launcher; `/bin` is a link to `/usr/bin` |

The container is that root. The bootable image is the same root as an
initramfs, beside a kernel; the kernel is Alpine's `linux-virt`. The ISO
image holds the two and GRUB, which starts the kernel.

Once the kernel runs there is no shell but x-ash and no C program but the
launcher, which is also the `x` command, and the engine; OpenSSL is a
library the engine opens, not a program.

## Commands

| Command | What |
|---|---|
| `sh`, `ash` | [x-ash](https://github.com/jonruttan/x-ash) |
| `grep` | [x-grep](https://github.com/jonruttan/x-grep) |
| `sed` | [x-sed](https://github.com/jonruttan/x-sed) |
| `awk` | [x-awk](https://github.com/jonruttan/x-awk) |
| `cc` | [x-cc](https://github.com/jonruttan/x-cc) |
| `python` | [x-python](https://github.com/jonruttan/x-python) |
| `logo` | [x-logo](https://github.com/jonruttan/x-logo) |
| `make` | [x-make](https://github.com/jonruttan/x-make) |
| `infocom` | [x-infocom](https://github.com/jonruttan/x-infocom): a Z-machine; `infocom /usr/share/infocom/zork1.z3` plays Zork I |
| `vi` | x-coreutils' editor |
| `x` | x itself: a dialect or any lang, as below |
| `poweroff`, `reboot`, `halt` | `init/power.x` |
| every other | an x-coreutils applet |

`commands.xon` names the commands that are a lang of their own. A row may
name an entry of this repository's in place of the lang's: `make` starts at
`init/make.x`, which builds with no arguments where x-make's own entry
starts a session.

## How a command starts

The engine reads its program from descriptor 0 and finds the caller's input on
descriptor 3. `launch` puts a prepared boot stream on 0, the caller's input on
3, and runs the engine. The command's name picks the stream:
`/usr/share/x/launch/NAME` when there is one, and otherwise the coreutils
stream, with the name passed as the applet.

A boot stream is the text the `x` wrapper pipes for a lang booted from its
state image. `tools/stream.sh` writes it when the image is built.

## The x command

```
x                                   a session in helium
x -l xe                             a session in xenon
x -c '(write (+ 1 2))'              evaluate, then exit; -c repeats
x -f prog.x                         evaluate a file, then exit
x -F lib.x                          evaluate a file, then the session
echo '(write 42)' | x               piped stdin is the program
x -l awk -- 'BEGIN { print 6*7 }'   a lang, with its arguments after --
```

`x` writes the stream the wrapper script writes for a boot from a state
image, from the same pieces and by the same rules, and runs the engine on it.
It takes `-l`, `-c`, `-f`, `-F`, `-q`, `--no-color`, `--share-dir`,
`--engine-path` and `-v`, which prints the pieces. The dialects are the ones
imaged into `/usr/share/x/images`: `x` and `xe`. The langs are the installed
ones. Each boots from its state image, and there is no source boot.

## Docker Hub

`docs/docker-hub.md` is the overview the repository on Docker Hub shows.
`tools/hub-describe.sh` sends it, and a push to main runs that after the
image is published. The token must be allowed to read, write and delete.

## Process 1

`init/init.x` mounts `/proc`, `/sys`, `/dev`, `/tmp` and `/run`, starts the
shell in its own session with the terminal as its controlling terminal,
collects every child that ends, and starts the shell again when it ends.

`poweroff`, `reboot` and `halt` are `init/power.x`: they flush and make the
`reboot` system call. Nothing is signalled first.

## Building

```bash
make test
```

`make help` lists the targets. `ARCH` is `amd64` or `arm64` and defaults to
the host's. The build needs Docker, the container test needs `expect`, and
the boot tests need QEMU and, for the ISO image, its UEFI firmware.

The builder is Alpine with a C compiler, a shell and make. None of it reaches
the image.

## Pins

`pins.xon` names each source by commit. `make fetch` acquires them into
`build/src` and refuses a checkout whose commit is not the one named.

It also says what each source tracks: its highest version tag, or the head of
its main branch. `tools/pins-update.sh` moves the pins to the newest tracked
commits, and the Pins workflow runs it daily and opens a pull request with
what moved. The image is rebuilt and published when that is merged.

## Limits

- A language that boots from source needs about 4 GB. The image boots each
  lang from its state image.
- ctrl-C at the prompt ends the shell; process 1 starts another.
- Writing x-python's state image needs more than 4 GB, so the build does too.
- `logo` does not read a piped program: a program goes in a file,
  `x -l logo -f FILE`.
- `cc` is x-cc, whose `run` executes a C program. It writes no executable
  here: what it writes is Mach-O.
