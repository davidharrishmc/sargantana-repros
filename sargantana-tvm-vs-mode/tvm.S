# Reproducer: mstatus.TVM = 1 makes SFENCE.VMA trap in VS-mode.
# Hypervisor extension (norm:mstatus_tsr_tvm_hs_only): "The TSR and TVM fields of mstatus affect execution only in
# HS-mode, not directly in VS or VU-mode." In VS-mode SFENCE.VMA and satp accesses are controlled by hstatus.VTVM:
# with VTVM = 0 they complete (the ecall that follows gives cause 10). The controls check that mstatus.TVM does trap
# SFENCE.VMA in HS-mode (illegal, 2) and that hstatus.VTVM traps it in VS-mode (virtual, 22).
#define MSTATUS_TVM (1 << 20)
#define HSTATUS_VTVM (1 << 20)
#include "harness.inc"
  .text
cases:
  #         name        guest code MPV MPP    mstatus      hstatus       hcen mcause GVA
  CASE(c_vs_sfence,  g_sfence, 1, MPP_S, MSTATUS_TVM, 0,            -1, 10, NO_GVA_CHECK)
  CASE(c_vs_satp,    g_satp,   1, MPP_S, MSTATUS_TVM, 0,            -1, 10, NO_GVA_CHECK)
  CASE(c_vs_vtvm,    g_sfence, 1, MPP_S, 0,           HSTATUS_VTVM, -1, 22, NO_GVA_CHECK)
  CASE(c_hs_tvm,     g_sfence, 0, MPP_S, MSTATUS_TVM, 0,            -1, 2,  NO_GVA_CHECK)
  j     finish

g_sfence: sfence.vma; ecall
g_satp:   csrr t0, satp; ecall

  .section .rodata
h_cases:     .string "SFENCE.VMA and satp with mstatus.TVM and hstatus.VTVM; mcause in hex (0a = completed, 02 illegal, 16 virtual):\n"
c_vs_sfence: .string "  VS TVM=1 VTVM=0 sfence.vma "
c_vs_satp:   .string "  VS TVM=1 VTVM=0 csrr satp  "
c_vs_vtvm:   .string "  VS TVM=0 VTVM=1 sfence.vma "
c_hs_tvm:    .string "  HS TVM=1         sfence.vma"
