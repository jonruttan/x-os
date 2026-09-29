; make.x -- the make command.
;
; x-make's own entry builds when it has arguments and starts a session when
; it has none.  A make with no arguments builds the default goal, so the
; command always builds.
(import mk/base)
(mk-main args)
