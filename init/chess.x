; chess.x -- x-chess, the chess engine.
;
; `chess` on a terminal is a game against the engine; fed lines, it
; speaks UCI when the first is `uci`, as a chess GUI expects.  The
; command's arguments are what follows the launcher's "--".
(import chess/base)
(Sys exit (chess-main (rest (Sys args (lit program)))))
