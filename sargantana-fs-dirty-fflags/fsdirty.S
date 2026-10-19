# Reproducer: an FP instruction with an integer result that raises an exception flag
# must set mstatus.FS to Dirty, because it modifies fcsr.fflags (Privileged spec,
# mstatus.FS: "FS=Dirty ... the state has potentially been modified"; fflags is part
# of the FS-tracked state).
#
# For each case: clear fflags, set mstatus.FS = Initial (01), execute one instruction,
# wait 32 nops (so a one-cycle SD lag cannot matter), then print mstatus.FS, mstatus.SD
# and fflags on the HTIF console.  Exit code = number of cases whose FS is not Dirty
# although the instruction raised a flag or wrote an FP register.

#define MSTATUS_FS       0x6000
#define MSTATUS_FS_INIT  0x2000

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  li    t0, MSTATUS_FS               # FS = Dirty so the f registers can be loaded
  csrs  mstatus, t0
  li    t0, 0x3F800000               # 1.0
  fmv.w.x f1, t0
  li    t0, 0x40400000               # 3.0
  fmv.w.x f2, t0
  li    t0, 0x7FA00000               # signaling NaN
  fmv.w.x f4, t0
  li    t0, 0x3FC00000               # 1.5
  fmv.w.x f5, t0
  li    t0, 0xBF800000               # -1.0
  fmv.w.x f6, t0
  li    t0, 0x7FF4000000000000       # signaling NaN (double)
  fmv.d.x f7, t0
  li    t0, 0x600                    # VS = Dirty for the vector cases
  csrs  mstatus, t0
  vsetivli zero, 4, e32, m1, ta, ma
  li    t0, 0x7FA00000
  vmv.v.x v1, t0                     # v1 = signaling NaNs
  li    t0, 0x3FC00000
  vmv.v.x v2, t0                     # v2 = 1.5
  la    a4, fpdata
  csrwi frm, 0                       # RNE
  li    s1, 0                        # violation count

#define CASE(name, mustdirty, ...)    \
  csrwi fflags, 0                    ;\
  li    t0, MSTATUS_FS               ;\
  csrc  mstatus, t0                  ;\
  li    t0, MSTATUS_FS_INIT          ;\
  csrs  mstatus, t0                  ;\
  __VA_ARGS__                        ;\
  .rept 32; nop; .endr               ;\
  csrr  s2, mstatus                  ;\
  csrr  s3, fflags                   ;\
  la    a0, name                     ;\
  mv    a1, s2                       ;\
  mv    a2, s3                       ;\
  li    a3, mustdirty                ;\
  call  report                       ;\
  add   s1, s1, a0

  la a0, h0; call puts
  CASE(c1, 1, fadd.s f0, f1, f2)
  CASE(c2, 1, fmadd.s f0, f1, f2, f1)
  CASE(c3, 1, fdiv.s f0, f2, f1)
  CASE(c4, 1, fsqrt.s f0, f1)
  CASE(c5, 1, fsgnj.s f0, f1, f2)
  CASE(c6, 1, fmin.s f0, f1, f2)
  CASE(c7, 1, flw f0, 0(a4))
  CASE(c8, 1, fld f0, 0(a4))
  CASE(c9, 1, fmv.w.x f0, x0)
  CASE(c10, 1, fmv.d.x f0, x0)
  CASE(c11, 1, fcvt.s.w f0, x0)
  CASE(c12, 1, fcvt.d.s f0, f1)
  CASE(c13, 1, fli.s f0, 1.0)
  CASE(c14, 1, vfmv.f.s f0, v2)
  la a0, h15; call puts
  CASE(c16, 1, feq.s x8, f4, f4)
  CASE(c17, 1, flt.s x8, f4, f4)
  CASE(c18, 1, fle.d x8, f7, f7)
  CASE(c19, 1, fcvt.w.s x8, f5)
  CASE(c20, 1, fcvt.wu.s x8, f6)
  CASE(c21, 1, fcvt.l.d x8, f7)
  CASE(c22, 1, vfadd.vv v3, v1, v1)
  CASE(c23, 1, vmfeq.vv v3, v1, v1)
  CASE(c24, 1, vfcvt.x.f.v v3, v2)
  CASE(c25, 1, vfredusum.vs v3, v1, v1)
  la a0, h26; call puts
  CASE(c27, 1, csrw fflags, x0)
  CASE(c28, 1, fsrmi 1)
  CASE(c29, 1, csrw fcsr, x0)
  la a0, h30; call puts
  CASE(c31, 0, feq.s x8, f1, f1)
  CASE(c32, 0, fclass.s x8, f4)
  CASE(c33, 0, fmv.x.w x8, f1)
  call  flush
  slli  t0, s1, 1                    # tohost = (exit code << 1) | 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# report(a0 = name, a1 = mstatus, a2 = fflags, a3 = must be Dirty)
# appends one line; returns a0 = 1 if FS is not Dirty but must be
report:
  addi  sp, sp, -48
  sd    ra, 0(sp); sd s4, 8(sp); sd s5, 16(sp); sd s6, 24(sp); sd s7, 32(sp)
  mv    s4, a1; mv s5, a2; mv s6, a3
  call  puts
  la    a0, s_fs;   call puts
  srli  a0, s4, 13; andi a0, a0, 3; li a1, 1; call puthex
  la    a0, s_sd;   call puts
  srli  a0, s4, 63; li a1, 1; call puthex
  la    a0, s_ff;   call puts
  mv    a0, s5; li a1, 2; call puthex
  srli  t0, s4, 13; andi t0, t0, 3; addi t0, t0, -3
  snez  t0, t0                       # 1 if FS != Dirty
  and   s7, t0, s6
  la    a0, s_ok
  beqz  s7, 1f
  la    a0, s_bad
1: call puts
  mv    a0, s7
  ld    ra, 0(sp); ld s4, 8(sp); ld s5, 16(sp); ld s6, 24(sp); ld s7, 32(sp)
  addi  sp, sp, 48
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
h0: .string "\nFP-register writes:\n"
c1: .string "  fadd.s f0, f1, f2       (writes f0)        "
c2: .string "  fmadd.s f0, f1, f2, f1  (writes f0)        "
c3: .string "  fdiv.s f0, f2, f1       (writes f0)        "
c4: .string "  fsqrt.s f0, f1          (writes f0)        "
c5: .string "  fsgnj.s f0, f1, f2      (writes f0)        "
c6: .string "  fmin.s f0, f1, f2       (writes f0)        "
c7: .string "  flw f0, 0(a4)           (writes f0)        "
c8: .string "  fld f0, 0(a4)           (writes f0)        "
c9: .string "  fmv.w.x f0, x0          (writes f0)        "
c10: .string "  fmv.d.x f0, x0          (writes f0)        "
c11: .string "  fcvt.s.w f0, x0         (writes f0)        "
c12: .string "  fcvt.d.s f0, f1         (writes f0)        "
c13: .string "  fli.s f0, 1.0           (Zfa, writes f0)   "
c14: .string "  vfmv.f.s f0, v2         (writes f0)        "
h15: .string "\nInstructions that only raise fflags:\n"
c16: .string "  feq.s x8, f4, f4        (sNaN, NV)         "
c17: .string "  flt.s x8, f4, f4        (sNaN, NV)         "
c18: .string "  fle.d x8, f7, f7        (sNaN, NV)         "
c19: .string "  fcvt.w.s x8, f5         (1.5, NX)          "
c20: .string "  fcvt.wu.s x8, f6        (-1.0, NV)         "
c21: .string "  fcvt.l.d x8, f7         (sNaN, NV)         "
c22: .string "  vfadd.vv v3, v1, v1     (sNaN, NV)         "
c23: .string "  vmfeq.vv v3, v1, v1     (sNaN, NV)         "
c24: .string "  vfcvt.x.f.v v3, v2      (1.5, NX)          "
c25: .string "  vfredusum.vs v3, v1, v1 (sNaN, NV)         "
h26: .string "\nFP CSR writes:\n"
c27: .string "  csrw fflags, x0                            "
c28: .string "  fsrmi 1                                    "
c29: .string "  csrw fcsr, x0                              "
h30: .string "\nNeither (FS may stay Initial):\n"
c31: .string "  feq.s x8, f1, f1        (no flag)          "
c32: .string "  fclass.s x8, f4                            "
c33: .string "  fmv.x.w x8, f1                             "
s_fs:     .string "FS="
s_sd:     .string " SD="
s_ff:     .string " fflags=0x"
s_ok:     .string "\n"
s_bad:    .string "   <-- FS must be Dirty (3)\n"

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
