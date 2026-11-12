; # x-os -- process 1
;
; ## init.x -- mount, start the shell, reap, start it again
;
; The kernel runs this as /init with the console on its descriptors.  The
; launcher has since put the boot stream on descriptor 0 and the console on 3,
; so the console is put back before anything is started.
;
; It never returns: when process 1 exits the kernel panics.

(def %init-mount (syscall-door (lit mount)))
(def %init-wait4 (syscall-door (lit wait4)))
(def %init-mkdir (syscall-door (lit mkdir)))
(def %init-setsid (syscall-door (lit setsid)))
(def %init-open (syscall-door (lit open)))
(def %init-read (syscall-door (lit read)))
(def %init-close (syscall-door (lit close)))
(def %init-finit-module (syscall-door (lit finit_module)))
(def %init-make-str (prim-ref (lit str) (lit make)))

(def %init-shell "/bin/sh")

; (SOURCE TARGET TYPE), in the order they are mounted.
(def %init-mounts
  (lit (("proc"     "/proc" "proc")
        ("sysfs"    "/sys"  "sysfs")
        ("devtmpfs" "/dev"  "devtmpfs")
        ("tmpfs"    "/tmp"  "tmpfs")
        ("tmpfs"    "/run"  "tmpfs"))))

(def %init-say
  (fn (_ . parts)
    (display "init: ")
    (apply display parts)
    (newline)))

; A mount that fails is reported and the boot goes on: a shell with no /proc
; can still say what is wrong, and a panic cannot.
(def %init-mount-row
  (fn (_ row)
    (def target (first (rest row)))
    (%init-mkdir target 493)
    (def r (%init-mount (first row) target (first (rest (rest row))) 0 ()))
    (match
      ((< r 0) (%init-say "cannot mount " target))
      (#t ()))))

(def %init-mount-all
  (fn (self rows)
    (match
      ((eq? rows ()) ())
      (#t (do (%init-mount-row (first rows))
              (self (rest rows)))))))

; The drivers the kernel has as modules, which the boot image carries
; unpacked with an order file naming them, a module's own needs first.  A
; driver with no device of its own loads and waits; one the kernel already
; has (-17) is passed over, and any other refusal is reported and the boot
; goes on.  The container root has no order file and loads nothing.
(def %init-modules "/lib/modules/x-os/")

(def %init-load-module
  (fn (_ name)
    (def fd (%init-open (Str8 append %init-modules name) 0 0))
    (def r (match ((< fd 0) fd) (#t (%init-finit-module fd "" 0))))
    (match ((< fd 0) ()) (#t (%init-close fd)))
    (match
      ((or (= r 0) (= r -17)) ())
      (#t (%init-say "cannot load " name " (" r ")")))))

(def %init-load-modules
  (fn (_)
    (def fd (%init-open (Str8 append %init-modules "order") 0 0))
    (def buf (%init-make-str 4096))
    (def n (match ((< fd 0) 0) (#t (%init-read fd buf 4096))))
    (match ((< fd 0) ()) (#t (%init-close fd)))
    (match
      ((< n 1) ())
      (#t (List for-each
            (fn (_ name) (match ((Str8 empty? name) ()) (#t (%init-load-module name))))
            (Str8 split "\n" (Str8 sub 0 n buf)))))))

; The terminal behind the console.  /dev/console cannot be a controlling
; terminal; the kernel names the devices it stands for, last one first in
; line for input, in /sys/class/tty/console/active.
(def %init-console-tty
  (fn (_)
    (def fd (%init-open "/sys/class/tty/console/active" 0 0))
    (def buf (%init-make-str 64))
    (def n (match ((< fd 0) 0) (#t (%init-read fd buf 64))))
    (match ((< fd 0) ()) (#t (%init-close fd)))
    (match
      ((< n 2) ())
      (#t (Str8 append "/dev/"
            (List last (Str8 split " " (Str8 sub 0 (- n 1) buf))))))))

; The shell's own session, with the terminal as its controlling terminal: a
; session leader that opens a terminal it has none of takes it.  Without one
; the shell runs on the console as it is and no key raises a signal.
(def %init-take-terminal
  (fn (_)
    (def tty (%init-console-tty))
    (%init-setsid)
    (def fd (match ((null? tty) -1) (#t (%init-open tty 2 0))))
    (match
      ((< fd 0) ())
      (#t (do (Sys dup2 fd 0)
              (Sys dup2 fd 1)
              (Sys dup2 fd 2)
              (match ((> fd 2) (%init-close fd)) (#t ())))))))

(def %init-spawn
  (fn (_)
    (def pid (Sys fork))
    (match
      ((= pid 0)
        (do (%init-take-terminal)
            (Sys exec %init-shell ())
            (%init-say "cannot run " %init-shell)
            (Sys exit 127)))
      (#t pid))))

; Every child that ends is collected here, the shell's own and the ones whose
; parents ended first.  The shell ending starts another after a second, so a
; shell that cannot start does not spin.
(def %init-serve
  (fn (self shell)
    (def pid (%init-wait4 -1 () 0 ()))
    ((prim-ref (lit heap) (lit collect)))
    (match
      ((= pid shell)
        (do (Sys sleep 1)
            (self (%init-spawn))))
      ((< pid 0)
        (do (Sys sleep 1)
            (self shell)))
      (#t (self shell)))))

; One form, and the last: the engine reads its program a form at a time from
; descriptor 0, so nothing after the console is put back there would be read
; from this file.
(def %init-main
  (fn (_)
    (Sys dup2 3 0)
    (Sys close 3)
    (%init-mount-all %init-mounts)
    (%init-load-modules)
    (%init-serve (%init-spawn))))

(%init-main)
