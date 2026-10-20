# Reproducer: an interrupt taken into HS-mode from VS-mode or VU-mode must write hstatus.GVA = 0.
# Hypervisor extension, hstatus: "Field GVA (Guest Virtual Address) is written by the implementation
# whenever a trap is taken into HS-mode. For any trap (breakpoint, address misaligned, access fault,
# page fault, or guest-page fault) that writes a guest virtual address to stval, GVA is set to 1.
# For any other trap into HS-mode, GVA is set to 0."
#
# mideleg.SSI = 1 and sie.SSIE = 1, so a pending supervisor software interrupt is taken into HS-mode
# whenever V = 1.  Cases A and B set mip.SSIP from M-mode and mret into VS-mode or VU-mode, where
# the interrupt is taken at once.  Case C ecalls from VS-mode (medeleg delegates it to HS-mode).
# Case D is case A with a VS-level software interrupt (hvip.VSSIP, hie.VSSIE = 1, hideleg = 0).
# The HS-mode handler records scause and hstatus, then ecalls to M-mode, which runs the next case.
# Printed: scause, and GVA, SPV and SPVP of hstatus.  Exit code = number of cases with GVA = 1.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800
#define MIP_SSIP      (1 << 1)
#define MIP_VSSIP     (1 << 2)
#define CAUSE_VS_ECALL 10
#define CAUSE_S_ECALL  9

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, mtrap
  csrw  mtvec, t0
  la    t0, strap
  csrw  stvec, t0
  csrw  hgatp, zero                  # G-stage Bare
  csrw  vsatp, zero                  # VS-stage Bare
  li    t0, (1 << CAUSE_VS_ECALL)
  csrw  medeleg, t0                  # ecall from VS-mode goes to HS-mode
  csrw  hedeleg, zero
  csrw  hideleg, zero                # VS-level interrupts are taken in HS-mode
  csrw  hvip, zero
  li    t0, MIP_SSIP
  csrw  mideleg, t0                  # SSI is taken in HS-mode
  csrw  sie, t0                      # sie.SSIE = 1
  li    t0, MIP_VSSIP
  csrw  hie, t0                      # hie.VSSIE = 1
  li    s1, 0

  la a0, h_int; call puts
  # Case A: SSI pending on entry to VS-mode
  la    s4, after_a
  li    t0, MIP_SSIP
  csrs  mip, t0
  li    a0, 0x0800                   # MPP = S
  la    a1, in_guest
  j     enter_guest
after_a:
  la    a0, c_vs; call report

  # Case B: SSI pending on entry to VU-mode
  la    s4, after_b
  li    t0, MIP_SSIP
  csrs  mip, t0
  li    a0, 0x0000                   # MPP = U
  la    a1, in_guest
  j     enter_guest
after_b:
  la    a0, c_vu; call report

  la a0, h_exc; call puts
  # Case C: ecall from VS-mode, nothing pending
  la    s4, after_c
  li    a0, 0x0800                   # MPP = S
  la    a1, in_guest_ecall
  j     enter_guest
after_c:
  la    a0, c_ecall; call report

  la a0, h_vssi; call puts
  # Case D: VSSI pending on entry to VS-mode
  la    s4, after_d
  li    t0, MIP_VSSIP
  csrs  hvip, t0
  li    a0, 0x0800                   # MPP = S
  la    a1, in_guest
  j     enter_guest
after_d:
  la    a0, c_vs; call report

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# enter_guest(a0 = MPP value, a1 = guest entry): mret into VS/VU-mode with MPV = 1
enter_guest:
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  csrs  mstatus, a0
  li    t0, MSTATUS_MPV
  csrs  mstatus, t0
  csrw  mepc, a1
  mret

in_guest:                            # the interrupt is taken here
  .rept 8; nop; .endr
  j     in_guest
in_guest_ecall:
  ecall

# HS-mode handler: record scause and hstatus, clear the interrupt, return to M-mode by ecall
strap:
  csrr  s2, scause
  csrr  s3, hstatus
  li    t0, MIP_VSSIP
  csrc  hvip, t0
  li    t0, MIP_SSIP
  csrc  sip, t0
  ecall

# M-mode handler: an ecall from HS-mode continues with the next case at s4 in M-mode
mtrap:
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0                  # MPP = M
  csrw  mepc, s4
  mret

# report(a0 = name): print scause (s2) and hstatus GVA/SPV/SPVP (s3); count GVA = 1 in s1
report:
  addi  sp, sp, -16
  sd    ra, 0(sp)
  call  puts
  la    a0, s_cause; call puts
  mv    a0, s2; li a1, 16; call puthex
  la    a0, s_gva; call puts
  srli  a0, s3, 6; andi a0, a0, 1; li a1, 1; call puthex
  la    a0, s_spv; call puts
  srli  a0, s3, 7; andi a0, a0, 1; li a1, 1; call puthex
  la    a0, s_spvp; call puts
  srli  a0, s3, 8; andi a0, a0, 1; li a1, 1; call puthex
  srli  t0, s3, 6; andi t0, t0, 1
  add   s1, s1, t0
  la    a0, s_ok
  beqz  t0, 1f
  la    a0, s_bad
1: call puts
  ld    ra, 0(sp)
  addi  sp, sp, 16
  ret

# puts(a0 = string): append to outbuf
puts:
  la    t1, outlen; ld t2, 0(t1)
  la    t3, htif_iobuf; add t3, t3, t2
1: lbu  t0, 0(a0)
  beqz  t0, 2f
  sb    t0, 0(t3)
  addi  a0, a0, 1; addi t3, t3, 1; addi t2, t2, 1
  j     1b
2: sd   t2, 0(t1)
  ret

# puthex(a0 = value, a1 = digits)
puthex:
  la    t1, outlen; ld t2, 0(t1)
  la    t3, htif_iobuf; add t3, t3, t2
  slli  t4, a1, 2
1: addi t4, t4, -4
  srl   t0, a0, t4; andi t0, t0, 15
  addi  t5, t0, '0'
  li    t6, 10
  blt   t0, t6, 2f
  addi  t5, t0, 'a'-10
2: sb   t5, 0(t3)
  addi  t3, t3, 1; addi t2, t2, 1
  bnez  t4, 1b
  sd    t2, 0(t1)
  ret

# flush: one HTIF SYS_write of outbuf (the tile reads the buffer with word-aligned
# DPI reads and needs the stores drained before tohost is seen)
flush:
  la    t1, htif_magicmem
  li    t0, 64;  sd t0, 0(t1)         # SYS_write
  li    t0, 1;   sd t0, 8(t1)         # stdout
  la    t0, htif_iobuf; sd t0, 16(t1)
  la    t0, outlen; ld t0, 0(t0); sd t0, 24(t1)
  fence
  li    t0, 100
1: addi t0, t0, -1
  bnez  t0, 1b
  la    t0, tohost
  sd    t1, 0(t0)
  li    t0, 50000                     # let the host see the console syscall before the exit write
1: addi t0, t0, -1
  bnez  t0, 1b
  ret

  .section .rodata
h_int:    .string "Supervisor software interrupt (mip.SSIP, mideleg.SSI = 1) taken into HS-mode:\n"
h_vssi:   .string "\nVS-level software interrupt (hvip.VSSIP, hideleg = 0) taken into HS-mode:\n"
h_exc:    .string "\nException taken into HS-mode:\n"
c_vs:     .string "  from VS-mode   "
c_vu:     .string "  from VU-mode   "
c_ecall:  .string "  ecall from VS  "
s_cause:  .string "scause="
s_gva:    .string " GVA="
s_spv:    .string " SPV="
s_spvp:   .string " SPVP="
s_ok:     .string "\n"
s_bad:    .string "   <-- GVA must be 0\n"

  .section .data
  .balign 8
outlen:   .dword 0
  .balign 16
  .space 4096
stack_top:

  .section .tohost, "aw", @progbits
  .balign 64; .globl tohost;   tohost:   .dword 0
  .balign 64; .globl fromhost; fromhost: .dword 0
  .balign 64; htif_magicmem: .dword 0,0,0,0,0,0,0,0
  .balign 64; htif_iobuf: .fill 8192,1,0
