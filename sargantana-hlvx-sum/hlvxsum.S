# Reproducer: HLVX.WU from HS-mode with hstatus.SPVP = 1 on a VS-stage page with U = 1 and vsstatus.SUM = 1.
# Hypervisor spec (norm:hlvx_perm): "HLVX.HU and HLVX.WU are the same as HLV.HU and HLV.WU, except that execute
# permission takes the place of read permission during address translation. That is, the memory being read must be
# executable in both stages of address translation, but read permission is not required." The U-bit rule for these
# VS-level accesses stays that of a load: with vsstatus.SUM = 1 a supervisor-level load may access a U = 1 page
# (privileged spec, norm:sstatus_sum_op), and hstatus.SPVP = 1 makes HLVX a VS-level (supervisor) access.
#
# Two-stage translation (Sv39 over Sv39x4), identity-mapped image. VA 0xc000_1000 is a 4 KiB VS-stage leaf with U = 1
# and X = 1 only, VA 0xc000_2000 one with U = 1 and R = 1 only, both on the page holding `marker`.
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  la    a0, mpage
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V)                    # U, execute-only
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_R | PTE_V)                    # U, read-only
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #     name        code    MPV MPP    mstatus hstatus       vsstatus     address     mcause GVA mtval2 a1
  CASE(c_x_sum1,  g_hlvx, 0, MPP_S, 0,      HSTATUS_SPVP, SSTATUS_SUM, 0xc0001234, 9,     ANY, ANY,   0x5a5a1234)
  CASE(c_x_sum0,  g_hlvx, 0, MPP_S, 0,      HSTATUS_SPVP, 0,           0xc0001234, 13,    ANY, ANY,   ANY)
  CASE(c_x_spvp0, g_hlvx, 0, MPP_S, 0,      0,            0,           0xc0001234, 9,     ANY, ANY,   0x5a5a1234)
  CASE(c_r_sum1,  g_hlv,  0, MPP_S, 0,      HSTATUS_SPVP, SSTATUS_SUM, 0xc0002234, 9,     ANY, ANY,   0x5a5a1234)
  CASE(c_r_hlvx,  g_hlvx, 0, MPP_S, 0,      HSTATUS_SPVP, SSTATUS_SUM, 0xc0002234, 13,    ANY, ANY,   ANY)
  j     finish

g_hlvx: hlvx.wu a1, (a0); ecall
g_hlv:  hlv.w   a1, (a0); ecall

  .section .rodata
h_cases:   .string "HS-mode HLVX.WU / HLV.W on VS-stage pages with U = 1 (a1 = loaded word):\n"
c_x_sum1:  .string "  hlvx.wu, leaf UX, SPVP=1, SUM=1      "
c_x_sum0:  .string "  hlvx.wu, leaf UX, SPVP=1, SUM=0      "
c_x_spvp0: .string "  hlvx.wu, leaf UX, SPVP=0 (ctrl)      "
c_r_sum1:  .string "  hlv.w,   leaf UR, SPVP=1, SUM=1 (ctrl)"
c_r_hlvx:  .string "  hlvx.wu, leaf UR, SPVP=1, SUM=1 (ctrl)"

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
  .balign 4096
mpage:
  .fill 0x234, 1, 0
marker: .word 0x5a5a1234
