; tmux.x -- x-tmux, the terminal multiplexer.
;
; `tmux` with no command opens a session, as tmux does; `tmux COMMAND ARGS`
; is x-tmux's command line.  The command's arguments are what follows the
; launcher's "--".
(import tmux/base)
(def %ops (rest (Sys args (lit program))))
(Sys exit (tmux-main (if (null? %ops) (list "new") %ops)))
