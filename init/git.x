; git.x -- x-git's commands: git, and its services git-upload-pack and
; git-receive-pack.
;
; A client of a git repository on this machine -- git over ssh, or git
; here given a file:// url -- runs `git-upload-pack 'PATH'` or
; `git-receive-pack 'PATH'`, as git's own services are named.  Each is
; x-git's service of the name after "git-", told which by %command, with
; the client's standard input and output as the conversation; `git` is
; x-git itself.  The command's arguments are what follows the launcher's
; "--".
(import git/base)
(def %ops (rest (Sys args (lit program))))
(git-main
  (if (str=? %command "git")
    %ops
    (pair (Str8 sub 4 (- (Str8 length %command) 4) %command) %ops)))
