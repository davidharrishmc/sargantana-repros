# Reproducer: mstatus.GVA on load and store page faults from VS-mode.
# Hypervisor extension (norm:mstatus_gva_op): "For any trap (breakpoint, address misaligned, access fault, page
# fault, or guest-page fault) that writes a guest virtual address to mtval, GVA is set to 1." A VS-stage load or
# store page fault writes the guest virtual address to mtval, so GVA = 1; the same holds for hstatus.GVA when the
# trap goes to HS-mode (norm:hstatus_gva_op).
#
# Two-stage translation, Sv39 (vsatp) over Sv39x4 (hgatp), identity-mapped image. VA 0xc000_n000 are 4 KiB VS-stage
# leaves on a mapped page: n = 1 execute-only, 2 read-only, 3 read-write (not executable). Every trap goes to M-mode.
# The fetch page fault and the guest-page fault are controls (Sargantana sets GVA there).
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)   # G: GPA 0x8000_0000 1 GiB identity
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)           # VS: VA 0x8000_0000 1 GiB identity
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  la    a0, page
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_X | PTE_V)                             # execute-only
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_R | PTE_V)                             # read-only
  SETPTE vt0, 3, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)                     # read-write, not executable
  li    a0, 0x140000000
  SETPTE vt0, 4, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)                     # GPA unmapped in the G-stage
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #     name     code    MPV MPP    mstatus hstatus       vsstatus address     mcause GVA mtval2 a1
  CASE(c_lw,   g_lw,   1, MPP_S, 0,      0,            0,       0xc0001000, 13,    1,  0,     ANY)
  CASE(c_sw,   g_sw,   1, MPP_S, 0,      0,            0,       0xc0002000, 15,    1,  0,     ANY)
  CASE(c_hlv,  g_hlv,  0, MPP_S, 0,      HSTATUS_SPVP, 0,       0xc0001000, 13,    1,  0,     ANY)
  CASE(c_hsv,  g_hsv,  0, MPP_S, 0,      HSTATUS_SPVP, 0,       0xc0002000, 15,    1,  0,     ANY)
  CASE(c_jalr, g_jalr, 1, MPP_S, 0,      0,            0,       0xc0003000, 12,    1,  0,     ANY)
  CASE(c_gpf,  g_lw,   1, MPP_S, 0,      0,            0,       0xc0004000, 21,    1,  0x50000000, ANY)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_hlv:  hlv.w a1, (a0);   ecall
g_hsv:  hsv.w zero, (a0); ecall
g_jalr: jalr  t0, 0(a0);  ecall

  .section .rodata
h_cases: .string "Traps from VS-stage translation, taken in M-mode (cause, mstatus.GVA, mtval2, mtinst, a1; all hex):\n"
c_lw:    .string "  VS lw    0xc0001000, leaf X only     "
c_sw:    .string "  VS sw    0xc0002000, leaf R only     "
c_hlv:   .string "  HS hlv.w 0xc0001000, leaf X only     "
c_hsv:   .string "  HS hsv.w 0xc0002000, leaf R only     "
c_jalr:  .string "  VS jalr  0xc0003000, leaf RW (ctrl)  "
c_gpf:   .string "  VS lw    0xc0004000, GPA unmapped (ctrl) "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
page:  .fill 512, 8, 0
