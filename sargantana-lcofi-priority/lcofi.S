# Reproducer: interrupt priority in HS-mode between LCOFI and the VS-level interrupts.
# Privileged spec, Hypervisor extension (norm:hsint_priority): "Multiple simultaneous interrupts destined for
# HS-mode are handled in the following decreasing priority order: SEI, SSI, STI, SGEI, VSEI, VSSI, VSTI, LCOFI."
#
# Each case runs from M-mode with mstatus.MIE = 0: it clears every pending and enable bit, then makes a pair of
# interrupts pending (mip.SSIP, mip.LCOFIP and hvip.VSxIP, all written from M-mode) and enables both in mie (mie
# aliases hie for the VS-level bits). mideleg delegates SSI and LCOFI to HS-mode; the VS-level bits of mideleg are
# read-only one with H, and hideleg = 0, so every interrupt here targets HS-mode. It records mip, mie and hip,
# then mrets to HS-mode with sstatus.SIE = 1. The HS handler records scause and ecalls back to M-mode.
# Printed per case: mip, mie, hip before the mret, the scause taken, and the scause expected.
# Exit code = number of cases taking the wrong interrupt first.

#define MSTATUS_MPP   0x1800
#define MSTATUS_MPP_S 0x0800

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, mtrap
  csrw  mtvec, t0
  la    t0, strap
  csrw  stvec, t0
  csrw  hgatp, zero
  csrw  hideleg, zero
  li    t0, (1 << 13) | (1 << 1)
  csrw  mideleg, t0              # SSI and LCOFI to HS-mode
  csrw  medeleg, zero
  li    t0, -1
  csrw  mcounteren, t0
  li    s1, 0
  la    a0, h_cases; call puts

#define CASE(name, pend_mip, pend_hvip, en, expect) \
  la    s4, 9f                  ;\
  li    s5, pend_mip            ;\
  li    s6, pend_hvip           ;\
  li    s7, en                  ;\
  la    s8, name                ;\
  li    s9, expect              ;\
  j     run_case                ;\
9:

  CASE(c_vsei_lcofi, 0x2000, 0x400, 0x2400, 0x800000000000000a)
  CASE(c_vssi_lcofi, 0x2000, 0x004, 0x2004, 0x8000000000000002)
  CASE(c_vsti_lcofi, 0x2000, 0x040, 0x2040, 0x8000000000000006)
  CASE(c_ssi_lcofi,  0x2002, 0x000, 0x2002, 0x8000000000000001)
  CASE(c_ssi_vsei,   0x0002, 0x400, 0x0402, 0x8000000000000001)
  CASE(c_vsei_vssi,  0x0000, 0x404, 0x0404, 0x800000000000000a)

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# run_case: s5 = mip bits to set, s6 = hvip bits, s7 = mie bits, s8 = name, s9 = expected scause; returns to s4
run_case:
  csrci mstatus, 8               # MIE = 0
  csrw  mie, zero
  csrw  hvip, zero
  li    t0, 0x2222
  csrc  mip, t0                  # clear SSIP, STIP, SEIP, LCOFIP where writable
  csrs  mip, s5
  csrs  hvip, s6
  csrw  mie, s7
  li    t0, 64                   # let the pending bits settle
1: addi t0, t0, -1
  bnez  t0, 1b
  csrr  s10, mip
  csrr  s11, mie
  csrr  s3, hip
  csrsi sstatus, 2               # sstatus.SIE = 1
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP_S
  csrs  mstatus, t0              # MPP = S, MPV = 0
  la    t0, in_hs
  csrw  mepc, t0
  li    s2, 0                    # scause, 0 if nothing is taken
  mret
in_hs:
  li    t0, 256
1: addi t0, t0, -1
  bnez  t0, 1b
  ecall                          # nothing taken: back to M-mode
strap:
  csrr  s2, scause
  csrci sstatus, 2
  ecall
mtrap:                           # ecall from HS-mode: report and continue in M-mode
  csrw  mie, zero
  csrw  hvip, zero
  li    t0, 0x2222
  csrc  mip, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0
  la    t0, report_ret
  csrw  mepc, t0
  mret
report_ret:
  mv    a0, s8; call puts
  la    a0, s_mip; call puts
  mv    a0, s10; li a1, 4; call puthex
  la    a0, s_mie; call puts
  mv    a0, s11; li a1, 4; call puthex
  la    a0, s_hip; call puts
  mv    a0, s3; li a1, 4; call puthex
  la    a0, s_taken; call puts
  mv    a0, s2; li a1, 16; call puthex
  la    a0, s_exp; call puts
  mv    a0, s9; li a1, 16; call puthex
  la    a0, s_ok
  beq   s2, s9, 1f
  addi  s1, s1, 1
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
h_cases:      .string "Pending and enabled pair, HS-mode with sstatus.SIE = 1; first scause taken:\n"
c_vsei_lcofi: .string "  VSEI + LCOFI "
c_vssi_lcofi: .string "  VSSI + LCOFI "
c_vsti_lcofi: .string "  VSTI + LCOFI "
c_ssi_lcofi:  .string "  SSI  + LCOFI "
c_ssi_vsei:   .string "  SSI  + VSEI  "
c_vsei_vssi:  .string "  VSEI + VSSI  "
s_mip:        .string " mip="
s_mie:        .string " mie="
s_hip:        .string " hip="
s_taken:      .string " taken="
s_exp:        .string " expected="
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
