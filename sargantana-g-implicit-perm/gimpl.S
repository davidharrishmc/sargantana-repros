# Reproducer: G-stage permission check on the implicit read of a VS-level page-table entry.
# Hypervisor spec (norm:H_vm_gpapriv): "For a memory access made to support VS-stage address translation (such as to
# read/write a VS-level page table), permissions and the need to set A and/or D bits at the G-stage level are checked
# as though for an implicit load or store, not for the original access type. However, any exception is always
# reported for the original access type". Reading a VS-level PTE therefore needs a G-stage leaf with R = 1 (and A = 1
# without Svadu); otherwise the access takes a guest-page fault whose mtval2 is the PTE's guest physical address >> 2
# and whose mtinst is the 0x3000 pseudoinstruction (norm:H_trap_xtinst_guestpage).
#
# Two-stage translation (Sv39 over Sv39x4). Both stages map the image with 4 KiB identity leaves (G: U, RWX), except the
# G-stage leaf for the page holding the VS-level table vt0, which is execute-only (U, X), and for the page holding
# vt0b, which has A = 0.
# VA 0xc000_1000 goes through vt0 and VA 0x1_0000_1000 through vt0b; both leaves map `marker`'s page read-write.
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  MAP4K gt0, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)        # GPA 0x8000_0000..0x801f_ffff, 4 KiB
  la    a0, gt0
  SETPTE gt1, 0, a0, PTE_V
  la    a0, gt1
  SETPTE groot, 2, a0, PTE_V
  # vt0's page: execute-only in the G stage; vt0b's page: A = 0
  la    a0, vt0
  li    t5, 0x80000000
  sub   t6, a0, t5
  srli  t6, t6, 12                                                              # index of vt0's page in gt0
  la    t0, gt0
  slli  t6, t6, 3
  add   t0, t0, t6
  srli  t2, a0, 12
  slli  t2, t2, 10
  ori   t2, t2, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V)
  sd    t2, 0(t0)
  la    a0, vt0b
  sub   t6, a0, t5
  srli  t6, t6, 12
  la    t0, gt0
  slli  t6, t6, 3
  add   t0, t0, t6
  srli  t2, a0, 12
  slli  t2, t2, 10
  ori   t2, t2, (PTE_D | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  sd    t2, 0(t0)
  li    a0, 0x80000000
  MAP4K vt0c, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)               # VS: image identity, 4 KiB leaves
  la    a0, vt0c
  SETPTE vt1c, 0, a0, PTE_V
  la    a0, vt1c
  SETPTE vroot, 2, a0, PTE_V
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  la    a0, mpage
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)
  la    a0, vt1b
  SETPTE vroot, 4, a0, PTE_V
  la    a0, vt0b
  SETPTE vt1b, 0, a0, PTE_V
  la    a0, mpage
  SETPTE vt0b, 1, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #         name      code  MPV MPP    mstatus hstatus vsstatus symbol adjust mcause GVA mtval2 a1
  CASE(c_xonly, g_lw, 1, MPP_S, 0, 0, 0, 0xc0001234, 21,    1,   ANY,   ANY)
  CASE(c_a0, g_lw, 1, MPP_S, 0, 0, 0, 0x100001234, 21,    1,   ANY,   ANY)
  CASE_SYM(c_ctrl,  g_lw, 1, MPP_S, 0,      0,      0,       marker, 0,     10,    ANY, ANY,   0x5a5a1234)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall

  .section .rodata
h_cases: .string "VS-mode loads whose VS-level leaf PTE lies on a page the G stage maps execute-only or with A = 0:\n"
c_xonly: .string "  lw 0xc0001234, PTE page G: U X       "
c_a0:    .string "  lw 0x100001234, PTE page G: A = 0    "
c_ctrl:  .string "  lw marker (ctrl)                     "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
gt1:   .fill 512, 8, 0
gt0:   .fill 512, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
vt1b:  .fill 512, 8, 0
vt0b:  .fill 512, 8, 0
vt1c:  .fill 512, 8, 0
vt0c:  .fill 512, 8, 0
  .balign 4096
mpage:
  .fill 0x234, 1, 0
marker: .word 0x5a5a1234
