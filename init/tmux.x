; tmux.x -- x-tmux, the terminal multiplexer.
;
; `tmux` with no command opens a session, as tmux does; `tmux COMMAND ARGS`
; is x-tmux's command line.  The launcher starts the engine as its path,
; its flags and --batch, then the command's arguments, with no "--"
; between: the first three are left out.
(import tmux/base)
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))
(def %ops (%operands (rest args)))
(Sys exit (tmux-main (if (null? %ops) (list "new") %ops)))
