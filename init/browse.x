; browse.x -- x-browse, the terminal Markdown browser.
;
; `browse` with no location browses the current directory; `browse -dump
; LOCATION` writes the page out, as lynx's -dump does.  The command's
; arguments are what follows the launcher's "--".
(import browse/base)
(Sys exit (browse-main (rest (Sys args (lit program)))))
