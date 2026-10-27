# Reproducer: a CSR write to mtval2 writes mip instead of mtval2.
# Hypervisor extension (norm:mtval2_op): mtval2 is a WARL register that holds a guest physical address shifted right
# by 2; writing it must not change mip. In M-mode with mie = 0, this writes 0x2222 (the SSIP, STIP, SEIP and LCOFIP
# bit positions) to mtval2 and reads back those bits of mip, and mtval2. Exit code = number of wrong values.
#include "harness.inc"
  .text
cases:
  csrw  mip, zero
  li    s5, 0x2222
  csrw  mtval2, s5
  csrr  s6, mip
  and   s6, s6, s5              # only the bits written; MTIP, MSIP and MEIP follow the platform
  csrr  s7, mtval2
  csrw  mip, zero
  la    a0, c_mip; call puts
  mv    a0, s6; li a1, 16; call puthex
  la    a0, c_mip_exp; call puts
  beqz  s6, 1f
  addi  s1, s1, 1
  la    a0, s_bad; call puts
  j     2f
1: la   a0, s_ok; call puts
2: la   a0, c_mtval2; call puts
  mv    a0, s7; li a1, 16; call puthex
  la    a0, c_mtval2_exp; call puts
  li    t0, 0x2220              # bit 1 may be read-only zero (mtval2 holds a GPA >> 2; low bits are WARL)
  and   t1, s7, t0
  beq   t1, t0, 3f
  addi  s1, s1, 1
  la    a0, s_bad; call puts
  j     finish
3: la   a0, s_ok; call puts
  j     finish

  .section .rodata
h_cases:      .string "csrw mtval2, 0x2222 in M-mode with mie = 0:\n"
c_mip:        .string "  mip & 0x2222 = "
c_mip_exp:    .string "   expected 0000000000000000"
c_mtval2:     .string "  mtval2       = "
c_mtval2_exp: .string "   expected 0000000000002222"
