# Reproducer: the VS-stage permission checks follow the G-stage enable instead of the VS-stage enable.
# Privileged spec, Sv39 translation process (applied by the VS stage when vsatp is not Bare): "If pte.v = 0, or if
# pte.r = 0 and pte.w = 1 ... stop and raise a page-fault exception"; "Determine if the requested memory access is
# allowed by the pte.r, pte.w, pte.x, and pte.u bits ... If not, stop and raise a page-fault exception".
# Hypervisor spec (norm:H_vm_vsatp_bare): when vsatp.MODE = Bare, guest virtual addresses equal guest physical
# addresses and there is no VS-stage check; VU-mode, HLV with hstatus.SPVP = 0 and MPRV with MPP = U and MPV = 1 are
# then checked only by the G stage, as user-level accesses.
#
# Part 1, hgatp = Bare and vsatp = Sv39: VA 0xc000_n000 are 4 KiB VS-stage leaves on a scratch page; every access
# in VS-mode must raise a page fault except the read-write control.
# Part 2, vsatp = Bare and hgatp = Sv39x4 (GPA 0x8000_0000 1 GiB identity, U = 1, RWX): user-level loads of `marker`
# must succeed (a1 = 0x5a5a1234).
#include "mmu-harness.inc"
  .text
init:
  li    a0, 0x80000000
  MAP4K vt0c, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)               # image, 4 KiB VS leaves
  la    a0, vt0c
  SETPTE vt1c, 0, a0, PTE_V
  la    a0, vt1c
  SETPTE vroot, 2, a0, PTE_V
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  la    a0, page
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_R | PTE_V)                            # read-only
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_V)                            # execute-only
  SETPTE vt0, 3, a0, (PTE_D | PTE_A | PTE_W | PTE_R)                            # V = 0
  SETPTE vt0, 4, a0, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)            # U = 1 (vsstatus.SUM = 0)
  SETPTE vt0, 5, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)                    # read-write (control)
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  csrw  hgatp, zero
  SETATP vsatp, vroot
  ret

part2:
  mv    s3, ra
  csrw  vsatp, zero
  SETATP hgatp, groot
  hfence.gvma
  hfence.vvma
  la    a0, h_part2; call puts
  mv    ra, s3
  ret

cases:
  #     name      code   MPV MPP    mstatus                   hstatus vsstatus address     mcause GVA mtval2 a1
  CASE(c_sw_r,  g_sw,  1, MPP_S, 0,                        0,      0,       0xc0001000, 15,    ANY, ANY,  ANY)
  CASE(c_lw_x,  g_lw,  1, MPP_S, 0,                        0,      0,       0xc0002000, 13,    ANY, ANY,  ANY)
  CASE(c_lw_v0, g_lw,  1, MPP_S, 0,                        0,      0,       0xc0003000, 13,    ANY, ANY,  ANY)
  CASE(c_lw_u,  g_lw,  1, MPP_S, 0,                        0,      0,       0xc0004000, 13,    ANY, ANY,  ANY)
  CASE(c_lw_rw, g_lw,  1, MPP_S, 0,                        0,      0,       0xc0005000, 10,    ANY, ANY,  0)
  call  part2
  #         name      code   MPV MPP    mstatus        hstatus vsstatus symbol adjust mcause GVA mtval2 a1
  CASE_SYM(c_vu,    g_lw,  1, MPP_U, 0,             0,      0,       marker, 0,     8,     ANY, ANY,  0x5a5a1234)
  CASE_SYM(c_hlv,   g_hlv, 0, MPP_S, 0,             0,      0,       marker, 0,     9,     ANY, ANY,  0x5a5a1234)
  CASE_SYM(c_mprv,  g_mprv, 0, MPP_M, 0,             0,      0,       marker, 0,     11,    ANY, ANY,  0x5a5a1234)
  CASE_SYM(c_vs,    g_lw,  1, MPP_S, 0,             0,      0,       marker, 0,     10,    ANY, ANY,  0x5a5a1234)
  j     finish

# c_mprv runs in M-mode with MPRV = 1, MPP = U, MPV = 1: set them here, after mret, so that MPP and MPV survive it
g_mprv: li t0, MSTATUS_MPP; csrc mstatus, t0
        li t0, MSTATUS_MPV | MSTATUS_MPRV; csrs mstatus, t0
        lw a1, 0(a0); ecall
g_lw:   lw    a1, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_hlv:  hlv.w a1, (a0);   ecall

  .section .rodata
h_cases: .string "Part 1, hgatp = Bare, vsatp = Sv39; VS-mode accesses through 4 KiB VS-stage leaves:\n"
h_part2: .string "Part 2, vsatp = Bare, hgatp = Sv39x4 (U = 1, RWX); user-level loads of `marker`:\n"
c_sw_r:  .string "  VS sw 0xc0001000, leaf R only        "
c_lw_x:  .string "  VS lw 0xc0002000, leaf X only        "
c_lw_v0: .string "  VS lw 0xc0003000, leaf V = 0         "
c_lw_u:  .string "  VS lw 0xc0004000, leaf U = 1, SUM=0  "
c_lw_rw: .string "  VS lw 0xc0005000, leaf RW (ctrl)     "
c_vu:    .string "  VU lw marker                         "
c_hlv:   .string "  HS hlv.w marker, SPVP = 0            "
c_mprv:  .string "  M lw marker, MPRV=1 MPP=U MPV=1      "
c_vs:    .string "  VS lw marker (ctrl)                  "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
vroot: .fill 512, 8, 0
vt1:   .fill 512, 8, 0
vt0:   .fill 512, 8, 0
vt1c:  .fill 512, 8, 0
vt0c:  .fill 512, 8, 0
page:  .fill 512, 8, 0
marker: .word 0x5a5a1234
