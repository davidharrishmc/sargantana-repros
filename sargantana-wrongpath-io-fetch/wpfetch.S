# Reproducer: a wrong-path fetch from the IO region deadlocks core_tile.
#
# The beq is taken, so the jal after it is never executed.  It is fetched on the
# wrong path while the beq is still unresolved (predicted not taken), and the
# frontend follows it to 0x7fff_f00c.  That address is in DracDefaultConfig's IO
# section (0x4000_0000-0x7fff_ffff), so the fetch goes out as a non-cacheable
# request.  When the beq resolves, the core must discard the wrong path and continue
# at label 1.
#
# Exit code 0: the beq target was reached.  On core_tile the testbench's
# 200-cycle no-commit watchdog fires instead.

  .section .text.init
  .globl _start
_start:
  li    t1, 1
  li    tp, 1
  beq   tp, t1, 1f              # taken
  jal   zero, . - 0x1000        # wrong path only: target 0x7fff_f00c (IO region)
1:
  li    t0, 1                   # tohost = (0 << 1) | 1: pass
  la    t1, tohost
  sd    t0, 0(t1)
2: j 2b

  .section .tohost, "aw", @progbits
  .balign 64
  .globl tohost
tohost: .dword 0
  .balign 64
  .globl fromhost
fromhost: .dword 0
