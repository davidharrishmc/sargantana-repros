# Reproducer: mstatus.GVA (and hstatus.GVA) on exceptions taken from VS-mode.
# Hypervisor extension (norm:mstatus_gva_op, norm:hstatus_gva_op): GVA is set to 1 when a trap writes a guest virtual
# address to mtval/stval, and to 0 otherwise. A breakpoint writes the faulting PC and a misaligned jump writes the
# target, both guest virtual addresses, so GVA = 1. A virtual-instruction exception writes the instruction bits, so
# GVA = 0. The misaligned JALR and the ecall are controls.
#include "harness.inc"
  .text
cases:
  #         name        guest code  MPV MPP    mstatus hstatus hcen mcause GVA
  CASE(c_ebreak,     g_ebreak,  1, MPP_S, 0, 0, -1, 3,  1)
  CASE(c_jal,        g_jal,     1, MPP_S, 0, 0, -1, 0,  1)
  CASE(c_hlv,        g_hlv,     1, MPP_S, 0, 0, -1, 22, 0)
  CASE(c_jalr,       g_jalr,    1, MPP_S, 0, 0, -1, 0,  1)
  CASE(c_ecall,      g_ecall,   1, MPP_S, 0, 0, -1, 10, 0)
  j     finish

g_ebreak: ebreak; ecall
  .option push
  .option norvc
g_jal:    .word 0x0060006f       # jal x0, .+6: misaligned target (no C extension)
          ecall
  .option pop
g_hlv:    la t1, scratch; hlv.w t0, (t1); ecall
g_jalr:   la t1, g_jalr; addi t1, t1, 2; jalr x0, 0(t1)
g_ecall:  ecall

  .section .rodata
h_cases:  .string "Exceptions from VS-mode trapped in M-mode; mcause in hex and mstatus.GVA:\n"
c_ebreak: .string "  ebreak               "
c_jal:    .string "  jal to pc+6          "
c_hlv:    .string "  hlv.w (virtual)      "
c_jalr:   .string "  jalr to pc+2 (ctrl)  "
c_ecall:  .string "  ecall (ctrl)         "
  .section .data
  .balign 8
scratch: .dword 0
