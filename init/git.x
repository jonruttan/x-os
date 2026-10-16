; git.x -- x-git's commands: git, and its services git-upload-pack and
; git-receive-pack.
;
; A client of a git repository on this machine -- git over ssh, or git
; here given a file:// url -- runs `git-upload-pack 'PATH'` or
; `git-receive-pack 'PATH'`, as git's own services are named.  Each is
; x-git's service of the name after "git-", told which by %command, with
; the client's standard input and output as the conversation; `git` is
; x-git itself.  The launcher starts the engine as its path, its flags and
; --batch, then the command's arguments, with no "--" between: the first
; three are left out, as init/ssh.x leaves them out.
(import git/base)
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))
(git-main
  (if (str=? %command "git")
    (%operands (rest args))
    (pair (Str8 sub 4 (- (Str8 length %command) 4) %command) (%operands (rest args)))))
