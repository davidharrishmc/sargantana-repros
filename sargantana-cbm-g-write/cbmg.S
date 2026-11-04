# Reproducer: cbo.clean, cbo.flush and cbo.inval from VS-mode on a page that the G stage maps read-only.
# Zicbom (norm:cbm_access): "A cache-block management instruction is permitted to access the specified cache block
# whenever a load instruction or store instruction is permitted to access the corresponding physical addresses";
# (norm:cbm_unperm_translate) "During address translation, the instruction also checks the accessed bit" (not the
# dirty bit). Hypervisor spec (norm:H_vm_gpapriv): access-type permissions are "checked during G-stage translation
# the same as for VS-stage translation". cbo.zero needs store permission (norm:cbz_access) and is a control.
#
# Two-stage translation (Sv39 over Sv39x4). VA 0xc000_1000 and 0xc000_2000 are read-write VS-stage leaves on GPA
# 0x1_4000_1000 and 0x1_4000_2000; the G stage maps the first read-only (U, R, A, D) and the second read-write with
# D = 0 (U, R, W, A), both onto the page `cpage`. menvcfg and henvcfg have CBIE = 01, CBCFE = 1, CBZE = 1.
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  la    a0, gt1
  SETPTE groot, 5, a0, PTE_V                                                    # GPA 0x1_4000_0000
  la    a0, gt0
  SETPTE gt1, 0, a0, PTE_V
  la    a0, cpage
  SETPTE gt0, 1, a0, (PTE_D | PTE_A | PTE_U | PTE_R | PTE_V)                    # G: read-only
  SETPTE gt0, 2, a0, (PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)                    # G: read-write, D = 0
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  li    a0, 0x140001000
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)
  li    a0, 0x140002000
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #     name        code     MPV MPP    mstatus hstatus vsstatus address     mcause GVA mtval2      a1
  CASE(c_clean,   g_clean, 1, MPP_S, 0,      0,      0,       0xc0001000, 10,    ANY, ANY,        ANY)
  CASE(c_flush,   g_flush, 1, MPP_S, 0,      0,      0,       0xc0001000, 10,    ANY, ANY,        ANY)
  CASE(c_inval,   g_inval, 1, MPP_S, 0,      0,      0,       0xc0001000, 10,    ANY, ANY,        ANY)
  CASE(c_zero,    g_zero,  1, MPP_S, 0,      0,      0,       0xc0001000, 23,    1,   0x50000400, ANY)
  CASE(c_clean_d, g_clean, 1, MPP_S, 0,      0,      0,       0xc0002000, 10,    ANY, ANY,        ANY)
  CASE(c_zero_d,  g_zero,  1, MPP_S, 0,      0,      0,       0xc0002000, 23,    1,   0x50000800, ANY)
  j     finish

g_clean: cbo.clean (a0); ecall
g_flush: cbo.flush (a0); ecall
g_inval: cbo.inval (a0); ecall
g_zero:  cbo.zero  (a0); ecall

  .section .rodata
h_cases:   .string "VS-mode cache-block operations; the G stage maps the page read-only (c_*) or read-write with D = 0 (*_d):\n"
c_clean:   .string "  cbo.clean 0xc0001000, G read-only    "
c_flush:   .string "  cbo.flush 0xc0001000, G read-only    "
c_inval:   .string "  cbo.inval 0xc0001000, G read-only    "
c_zero:    .string "  cbo.zero  0xc0001000, G read-only (ctrl)"
c_clean_d: .string "  cbo.clean 0xc0002000, G RW, D = 0    "
c_zero_d:  .string "  cbo.zero  0xc0002000, G RW, D = 0 (ctrl)"

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
gt1:   .fill 512, 8, 0
gt0:   .fill 512, 8, 0
cpage: .fill 512, 8, 0
