# Reproducer: WFI in VU-mode and VS-mode for each value of mstatus.TW and hstatus.VTW, with nothing pending.
# Privileged spec, mstatus.TW (norm:mstatus_tw_op): "When TW=1, then if WFI is executed in any less-privileged
# mode, and it does not complete within an implementation-specific, bounded time limit, the WFI instruction causes
# an illegal-instruction exception."  Hypervisor extension, virtual-instruction exceptions are raised
# (norm:H_virtinst_vu_wfi_tw0) "in VU-mode, attempts to execute WFI when mstatus.TW=0" and
# (norm:H_virtinst_wfi_vtw1_tw0) "in VS-mode, attempts to execute WFI when hstatus.VTW=1 and mstatus.TW=0, unless
# the instruction completes within an implementation-specific, bounded time".  So with TW = 1 the only legal
# outcomes are completion or illegal instruction (cause 2), in VS-mode and VU-mode alike.
#
# Every trap goes to M-mode (medeleg = 0, all interrupt enables clear). Each case mrets to the guest at a WFI;
# the next instruction is an ecall (cause 10 from VS-mode, 8 from VU-mode), so a WFI that completes shows up as
# that ecall. Printed per case: mcause, and the causes allowed. Exit code = number of cases with a cause not allowed.

#define MSTATUS_TW    (1 << 21)
#define HSTATUS_VTW   (1 << 21)
#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, mtrap
  csrw  mtvec, t0
  csrw  medeleg, zero
  csrw  mideleg, zero
  csrw  hedeleg, zero
  csrw  hideleg, zero
  csrw  mie, zero
  csrw  hgatp, zero
  csrw  vsatp, zero
  li    s1, 0
  la    a0, h_cases; call puts

#define CASE(name, tw, vtw, mpp, ok1, ok2) \
  la    s4, 9f                  ;\
  li    s5, tw                  ;\
  li    s6, vtw                 ;\
  li    s7, mpp                 ;\
  li    s8, ok1                 ;\
  li    s9, ok2                 ;\
  la    s10, name               ;\
  j     run_case                ;\
9:

  # VU-mode (MPP = U): TW = 1 -> illegal (2) or completes (ecall 8); TW = 0 -> virtual (22)
  CASE(c_vu_tw1_vtw0, 1, 0, 0x0000, 2, 8)
  CASE(c_vu_tw1_vtw1, 1, 1, 0x0000, 2, 8)
  CASE(c_vu_tw0_vtw0, 0, 0, 0x0000, 22, 22)
  CASE(c_vu_tw0_vtw1, 0, 1, 0x0000, 22, 22)
  # VS-mode (MPP = S): TW = 1 -> illegal (2) or completes (ecall 10); TW = 0, VTW = 1 -> virtual (22) or completes
  CASE(c_vs_tw1_vtw0, 1, 0, 0x0800, 2, 10)
  CASE(c_vs_tw1_vtw1, 1, 1, 0x0800, 2, 10)
  CASE(c_vs_tw0_vtw1, 0, 1, 0x0800, 22, 10)

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

run_case:
  li    t0, MSTATUS_TW
  csrc  mstatus, t0
  beqz  s5, 1f
  csrs  mstatus, t0
1: li    t0, HSTATUS_VTW
  csrc  hstatus, t0
  beqz  s6, 1f
  csrs  hstatus, t0
1: li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  csrs  mstatus, s7
  li    t0, MSTATUS_MPV
  csrs  mstatus, t0
  la    t0, in_guest
  csrw  mepc, t0
  mret
in_guest:
  wfi
  ecall
mtrap:
  csrr  s2, mcause
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0              # back to M-mode
  la    t0, report
  csrw  mepc, t0
  mret
report:
  mv    a0, s10; call puts
  la    a0, s_cause; call puts
  mv    a0, s2; li a1, 2; call puthex
  la    a0, s_allowed; call puts
  mv    a0, s8; li a1, 2; call puthex
  la    a0, s_or; call puts
  mv    a0, s9; li a1, 2; call puthex
  la    a0, s_ok
  beq   s2, s8, 1f
  beq   s2, s9, 1f
  addi  s1, s1, 1
  la    a0, s_bad
1: call puts
  jr    s4

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
h_cases:       .string "WFI in the guest with nothing pending; mcause in hex (02 illegal, 16 virtual, 08/0a ecall = WFI completed):\n"
c_vu_tw1_vtw0: .string "  VU TW=1 VTW=0 "
c_vu_tw1_vtw1: .string "  VU TW=1 VTW=1 "
c_vu_tw0_vtw0: .string "  VU TW=0 VTW=0 "
c_vu_tw0_vtw1: .string "  VU TW=0 VTW=1 "
c_vs_tw1_vtw0: .string "  VS TW=1 VTW=0 "
c_vs_tw1_vtw1: .string "  VS TW=1 VTW=1 "
c_vs_tw0_vtw1: .string "  VS TW=0 VTW=1 "
s_cause:       .string " mcause="
s_allowed:     .string " allowed="
s_or:          .string " or "
s_ok:          .string "\n"
s_bad:         .string "   <-- not allowed\n"

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
