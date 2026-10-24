; applets.x -- print the coreutils applet names, one a line.
;
;   x -l coreutils -f tools/applets.x
;
; The names come from x-coreutils' own Applets class, so the root links the
; applets the bundle dispatches.
(import cu/applets Applets)
(import cu/prims file-write)

(file-write 1 (Str8 join "\n" (Applets names)))
(file-write 1 "\n")
