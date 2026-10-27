# Shared harness for the Sargantana reproducers. Every trap goes to M-mode (medeleg = mideleg = 0, all interrupt
# enables clear). Each CASE sets mstatus and hstatus bits and hcounteren from M-mode, then mrets to the case's guest
# code in the requested mode (hgatp = vsatp = Bare). The guest code runs one instruction and then an ecall, so a
# guest instruction that does not trap shows up as the ecall (cause 8 from VU-mode, 10 from VS-mode, 9 from HS-mode).
# The M-mode handler records mcause and mstatus.GVA. Printed per case: mcause, GVA and the expected values.
# Exit code = number of cases that differ from the expected values.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_GVA   (1 << 38)
#define MSTATUS_MPP   0x1800
#define MPP_U         0x0000
#define MPP_S         0x0800
#define NO_GVA_CHECK  2

# CASE(label string, guest code, MPV, MPP, mstatus bits to set, hstatus bits to set, hcounteren, mcause, GVA)
#define CASE(name, code, mpv, mpp, mbits, hbits, hcen, cause, gva) \
  la    s4, 9f                  ;\
  la    s3, code                ;\
  li    s5, mbits               ;\
  li    s6, hbits               ;\
  li    s7, mpp                 ;\
  li    s0, mpv                 ;\
  li    s11, hcen               ;\
  li    s8, cause               ;\
  li    s9, gva                 ;\
  la    s10, name               ;\
  j     run_case                ;\
9:

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
  li    t0, -1
  csrw  mcounteren, t0
  csrw  scounteren, t0
  li    s1, 0
  la    a0, h_cases; call puts
  j     cases

finish:
  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

run_case:
  csrw  hcounteren, s11
  csrs  mstatus, s5
  csrs  hstatus, s6
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  csrs  mstatus, s7
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  beqz  s0, 1f
  csrs  mstatus, t0
1: csrw  mepc, s3
  mret
mtrap:
  csrr  s2, mcause
  csrr  t0, mstatus
  srli  t0, t0, 38
  andi  s3, t0, 1                # GVA
  csrc  mstatus, s5              # undo the case's control bits
  csrc  hstatus, s6
  li    t0, -1
  csrw  hcounteren, t0
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
  la    a0, s_gva; call puts
  mv    a0, s3; li a1, 1; call puthex
  la    a0, s_expected; call puts
  mv    a0, s8; li a1, 2; call puthex
  li    t0, NO_GVA_CHECK
  beq   s9, t0, 1f
  la    a0, s_gva; call puts
  mv    a0, s9; li a1, 1; call puthex
1: la    a0, s_ok
  bne   s2, s8, 2f
  li    t0, NO_GVA_CHECK
  beq   s9, t0, 3f
  beq   s3, s9, 3f
2: addi  s1, s1, 1
  la    a0, s_bad
3: call puts
  jr    s4

# puts(a0 = string): append to the HTIF console buffer
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

# flush: one HTIF SYS_write of the console buffer (the tile reads the buffer with word-aligned DPI reads and needs
# the stores drained before tohost is seen)
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
s_cause:    .string " mcause="
s_gva:      .string " GVA="
s_expected: .string "   expected mcause="
s_ok:       .string "\n"
s_bad:      .string "   <-- wrong\n"

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
