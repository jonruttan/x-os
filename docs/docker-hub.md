# x-os

The Linux kernel, [x](https://github.com/jonruttan/x-lang) and its languages,
and nothing else. The shell is [x-ash](https://github.com/jonruttan/x-ash) and
the commands are [x-coreutils](https://github.com/jonruttan/x-coreutils).

    docker run -it jonruttan/x-os

For `linux/amd64` and `linux/arm64`.

## Commands

| Command | What |
|---|---|
| `sh`, `ash` | [x-ash](https://github.com/jonruttan/x-ash) |
| `grep` | [x-grep](https://github.com/jonruttan/x-grep) |
| `sed` | [x-sed](https://github.com/jonruttan/x-sed) |
| `awk` | [x-awk](https://github.com/jonruttan/x-awk) |
| `make` | [x-make](https://github.com/jonruttan/x-make) |
| `cc` | [x-cc](https://github.com/jonruttan/x-cc) |
| `python` | [x-python](https://github.com/jonruttan/x-python) |
| `logo` | [x-logo](https://github.com/jonruttan/x-logo) |
| `infocom` | [x-infocom](https://github.com/jonruttan/x-infocom): a Z-machine; `infocom /usr/share/infocom/zork1.z3` plays Zork I |
| `sshd`, `ssh`, `ssh-keygen`, `scp` | [x-ssh](https://github.com/jonruttan/x-ssh): OpenSSH's server, client, key tool and scp |
| `git`, `git-upload-pack`, `git-receive-pack` | [x-git](https://github.com/jonruttan/x-git): git, and the services a client of this machine's repositories runs over ssh or a file:// url |
| `tmux` | [x-tmux](https://github.com/jonruttan/x-tmux): a window of panes, each a shell; C-b `%` and `"` split, `o` switches, `x` kills, `d` leaves |
| `vi` | the editor, an x-coreutils applet |
| `x` | x itself: `x`, `x -l xe`, `x -l LANG` |
| every other | an x-coreutils applet |

## Bootable image

The same system as an ISO image, for x86-64 and arm64, is on the
[latest release](https://github.com/jonruttan/x-os/releases/tag/latest).

## Source

[github.com/jonruttan/x-os](https://github.com/jonruttan/x-os)
