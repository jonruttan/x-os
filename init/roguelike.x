; roguelike.x -- x-roguelike, the dungeon crawl.
;
; `roguelike` with no arguments plays the classic set, taking up a
; saved game first; `roguelike scores` lists the best games.  The
; command's arguments are what follows the launcher's "--".
(import roguelike/base roguelike-main)
(Sys exit (roguelike-main (rest (Sys args (lit program)))))
