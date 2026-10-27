# Reproducer: VS-mode and VU-mode instructions that are illegal in HS-mode too raise a virtual-instruction exception.
# Hypervisor extension (norm:H_virtinst): a virtual-instruction exception is raised for an instruction that is
# "valid and not prevented from executing in HS-mode" but not allowed in VS-mode or VU-mode. An instruction that HS-mode
# could not execute either (an access to an unimplemented CSR, a write to a read-only CSR, MRET) raises illegal
# instruction (cause 2). The two controls access implemented CSRs that HS-mode may access, so they must give cause 22.
#include "harness.inc"
  .text
cases:
  #         name      guest code  MPV MPP    mstatus hstatus hcounteren mcause GVA
  CASE(c_vu_101,  g_csr101,   1, MPP_U, 0, 0, -1, 2,  NO_GVA_CHECK)   # unimplemented S-level CSR 0x101
  CASE(c_vu_901,  g_csr901,   1, MPP_U, 0, 0, -1, 2,  NO_GVA_CHECK)   # unimplemented S-level CSR 0x901
  CASE(c_vs_hgeip, g_hgeip,   1, MPP_S, 0, 0, -1, 2,  NO_GVA_CHECK)   # write to read-only hgeip
  CASE(c_vs_mret, g_mret,     1, MPP_S, 0, 0, -1, 2,  NO_GVA_CHECK)   # MRET
  CASE(c_vs_cycle, g_cyclew,  1, MPP_S, 0, 0,  0, 2,  NO_GVA_CHECK)   # write to read-only cycle, hcounteren = 0
  CASE(c_vs_hstatus, g_hstatus, 1, MPP_S, 0, 0, -1, 22, NO_GVA_CHECK) # control: implemented H CSR
  CASE(c_vu_sstatus, g_sstatus, 1, MPP_U, 0, 0, -1, 22, NO_GVA_CHECK) # control: implemented S CSR
  j     finish

g_csr101:  csrr  t0, 0x101;  ecall
g_csr901:  csrr  t0, 0x901;  ecall
g_hgeip:   csrw  hgeip, zero; ecall
g_mret:    mret;             ecall
g_cyclew:  csrw  cycle, zero; ecall
g_hstatus: csrr  t0, hstatus; ecall
g_sstatus: csrr  t0, sstatus; ecall

  .section .rodata
h_cases:     .string "Guest instructions that HS-mode cannot execute either; mcause in hex (02 illegal, 16 virtual):\n"
c_vu_101:    .string "  VU csrr 0x101           "
c_vu_901:    .string "  VU csrr 0x901           "
c_vs_hgeip:  .string "  VS csrw hgeip           "
c_vs_mret:   .string "  VS mret                 "
c_vs_cycle:  .string "  VS csrw cycle (hcen=0)  "
c_vs_hstatus:.string "  VS csrr hstatus (ctrl)  "
c_vu_sstatus:.string "  VU csrr sstatus (ctrl)  "
