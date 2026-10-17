; ssh.x -- x-ssh's programs: sshd, ssh, ssh-keygen and scp.
;
; x-ssh names its program by its first operand.  Each of those names is a
; command here, its stream told which by %command, so `ssh host cmd` is
; x-ssh's `ssh host cmd`.  The launcher starts the engine as its path, its
; flags and --batch, then the command's arguments, with no "--" between:
; the first three are left out.
(import ssh/base)
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))
(ssh-main (pair %command (%operands (rest args))))
