; links.x -- x-links, the terminal Markdown browser.
;
; `links` with no location browses the current directory; `links -dump
; LOCATION` writes the page out, as lynx's -dump does.  The command's
; arguments are what follows the launcher's "--".
(import links/base)
(Sys exit (links-main (rest (Sys args (lit program)))))
