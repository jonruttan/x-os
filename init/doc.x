; doc.x -- x-doc, documents shown, described and converted.
;
; `doc FILE` lays a document out as text, `doc -i FILE` says what it is,
; and `doc FILE OUTPUT` or `doc -t FORMAT FILE` writes it in another
; format; `doc` alone prints the usage.  The command's arguments are what
; follows the launcher's "--".
(import doc/base)
(Sys exit (doc-main (rest (Sys args (lit program)))))
