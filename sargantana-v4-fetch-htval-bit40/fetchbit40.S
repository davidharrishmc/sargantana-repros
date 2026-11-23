# Reproducer: on core_tile v4.0, mtval2 on an instruction guest-page fault loses guest-physical-address bit 40.
# Hypervisor spec: on a guest-page fault, mtval2 (and htval) "is written with either zero or the guest physical
# address that faulted, shifted right by 2 bits" (norm:mtval2_trapval, norm:htval_trapval); with Shtvala, htval
# "must be written with the faulting guest physical address" (norm:shtvala_htval_faulting_gpa).
#
# Two-stage translation (Sv39 over Sv39x4), identity-mapped image. VA 0xc000_3000 and 0xc000_4000 are VS-stage
# leaves on guest physical addresses (1 << 40) + 0x8000_3000 and (1 << 39) + 0x8000_4000. Both are below Sv39x4's
# 41-bit limit, and the G-stage root entries for them are invalid, so every access takes a guest-page fault.
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
  li    a0, (1 << 40) + 0x80003000
  SETPTE vt0, 3, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  li    a0, (1 << 39) + 0x80004000
  SETPTE vt0, 4, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #     name       code    MPV MPP    mstatus hstatus vsstatus address     mcause GVA mtval2                          a1
  CASE(c_lw40,   g_lw,   1, MPP_S, 0,      0,      0,       0xc0003008, 21,    1,   ((1 << 40) + 0x80003008) >> 2, ANY)
  CASE(c_sw40,   g_sw,   1, MPP_S, 0,      0,      0,       0xc0003008, 23,    1,   ((1 << 40) + 0x80003008) >> 2, ANY)
  CASE(c_jalr40, g_jalr, 1, MPP_S, 0,      0,      0,       0xc0003008, 20,    1,   ((1 << 40) + 0x80003008) >> 2, ANY)
  CASE(c_jalr39, g_jalr, 1, MPP_S, 0,      0,      0,       0xc0004008, 20,    1,   ((1 << 39) + 0x80004008) >> 2, ANY)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_jalr: jalr  t0, 0(a0);  ecall

  .section .rodata
h_cases:  .string "VS-mode accesses whose guest physical address has bit 40 or bit 39 set (guest-page fault):\n"
c_lw40:   .string "  lw   GPA (1<<40)+0x80003008          "
c_sw40:   .string "  sw   GPA (1<<40)+0x80003008          "
c_jalr40: .string "  jalr GPA (1<<40)+0x80003008          "
c_jalr39: .string "  jalr GPA (1<<39)+0x80004008 (ctrl)   "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
