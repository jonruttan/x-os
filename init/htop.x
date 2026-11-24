; htop.x -- x-top, the interactive process viewer.
;
; `htop` on a terminal shows the meters and the processes until q;
; `htop -D` draws one screen to standard output and exits.  The
; command's arguments are what follows the launcher's "--".
(import top/base top-main)
(Sys exit (top-main (rest (Sys args (lit program)))))
