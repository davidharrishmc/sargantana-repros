# Reproducer: vsstatus.SD must read 1 whenever vsstatus.VS (or FS, XS) is Dirty.
# Hypervisor extension (norm:vsstatus_sd_op_vs): "If vsstatus.VS is Dirty, vsstatus.SD is 1;
# otherwise, vsstatus.SD is set in accordance with existing specifications."
#
# Cases A-D write vsstatus from M-mode, wait 32 nops and read it back.  Case E enters VS-mode
# with vsstatus.VS = Initial, executes vadd.vv (which must set vsstatus.VS and mstatus.VS to
# Dirty), waits, reads sstatus (= vsstatus in VS-mode), and ecalls back to M-mode.
# Printed: VS, FS and SD of the value read.  Exit code = number of cases where SD is wrong.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800
#define MSTATUS_MPP_S 0x0800
#define SD_BIT        63

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, mtrap
  csrw  mtvec, t0
  li    t0, 0x6600                   # mstatus.FS = VS = Dirty
  csrs  mstatus, t0
  csrw  hgatp, zero                  # G-stage Bare
  csrw  vsatp, zero                  # VS-stage Bare
  csrw  medeleg, zero                # every trap from VS goes to M
  csrw  hedeleg, zero
  li    s1, 0

#define CASE(name, value, expsd)      \
  li    t0, value                    ;\
  csrw  vsstatus, t0                 ;\
  .rept 32; nop; .endr               ;\
  csrr  a1, vsstatus                 ;\
  la    a0, name                     ;\
  li    a2, expsd                    ;\
  call  report                       ;\
  add   s1, s1, a0

  la a0, h_m; call puts
  CASE(c_vs3, 0x600, 1)              # VS = Dirty, FS = Off
  CASE(c_fs3, 0x6000, 1)             # FS = Dirty, VS = Off
  CASE(c_both, 0x6600, 1)            # FS = VS = Dirty
  CASE(c_vs1, 0x200, 0)              # VS = Initial, FS = Off

  # Case E: vadd.vv in VS-mode with vsstatus.VS = Initial
  la a0, h_v; call puts
  li    t0, 0x200                    # vsstatus: VS = Initial, FS = Off
  csrw  vsstatus, t0
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP_S | 0        # MPP = S
  csrs  mstatus, t0
  li    t0, 1
  slli  t0, t0, 39                   # MPV = 1
  csrs  mstatus, t0
  la    t0, in_vs
  csrw  mepc, t0
  mret
in_vs:
  vsetivli zero, 4, e32, m1, ta, ma
  vadd.vv v1, v2, v3
  .rept 32; nop; .endr
  csrr  a1, sstatus                  # reads vsstatus in VS-mode
  ecall                              # back to M-mode (mtrap)
after_vs:
  la    a0, c_vadd
  li    a2, 1
  call  report
  add   s1, s1, a0
  csrr  a1, vsstatus                 # the same register read from M-mode
  la    a0, c_vadd_m
  li    a2, 1
  call  report
  add   s1, s1, a0

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# M-mode trap handler: only the ecall from VS-mode is expected; continue at after_vs in M-mode
mtrap:
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0                  # MPP = M
  la    t0, after_vs
  csrw  mepc, t0
  mret

# report(a0 = name, a1 = status value, a2 = expected SD); returns a0 = 1 if SD is wrong
report:
  addi  sp, sp, -32
  sd    ra, 0(sp); sd s4, 8(sp); sd s5, 16(sp); sd s6, 24(sp)
  mv    s4, a1; mv s5, a2
  call  puts
  la    a0, s_vs; call puts
  srli  a0, s4, 9;  andi a0, a0, 3; li a1, 1; call puthex
  la    a0, s_fs; call puts
  srli  a0, s4, 13; andi a0, a0, 3; li a1, 1; call puthex
  la    a0, s_sd; call puts
  srli  a0, s4, 63; li a1, 1; call puthex
  srli  t0, s4, 63
  xor   s6, t0, s5                   # 1 if SD != expected
  la    a0, s_ok
  beqz  s6, 1f
  la    a0, s_bad
1: call puts
  mv    a0, s6
  ld    ra, 0(sp); ld s4, 8(sp); ld s5, 16(sp); ld s6, 24(sp)
  addi  sp, sp, 32
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
h_m:      .string "csrw vsstatus from M-mode, then csrr vsstatus:\n"
h_v:      .string "\nvadd.vv in VS-mode with vsstatus.VS = Initial:\n"
c_vs3:    .string "  write VS=3 FS=0           "
c_fs3:    .string "  write VS=0 FS=3           "
c_both:   .string "  write VS=3 FS=3           "
c_vs1:    .string "  write VS=1 FS=0           "
c_vadd:   .string "  csrr sstatus in VS-mode   "
c_vadd_m: .string "  csrr vsstatus in M-mode   "
s_vs:     .string "VS="
s_fs:     .string " FS="
s_sd:     .string " SD="
s_ok:     .string "\n"
s_bad:    .string "   <-- SD wrong\n"

  .section .data
  .balign 8
outlen:   .dword 0
fpdata:   .dword 0x3FF0000000000000
  .balign 16
  .space 4096
stack_top:

  .section .tohost, "aw", @progbits
  .balign 64; .globl tohost;   tohost:   .dword 0
  .balign 64; .globl fromhost; fromhost: .dword 0
  .balign 64; htif_magicmem: .dword 0,0,0,0,0,0,0,0
  .balign 64; htif_iobuf: .fill 8192,1,0
