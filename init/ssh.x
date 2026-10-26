; ssh.x -- x-ssh's programs: sshd, ssh, ssh-keygen, scp, sftp, sftp-server,
; ssh-agent and ssh-add.
;
; x-ssh names its program by its first operand.  Each of those names is a
; command here, its stream told which by %command, so `ssh host cmd` is
; x-ssh's `ssh host cmd`.  The command's arguments are what follows the
; launcher's "--".
(import ssh/base)
(ssh-main (pair %command (rest (Sys args (lit program)))))
