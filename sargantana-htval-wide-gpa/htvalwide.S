# Reproducer: mtval2 on a guest-page fault for a guest physical address wider than the Sv39x4 limit.
# Hypervisor spec: "Translation is a G-stage ... address bits 63:41 must all be zeros, or else a guest-page-fault
# exception occurs" (norm:H_vm_gpa_width); on a guest-page fault, mtval2 (and htval) "is written with either zero or
# the guest physical address that faulted, shifted right by 2 bits" (norm:mtval2_trapval, norm:htval_trapval), and
# with Shtvala htval "must be written with the faulting guest physical address" (norm:shtvala_htval_faulting_gpa).
#
# Two-stage translation (Sv39 over Sv39x4), identity-mapped image. VA 0xc000_1000 and 0xc000_2000 are VS-stage leaves
# whose PPN puts the guest physical address at (1 << 55) + 0x8000_1000 and (1 << 41) + 0x8000_2000.
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
  li    a0, (1 << 55) + 0x80001000
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  li    a0, (1 << 41) + 0x80002000
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #     name       code    MPV MPP    mstatus hstatus vsstatus address     mcause GVA mtval2                          a1
  CASE(c_lw55,   g_lw,   1, MPP_S, 0,      0,      0,       0xc0001008, 21,    1,   ((1 << 55) + 0x80001008) >> 2, ANY)
  CASE(c_sw55,   g_sw,   1, MPP_S, 0,      0,      0,       0xc0001008, 23,    1,   ((1 << 55) + 0x80001008) >> 2, ANY)
  CASE(c_jalr55, g_jalr, 1, MPP_S, 0,      0,      0,       0xc0001008, 20,    1,   ((1 << 55) + 0x80001008) >> 2, ANY)
  CASE(c_lw41,   g_lw,   1, MPP_S, 0,      0,      0,       0xc0002008, 21,    1,   ((1 << 41) + 0x80002008) >> 2, ANY)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_jalr: jalr  t0, 0(a0);  ecall

  .section .rodata
h_cases:  .string "VS-mode accesses whose guest physical address has bit 55 or bit 41 set (guest-page fault):\n"
c_lw55:   .string "  lw   GPA (1<<55)+0x80001008          "
c_sw55:   .string "  sw   GPA (1<<55)+0x80001008          "
c_jalr55: .string "  jalr GPA (1<<55)+0x80001008          "
c_lw41:   .string "  lw   GPA (1<<41)+0x80002008 (ctrl)   "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
