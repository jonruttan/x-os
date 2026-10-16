; ssh.x -- x-ssh's programs: dropbear, dbclient and ssh, dropbearkey and
; ssh-keygen, dropbearconvert, scp.
;
; x-ssh is Dropbear's multi-purpose binary: its first operand names the
; program.  Each of those names is a command here, its stream told which by
; %command, so `dbclient host cmd` is x-ssh's `dbclient host cmd`.  The
; launcher starts the engine as its path, its flags and --batch, then the
; command's arguments, with no "--" between: the first three are left out.
(import ssh/base)
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))
(ssh-main (pair %command (%operands (rest args))))
