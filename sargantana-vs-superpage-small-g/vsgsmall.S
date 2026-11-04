# Reproducer: two-stage translation where the VS-stage leaf is a superpage and the G-stage leaf for the guest
# physical address is smaller.
# Hypervisor spec (norm:H_vm_twostage): the guest virtual address "is converted in the first stage by VS-level address
# translation ... into a guest physical address. The guest physical address is then converted in the second stage";
# for a VS-stage superpage the guest physical address takes VA bits below the leaf level (privileged spec, Sv39
# step 8: "pa.ppn[i-1:0] = va.vpn[i-1:0]"), and the G stage translates that address.
#
# Sv39 over Sv39x4. The image is identity-mapped in both stages with 1 GiB leaves. In every case the accessed guest
# physical address is mapped by the G stage to the page holding `marker`; the first 2 MiB or 4 KiB of the VS-stage
# superpage (the superpage's base guest physical address) is not mapped by the G stage, except in c_base where it is
# and the accessed address is not.
#   c_1g_2m: VA 0x1_0000_0000 is a 1 GiB VS leaf on GPA 0x1_4000_0000; the G stage maps GPA 0x1_4020_0000 (2 MiB)
#            to PA 0x8000_0000. lw 0x1_0020_0000 + (marker - 0x8000_0000) must return 0x5a5a1234.
#   c_2m_4k: VA 0x1_4000_0000 is a 2 MiB VS leaf on GPA 0x1_8000_0000; the G stage maps GPA 0x1_8000_1000 (4 KiB) to
#            marker's page. lw 0x1_4000_1000 + (marker & 0xfff) must return 0x5a5a1234.
#   c_base:  VA 0x1_8000_0000 is a 1 GiB VS leaf on GPA 0x1_c000_0000; the G stage maps GPA 0x1_c000_0000 (2 MiB) to PA
#            0x8000_0000 and not GPA 0x1_c020_0000. lw 0x1_8020_0000 + (marker - 0x8000_0000) must raise a load
#            guest-page fault with mtval2 = 0x1_c020_0000 + (marker - 0x8000_0000) >> 2.
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)  # G: image identity, 1 GiB
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)          # VS: image identity, 1 GiB
  # c_1g_2m
  li    a0, 0x140000000
  SETPTE vroot, 4, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)          # VA 0x1_0000_0000 -> GPA 0x1_4000_0000, 1 GiB
  la    a0, gt1a
  SETPTE groot, 5, a0, PTE_V                                                    # GPA 0x1_4000_0000 -> gt1a
  li    a0, 0x80000000
  SETPTE gt1a, 1, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)   # GPA 0x1_4020_0000 -> PA 0x8000_0000, 2 MiB
  # c_2m_4k
  la    a0, vt1b
  SETPTE vroot, 5, a0, PTE_V
  li    a0, 0x180000000
  SETPTE vt1b, 0, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)           # VA 0x1_4000_0000 -> GPA 0x1_8000_0000, 2 MiB
  la    a0, gt1b
  SETPTE groot, 6, a0, PTE_V
  la    a0, gt0b
  SETPTE gt1b, 0, a0, PTE_V
  la    a0, marker
  SETPTE gt0b, 1, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)   # GPA 0x1_8000_1000 -> marker's page, 4 KiB
  # c_base
  li    a0, 0x1c0000000
  SETPTE vroot, 6, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)          # VA 0x1_8000_0000 -> GPA 0x1_c000_0000, 1 GiB
  la    a0, gt1c
  SETPTE groot, 7, a0, PTE_V
  li    a0, 0x80000000
  SETPTE gt1c, 0, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)   # GPA 0x1_c000_0000 -> PA 0x8000_0000, 2 MiB
  SETATP hgatp, groot
  SETATP vsatp, vroot
  ret

cases:
  #         name      code  MPV MPP    mstatus hstatus vsstatus symbol  adjust                     mcause GVA mtval2 a1
  CASE_SYM(c_1g_2m, g_lw, 1, MPP_S, 0,      0,      0,       marker, 0x100200000 - 0x80000000, 10,    ANY, ANY,   0x5a5a1234)
  CASE(c_2m_4k,     g_lw, 1, MPP_S, 0,      0,      0,       0x140001234,                      10,    ANY, ANY,   0x5a5a1234)
  CASE_SYM(c_base,  g_lw, 1, MPP_S, 0,      0,      0,       marker, 0x180200000 - 0x80000000, 21,    1,   ANY,   ANY)
  CASE_SYM(c_ctrl,  g_lw, 1, MPP_S, 0,      0,      0,       marker, 0,                        10,    ANY, ANY,   0x5a5a1234)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall

  .section .rodata
h_cases: .string "VS-mode loads through a VS-stage superpage over a smaller G-stage leaf (Sv39 over Sv39x4):\n"
c_1g_2m: .string "  VS 1 GiB over G 2 MiB                 "
c_2m_4k: .string "  VS 2 MiB over G 4 KiB                 "
c_base:  .string "  VS 1 GiB, only base 2 MiB G-mapped    "
c_ctrl:  .string "  VS 1 GiB over G 1 GiB (ctrl)          "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1b:  .fill 512, 8, 0
gt1a:  .fill 512, 8, 0
gt1b:  .fill 512, 8, 0
gt0b:  .fill 512, 8, 0
gt1c:  .fill 512, 8, 0
  .balign 4096
mpage:
  .fill 0x234, 1, 0
marker: .word 0x5a5a1234
