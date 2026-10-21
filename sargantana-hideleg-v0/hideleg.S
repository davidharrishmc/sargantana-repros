# Reproducer: a VS-level interrupt delegated to VS-mode by hideleg must not be taken while V = 0.
# Hypervisor spec: an interrupt delegated to HS-mode "is further delegated to VS-mode if the corresponding hideleg
# bit is set" (norm:hideleg_op), and it traps to HS-mode only when "bit i is not set in hideleg" (norm:hideleg_hs).
# Privileged spec: interrupts for lower-privilege modes "are always globally disabled" (norm:mstatus_xie_intr_en_dis),
# and HS-mode is more privileged than VS-mode; "VS-mode interrupts are globally disabled when executing in U-mode".
#
# Each case runs from M-mode: hie = 0x444, hideleg and hvip as given, sstatus.SIE = vsstatus.SIE = 1, then mret to
# the target mode, which spins and then ecalls to M-mode. The HS-mode and VS-mode handlers record where the
# interrupt was taken and its cause, then ecall to M-mode. Printed: where the interrupt was taken (none, HS or VS)
# and its cause, and the expectation. Exit code = number of wrong cases.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, mtrap
  csrw  mtvec, t0
  la    t0, strap
  csrw  stvec, t0
  la    t0, vstrap
  csrw  vstvec, t0
  csrw  hgatp, zero
  csrw  vsatp, zero
  csrw  medeleg, zero
  csrw  hedeleg, zero
  csrw  mideleg, zero            # the VS-level bits of mideleg are read-only one
  li    s1, 0
  la    a0, h_cases; call puts

# CASE(name, mpp, mpv, hideleg, hvip, expected where (0 none, 1 HS, 2 VS), expected cause)
#define CASE(name, mpp, mpv, hdl, hv, ew, ec) \
  la    s4, 9f                  ;\
  li    s5, mpp                 ;\
  li    s6, mpv                 ;\
  li    s7, hdl                 ;\
  li    s8, hv                  ;\
  li    s9, ew                  ;\
  li    s10, ec                 ;\
  la    s11, name               ;\
  j     run_case                ;\
9:
  CASE(c_hs_vssi,  0x0800, 0, 0x004, 0x004, 0, 0)
  CASE(c_hs_vsei,  0x0800, 0, 0x400, 0x400, 0, 0)
  CASE(c_u_vssi,   0x0000, 0, 0x004, 0x004, 0, 0)
  CASE(c_vs_vssi,  0x0800, 1, 0x004, 0x004, 2, 0x8000000000000001)
  CASE(c_hs_nodeleg, 0x0800, 0, 0x000, 0x004, 1, 0x8000000000000002)

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

run_case:
  li    s2, 0                    # where taken: 0 none, 1 HS, 2 VS
  li    s3, 0                    # cause
  csrw  hvip, zero
  li    t0, 0x444
  csrw  hie, t0
  csrw  hideleg, s7
  csrsi sstatus, 2               # sstatus.SIE = 1
  csrsi vsstatus, 2              # vsstatus.SIE = 1
  csrw  vsie, zero
  li    t0, 0x222
  csrs  vsie, t0                 # vsie = SSIE|STIE|SEIE (the delegated VS-level enables)
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  csrs  mstatus, s5
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  beqz  s6, 1f
  csrs  mstatus, t0
1: la    t0, in_target
  csrw  mepc, t0
  csrw  hvip, s8                 # pending
  mret
in_target:
  li    t0, 512
1: addi t0, t0, -1
  bnez  t0, 1b
  ecall
strap:
  li    s2, 1
  csrr  s3, scause
  ecall
vstrap:
  li    s2, 2
  csrr  s3, scause               # vscause in VS-mode
  ecall
mtrap:
  csrw  hvip, zero
  csrw  hie, zero
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0
  la    t0, report
  csrw  mepc, t0
  mret
report:
  mv    a0, s11; call puts
  la    a0, s_taken; call puts
  slli  t0, s2, 2
  la    a0, s_where
  add   a0, a0, t0
  call  puts
  la    a0, s_cause; call puts
  mv    a0, s3; li a1, 16; call puthex
  la    a0, s_exp; call puts
  slli  t0, s9, 2
  la    a0, s_where
  add   a0, a0, t0
  call  puts
  la    a0, s_ok
  bne   s2, s9, 2f
  bne   s3, s10, 2f
  j     1f
2: addi  s1, s1, 1
  la    a0, s_bad
1: call puts
  jr    s4

# puts(a0 = string): append to outbuf
puts:
  la    t1, outlen; ld t2, 0(t1)
  la    t3, htif_iobuf; add t3, t3, t2
1: lbu  t0, 0(a0)
  beqz  t0, 2f
  sb    t0, 0(t3)
  addi  a0, a0, 1; addi t3, t3, 1; addi t2, t2, 1
  j     1b
2: sd   t2, 0(t1)
  ret

# puthex(a0 = value, a1 = digits)
puthex:
  la    t1, outlen; ld t2, 0(t1)
  la    t3, htif_iobuf; add t3, t3, t2
  slli  t4, a1, 2
1: addi t4, t4, -4
  srl   t0, a0, t4; andi t0, t0, 15
  addi  t5, t0, '0'
  li    t6, 10
  blt   t0, t6, 2f
  addi  t5, t0, 'a'-10
2: sb   t5, 0(t3)
  addi  t3, t3, 1; addi t2, t2, 1
  bnez  t4, 1b
  sd    t2, 0(t1)
  ret

# flush: one HTIF SYS_write of outbuf (the tile reads the buffer with word-aligned
# DPI reads and needs the stores drained before tohost is seen)
flush:
  la    t1, htif_magicmem
  li    t0, 64;  sd t0, 0(t1)         # SYS_write
  li    t0, 1;   sd t0, 8(t1)         # stdout
  la    t0, htif_iobuf; sd t0, 16(t1)
  la    t0, outlen; ld t0, 0(t0); sd t0, 24(t1)
  fence
  li    t0, 100
1: addi t0, t0, -1
  bnez  t0, 1b
  la    t0, tohost
  sd    t1, 0(t0)
  li    t0, 50000                     # let the host see the console syscall before the exit write
1: addi t0, t0, -1
  bnez  t0, 1b
  ret

  .section .rodata
h_cases:      .string "hie = 0x444, sstatus.SIE = vsstatus.SIE = 1; where the pending interrupt is taken:\n"
c_hs_vssi:    .string "  HS-mode, hideleg.VSSI = 1, VSSI pending:   "
c_hs_vsei:    .string "  HS-mode, hideleg.VSEI = 1, VSEI pending:   "
c_u_vssi:     .string "  U-mode,  hideleg.VSSI = 1, VSSI pending:   "
c_vs_vssi:    .string "  VS-mode, hideleg.VSSI = 1, VSSI pending:   "
c_hs_nodeleg: .string "  HS-mode, hideleg = 0,      VSSI pending:   "
s_taken:      .string "taken in "
  .balign 4
s_where:      .string "--"
  .balign 4
              .string "HS"
  .balign 4
              .string "VS"
s_cause:      .string " cause="
s_exp:        .string "  expected "
s_ok:         .string "\n"
s_bad:        .string "   <-- wrong\n"

  .section .data
  .balign 8
outlen:   .dword 0
  .balign 16
  .space 4096
stack_top:

  .section .tohost, "aw", @progbits
  .balign 64; .globl tohost;   tohost:   .dword 0
  .balign 64; .globl fromhost; fromhost: .dword 0
  .balign 64; htif_magicmem: .dword 0,0,0,0,0,0,0,0
  .balign 64; htif_iobuf: .fill 8192,1,0
