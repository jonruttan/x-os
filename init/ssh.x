; ssh.x -- x-ssh's programs: dropbear, dbclient and ssh, dropbearkey and
; ssh-keygen, dropbearconvert, scp.
;
; x-ssh is Dropbear's multi-purpose binary: its first operand names the
; program.  Each of those names is a command here, its stream told which by
; %command, so `dbclient host cmd` is x-ssh's `dbclient host cmd`.
(import ssh/base)
(ssh-main (pair %command args))
