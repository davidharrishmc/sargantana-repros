# Reproducer: VS-stage translation with hgatp = Bare (VS-stage only) of an address inside a VS-stage superpage.
# Privileged spec, Sv39 translation process, step 8: for a superpage, "pa.ppn[i-1:0] = va.vpn[i-1:0]"; with the
# G-stage Bare the guest physical address is the supervisor physical address.
#
# hgatp = Bare, vsatp = Sv39. The image (VA = PA 0x8000_0000..0x801f_ffff) is mapped by 4 KiB VS-stage leaves.
# VA 0xc000_0000 is a 1 GiB VS-stage leaf and VA 0x8020_0000 a 2 MiB VS-stage leaf, both on PA 0x8000_0000, so
# VA 0xc000_0000 + x and 0x8020_0000 + x read PA 0x8000_0000 + x. Each case loads the word `marker` through one of
# these mappings in VS-mode; the load should return 0x5a5a1234. The 4 KiB mapping is the control.
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  MAP4K vt0c, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)               # VA = PA 0x8000_0000..0x801f_ffff, 4 KiB
  la    a0, vt0c
  SETPTE vt1c, 0, a0, PTE_V
  li    a0, 0x80000000
  SETPTE vt1c, 1, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)           # VA 0x8020_0000: 2 MiB leaf on PA 0x8000_0000
  la    a0, vt1c
  SETPTE vroot, 2, a0, PTE_V
  li    a0, 0x80000000
  SETPTE vroot, 3, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)          # VA 0xc000_0000: 1 GiB leaf on PA 0x8000_0000
  csrw  hgatp, zero
  SETATP vsatp, vroot
  ret

cases:
  #         name    code  MPV MPP  mstatus hstatus vsstatus symbol adjust                 mcause GVA mtval2 a1
  CASE_SYM(c_giga, g_lw, 1, MPP_S, 0, 0, 0, marker, 0xc0000000 - 0x80000000, 10,    ANY, ANY,   0x5a5a1234)
  CASE_SYM(c_mega, g_lw, 1, MPP_S, 0, 0, 0, marker, 0x80200000 - 0x80000000, 10,    ANY, ANY,   0x5a5a1234)
  CASE_SYM(c_kilo, g_lw, 1, MPP_S, 0, 0, 0, marker, 0, 10,    ANY, ANY,   0x5a5a1234)
  j     finish

g_lw:   lw    a1, 0(a0);  ecall

  .section .rodata
h_cases: .string "VS-mode loads of `marker` (PA 0x8000_0000 + OFF) with hgatp = Bare, vsatp = Sv39; a1 = loaded word:\n"
c_giga:  .string "  lw 0xc0000000+OFF, 1 GiB VS leaf      "
c_mega:  .string "  lw 0x80200000+OFF, 2 MiB VS leaf      "
c_kilo:  .string "  lw 0x80000000+OFF, 4 KiB (ctrl)       "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1c:  .fill 512, 8, 0
vt0c:  .fill 512, 8, 0
  .balign 4096
  .fill 0x234, 1, 0
marker: .word 0x5a5a1234
