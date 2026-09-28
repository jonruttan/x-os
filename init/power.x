; # x-os -- poweroff, reboot, halt
;
; ## power.x -- flush, then ask the kernel
;
; The stream that runs this defines %power-how ahead of it: one of poweroff,
; reboot or halt.  reboot(2) wants its two magic numbers and then the command.

(def %power-reboot (syscall-door (lit reboot)))

(def %power-commands
  (lit ((poweroff 1126301404)      ; LINUX_REBOOT_CMD_POWER_OFF  0x4321fedc
        (reboot   19088743)        ; LINUX_REBOOT_CMD_RESTART    0x01234567
        (halt     3454992675))))   ; LINUX_REBOOT_CMD_HALT       0xcdef0123

(def %power-main
  (fn (_)
    (def row (Assoc get %power-how %power-commands))
    (Sys sync)
    ; LINUX_REBOOT_MAGIC1 0xfee1dead, LINUX_REBOOT_MAGIC2 672274793
    (def r (%power-reboot 4276215469 672274793 (first row) ()))
    (display "power: the kernel refused")
    (newline)
    (Sys exit 1)))

(%power-main)
