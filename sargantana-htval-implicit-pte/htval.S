# Reproducer: a guest-page fault on an implicit VS-stage page-table read must write htval = (GPA of that PTE) >> 2.
# Hypervisor spec, htval: "A guest-page fault may arise due to an implicit memory access during first-stage (VS-stage)
# address translation, in which case a guest physical address written to htval is that of the implicit memory access
# that faulted-for example, the address of a VS-level page table entry that could not be read." (shifted right by 2)
#
# Two-stage translation, Sv39 (vsatp) over Sv39x4 (hgatp). The G-stage maps GPA 0x8000_0000..0xbfff_ffff to the
# same PA and nothing else. The VS-stage maps the image at VA = GPA 0x8000_0000 and:
#   VA 0x40a4_5678: vroot[1] points to a level-1 table at GPA 0xc012_3000 (unmapped in the G-stage)
#                   -> the read of the level-1 PTE at GPA 0xc012_3000 + 5*8 = 0xc012_3028 faults
#   VA 0x00a4_5678: vroot[0] -> vt1 (mapped); vt1[5] points to a level-0 table at GPA 0xc045_6000 (unmapped)
#                   -> the read of the level-0 PTE at GPA 0xc045_6000 + 0x45*8 = 0xc045_6228 faults
#   VA 0xc004_5678: vroot[3] is a 1 GiB leaf at GPA 0x1_4000_0000 (unmapped) -> the final access faults (control)
# Each case runs from M-mode: mret into VS-mode (or HS-mode for hlv.w, hstatus.SPVP = 1), access the VA, ecall.
# medeleg sends guest-page faults to HS-mode, whose handler records scause, stval, htval and htinst and ecalls to M.
# Printed: cause, stval, htval, htinst and the expected cause and htval (htinst is printed but not checked, since 0
# is always legal). Exit code = number of wrong cases.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800
#define HSTATUS_SPVP  (1 << 8)
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_U 0x10
#define PTE_A 0x40
#define PTE_D 0x80

# SETPTE table, index, physical-address register, flags
.macro SETPTE table, idx, pa, flags
  la    t0, \table
  li    t1, (\idx) * 8
  add   t0, t0, t1
  srli  t2, \pa, 12
  slli  t2, t2, 10
  ori   t2, t2, \flags
  sd    t2, 0(t0)
.endm

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, skip
  csrw  mtvec, t0                    # PMP may be absent (Sargantana, Sail config): skip the writes if they trap
  li    t0, -1
  csrw  pmpaddr0, t0
  li    t0, 0x1f
  csrw  pmpcfg0, t0                  # NAPOT RWX over everything (Spike needs it for S/U accesses)
  la    t0, mtrap
  csrw  mtvec, t0
  la    t0, strap
  csrw  stvec, t0
  li    t0, (1 << 20) | (1 << 21) | (1 << 23)
  csrw  medeleg, t0                  # guest-page faults go to HS-mode
  csrw  hedeleg, zero
  csrw  mideleg, zero

  # G-stage: GPA 0x8000_0000 1 GiB -> PA 0x8000_0000 (U = 1, as G-stage leaves require)
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  # VS-stage
  li    a0, 0x80000000
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  li    a0, 0xc0123000
  SETPTE vroot, 1, a0, PTE_V         # level-1 table at an unmapped GPA
  la    a0, vt1
  SETPTE vroot, 0, a0, PTE_V         # level-1 table at a mapped GPA
  li    a0, 0xc0456000
  SETPTE vt1, 5, a0, PTE_V           # level-0 table at an unmapped GPA
  li    a0, 0x140000000
  SETPTE vroot, 3, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)   # 1 GiB leaf at an unmapped GPA

  la    t0, groot
  srli  t0, t0, 12
  li    t1, 8 << 60
  or    t0, t0, t1
  csrw  hgatp, t0                    # Sv39x4
  la    t0, vroot
  srli  t0, t0, 12
  li    t1, 8 << 60
  or    t0, t0, t1
  csrw  vsatp, t0                    # Sv39
  li    t0, HSTATUS_SPVP
  csrs  hstatus, t0                  # hlv.w from HS-mode uses VS-mode (S) permissions
  li    s1, 0
  la    a0, h_cases; call puts

# CASE(name, mpp, mpv, entry, va, expected cause, expected htval)
#define CASE(name, mpp, mpv, entry, va, ec, eh) \
  la    t0, cur                 ;\
  la    t1, name;  sd t1, 0(t0) ;\
  li    t1, mpp;   sd t1, 8(t0) ;\
  li    t1, mpv;   sd t1, 16(t0);\
  la    t1, entry; sd t1, 24(t0);\
  li    t1, va;    sd t1, 32(t0);\
  li    t1, ec;    sd t1, 40(t0);\
  li    t1, eh;    sd t1, 48(t0);\
  call  run_case
  CASE(c_lw_l1,   0x0800, 1, g_lw,   0x40a45678, 21, 0x30048c0a)
  CASE(c_sw_l1,   0x0800, 1, g_sw,   0x40a45678, 23, 0x30048c0a)
  CASE(c_jalr_l1, 0x0800, 1, g_jalr, 0x40a45678, 20, 0x30048c0a)
  CASE(c_hlv_l1,  0x0800, 0, g_hlv,  0x40a45678, 21, 0x30048c0a)
  CASE(c_lw_l0,   0x0800, 1, g_lw,   0x00a45678, 21, 0x3011588a)
  CASE(c_lw_fin,  0x0800, 1, g_lw,   0xc0045678, 21, 0x5001159e)

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# run_case: enter the mode in cur, run cur.entry with a0 = cur.va; mtrap returns to run_case_ret
run_case:
  la    t0, saved_ra
  sd    ra, 0(t0)
  la    t0, res
  sd    zero, 0(t0); sd zero, 8(t0); sd zero, 16(t0); sd zero, 24(t0); sd zero, 32(t0)
  hfence.gvma
  hfence.vvma
  la    t0, cur
  ld    t1, 8(t0)
  li    t2, MSTATUS_MPP
  csrc  mstatus, t2
  csrs  mstatus, t1
  ld    t1, 16(t0)
  li    t2, MSTATUS_MPV
  csrc  mstatus, t2
  beqz  t1, 1f
  csrs  mstatus, t2
1: ld   t1, 24(t0)
  csrw  mepc, t1
  ld    a0, 32(t0)
  mret
run_case_ret:
  la    t0, saved_ra
  ld    ra, 0(t0)
  j     report

# guest entry points (a0 = VA); a trap goes to strap, otherwise the ecall goes to M-mode
g_lw:   lw    t0, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_jalr: jalr  t0, 0(a0);  ecall
g_hlv:  hlv.w t0, (a0);   ecall

# HS-mode handler: record the trap, then ecall to M-mode
strap:
  la    t0, res
  li    t1, 1;          sd t1, 0(t0)
  csrr  t1, scause;     sd t1, 8(t0)
  csrr  t1, stval;      sd t1, 16(t0)
  csrr  t1, htval;      sd t1, 24(t0)
  csrr  t1, htinst;     sd t1, 32(t0)
  ecall

skip:
  csrr  t1, mepc
  addi  t1, t1, 4
  csrw  mepc, t1
  mret

# M-mode handler: any trap ends the case
mtrap:
  li    t0, MSTATUS_MPV
  csrc  mstatus, t0
  li    t0, MSTATUS_MPP
  csrs  mstatus, t0
  la    t0, run_case_ret
  csrw  mepc, t0
  mret

report:
  addi  sp, sp, -16
  sd    ra, 8(sp)
  la    t0, cur; ld a0, 0(t0); call puts
  la    a0, s_cause; call puts
  la    t0, res; ld a0, 8(t0); li a1, 2; call puthex
  la    a0, s_tval; call puts
  la    t0, res; ld a0, 16(t0); li a1, 10; call puthex
  la    a0, s_htval; call puts
  la    t0, res; ld a0, 24(t0); li a1, 8; call puthex
  la    a0, s_htinst; call puts
  la    t0, res; ld a0, 32(t0); li a1, 8; call puthex
  la    a0, s_exp; call puts
  la    t0, cur; ld a0, 40(t0); li a1, 2; call puthex
  la    a0, s_htval; call puts
  la    t0, cur; ld a0, 48(t0); li a1, 8; call puthex
  la    t0, res; la t1, cur
  ld    t2, 0(t0)                    # taken in HS-mode
  li    t3, 1
  bne   t2, t3, 2f
  ld    t2, 8(t0); ld t3, 40(t1)
  bne   t2, t3, 2f
  ld    t2, 16(t0); ld t3, 32(t1)
  bne   t2, t3, 2f
  ld    t2, 24(t0); ld t3, 48(t1)
  bne   t2, t3, 2f
  la    a0, s_ok
  j     1f
2: addi s1, s1, 1
  la    a0, s_bad
1: call puts
  ld    ra, 8(sp)
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
h_cases:   .string "Guest-page faults taken into HS-mode (expected htval = faulting GPA >> 2):\n"
c_lw_l1:   .string "  VS lw    0x40a45678, level-1 PTE read faults: "
c_sw_l1:   .string "  VS sw    0x40a45678, level-1 PTE read faults: "
c_jalr_l1: .string "  VS jalr  0x40a45678, level-1 PTE read faults: "
c_hlv_l1:  .string "  HS hlv.w 0x40a45678, level-1 PTE read faults: "
c_lw_l0:   .string "  VS lw    0x00a45678, level-0 PTE read faults: "
c_lw_fin:  .string "  VS lw    0xc0045678, final access faults:     "
s_cause:   .string "cause="
s_tval:    .string " stval="
s_htval:   .string " htval="
s_htinst:  .string " htinst="
s_exp:     .string "  expected cause="
s_ok:      .string "\n"
s_bad:     .string "   <-- wrong\n"

  .section .data
  .balign 16384
groot:    .fill 2048, 8, 0           # Sv39x4 root: 16 KiB
vroot:    .fill 512, 8, 0
vt1:      .fill 512, 8, 0
  .balign 8
cur:      .fill 8, 8, 0
res:      .fill 8, 8, 0
saved_ra: .dword 0
outlen:   .dword 0
  .balign 16
  .space 4096
stack_top:

  .section .tohost, "aw", @progbits
  .balign 64; .globl tohost;   tohost:   .dword 0
  .balign 64; .globl fromhost; fromhost: .dword 0
  .balign 64; htif_magicmem: .dword 0,0,0,0,0,0,0,0
  .balign 64; htif_iobuf: .fill 8192,1,0
