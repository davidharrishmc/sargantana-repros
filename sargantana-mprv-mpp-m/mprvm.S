# Reproducer: M-mode load or store with mstatus.MPRV = 1, MPP = M and MPV = 1.
# Hypervisor spec (norm:mstatus_mprv_hypervisor and the table after it): with MPRV = 1 and MPP = 3 the access is an
# "M-level access with no translation", whatever MPV holds; MPV only matters when MPP is S or U.
#
# vsatp = Bare; hgatp = Sv39x4 with an empty root table, so any access translated by the G stage takes a guest-page
# fault. Each case runs in M-mode, sets MPRV, MPP and MPV itself, accesses `marker` and executes ecall.
#include "mmu-harness.inc"
  .text
init:
  csrw  vsatp, zero
  SETATP hgatp, groot                                                             # empty G-stage root
  ret

cases:
  #         name      code      MPV MPP    mstatus hstatus vsstatus symbol adjust mcause GVA mtval2 a1
  CASE_SYM(c_m_lw,  g_lw_m1,  0, MPP_M, 0,      0,      0,       marker, 0,     11,    ANY, ANY,   0x5a5a1234)
  CASE_SYM(c_m_sw,  g_sw_m1,  0, MPP_M, 0,      0,      0,       marker, 0,     11,    ANY, ANY,   ANY)
  CASE_SYM(c_m0_lw, g_lw_m0,  0, MPP_M, 0,      0,      0,       marker, 0,     11,    ANY, ANY,   0x5a5a1234)
  CASE_SYM(c_s_lw,  g_lw_s1,  0, MPP_M, 0,      0,      0,       marker, 0,     21,    1,   ANY,   ANY)
  j     finish

# Each sets MPP and MPV after the harness's mret (which consumes MPP), then MPRV, and accesses a0.
g_lw_m1: li t0, MSTATUS_MPP | MSTATUS_MPV; csrs mstatus, t0          # MPP = M, MPV = 1
         li t0, MSTATUS_MPRV; csrs mstatus, t0
         lw a1, 0(a0); ecall
g_sw_m1: li t0, MSTATUS_MPP | MSTATUS_MPV; csrs mstatus, t0
         li t0, MSTATUS_MPRV; csrs mstatus, t0
         sw zero, 4(a0); ecall
g_lw_m0: li t0, MSTATUS_MPP; csrs mstatus, t0                        # MPP = M, MPV = 0
         li t0, MSTATUS_MPV; csrc mstatus, t0
         li t0, MSTATUS_MPRV; csrs mstatus, t0
         lw a1, 0(a0); ecall
g_lw_s1: li t0, MSTATUS_MPP; csrc mstatus, t0
         li t0, MPP_S | MSTATUS_MPV; csrs mstatus, t0                # MPP = S, MPV = 1: VS-level, two-stage
         li t0, MSTATUS_MPRV; csrs mstatus, t0
         lw a1, 0(a0); ecall

  .section .rodata
h_cases: .string "M-mode accesses to `marker` with MPRV = 1 (vsatp = Bare, hgatp = Sv39x4 with nothing mapped):\n"
c_m_lw:  .string "  lw, MPP = M, MPV = 1                 "
c_m_sw:  .string "  sw, MPP = M, MPV = 1                 "
c_m0_lw: .string "  lw, MPP = M, MPV = 0 (ctrl)          "
c_s_lw:  .string "  lw, MPP = S, MPV = 1 (ctrl)          "

  .section .data
  .balign 16384
groot: .fill 2048, 8, 0
marker: .word 0x5a5a1234
  .word 0
