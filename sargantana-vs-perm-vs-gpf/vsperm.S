# Reproducer: a VS-stage leaf that denies the access must raise a page fault, even when its GPA is unmapped in the
# G-stage.
# Privileged spec, virtual address translation process: "Determine if the requested memory access is allowed by the
# pte.r, pte.w, and pte.x bits. If not, stop and raise a page-fault exception corresponding to the original access
# type." (likewise for pte.u, and for pte.a = 0 without Svadu). Only when the walk succeeds is there a translated
# address. Hypervisor spec (norm:H_vm_twostage): "the original virtual address is converted in the first stage by
# VS-level address translation ... into a guest physical address. The guest physical address is then converted in
# the second stage by guest physical address translation".
#
# Two-stage translation, Sv39 (vsatp) over Sv39x4 (hgatp). The G-stage maps GPA 0x8000_0000..0xbfff_ffff to the same
# PA and nothing else. The VS-stage maps the image at VA = GPA 0x8000_0000, and 4 KiB leaves at VA 0xc000_n000
# (vroot[3] -> vt1 -> vt0) whose GPA is 0x1_4000_n000 (unmapped) or, for the control, a mapped scratch page.
# hedeleg delegates page faults (12, 13, 15) to VS-mode; medeleg sends guest-page faults (20, 21, 23) to HS-mode.
# Each case mrets into VS-mode, accesses the VA and ecalls to M-mode. The VS-mode and HS-mode handlers record where
# the trap was taken, its cause and tval, and ecall to M-mode. Exit code = number of wrong cases.

#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_MPP   0x1800
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
  la    t0, vstrap
  csrw  vstvec, t0
  li    t0, (1 << 12) | (1 << 13) | (1 << 15) | (1 << 20) | (1 << 21) | (1 << 23)
  csrw  medeleg, t0                  # page faults and guest-page faults go to HS-mode
  li    t0, (1 << 12) | (1 << 13) | (1 << 15)
  csrw  hedeleg, t0                  # page faults go on to VS-mode
  csrw  mideleg, zero

  # G-stage: GPA 0x8000_0000 1 GiB -> PA 0x8000_0000 (U = 1, as G-stage leaves require)
  li    a0, 0x80000000
  SETPTE groot, 2, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)
  # VS-stage
  li    a0, 0x80000000
  SETPTE vroot, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)
  la    a0, vt1
  SETPTE vroot, 3, a0, PTE_V
  la    a0, vt0
  SETPTE vt1, 0, a0, PTE_V
  li    a0, 0x140001000
  SETPTE vt0, 1, a0, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)           # no W, unmapped GPA
  li    a0, 0x140002000
  SETPTE vt0, 2, a0, (PTE_D | PTE_A | PTE_X | PTE_V)                   # no R, unmapped GPA
  li    a0, 0x140003000
  SETPTE vt0, 3, a0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)           # no X, unmapped GPA
  li    a0, 0x140004000
  SETPTE vt0, 4, a0, (PTE_D | PTE_X | PTE_W | PTE_R | PTE_V)           # A = 0, unmapped GPA
  li    a0, 0x140005000
  SETPTE vt0, 5, a0, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)   # U = 1 (VS-mode, SUM = 0), unmapped GPA
  li    a0, 0x140006000
  SETPTE vt0, 6, a0, (PTE_D | PTE_A | PTE_W | PTE_V)                   # reserved W = 1 R = 0, unmapped GPA
  la    a0, scratch
  SETPTE vt0, 7, a0, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)           # no W, mapped GPA

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
  li    s1, 0
  la    a0, h_cases; call puts

# CASE(name, entry, va, expected where (1 HS, 2 VS), expected cause)
#define CASE(name, entry, va, ew, ec) \
  la    t0, cur                 ;\
  la    t1, name;  sd t1, 0(t0) ;\
  la    t1, entry; sd t1, 24(t0);\
  li    t1, va;    sd t1, 32(t0);\
  li    t1, ew;    sd t1, 40(t0);\
  li    t1, ec;    sd t1, 48(t0);\
  call  run_case
  CASE(c_sw_rx,   g_sw,   0xc0001000, 2, 15)
  CASE(c_lw_x,    g_lw,   0xc0002000, 2, 13)
  CASE(c_jalr_rw, g_jalr, 0xc0003000, 2, 12)
  CASE(c_lw_a0,   g_lw,   0xc0004000, 2, 13)
  CASE(c_lw_u,    g_lw,   0xc0005000, 2, 13)
  CASE(c_lw_wo,   g_lw,   0xc0006000, 2, 13)
  CASE(c_sw_map,  g_sw,   0xc0007000, 2, 15)

  call  flush
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# run_case: mret into VS-mode at cur.entry with a0 = cur.va; mtrap returns to run_case_ret
run_case:
  la    t0, saved_ra
  sd    ra, 0(t0)
  la    t0, res
  sd    zero, 0(t0); sd zero, 8(t0); sd zero, 16(t0)
  hfence.gvma
  hfence.vvma
  li    t2, MSTATUS_MPP
  csrc  mstatus, t2
  li    t2, 0x0800
  csrs  mstatus, t2                  # MPP = S
  li    t2, MSTATUS_MPV
  csrs  mstatus, t2                  # MPV = 1
  la    t0, cur
  ld    t1, 24(t0)
  csrw  mepc, t1
  ld    a0, 32(t0)
  mret
run_case_ret:
  la    t0, saved_ra
  ld    ra, 0(t0)
  j     report

# guest entry points (a0 = VA); a trap goes to vstrap or strap, otherwise the ecall goes to M-mode
g_lw:   lw    t0, 0(a0);  ecall
g_sw:   sw    zero, 0(a0); ecall
g_jalr: jalr  t0, 0(a0);  ecall

# HS-mode handler: record the trap, then ecall to M-mode
strap:
  la    t0, res
  li    t1, 1;          sd t1, 0(t0)
  csrr  t1, scause;     sd t1, 8(t0)
  csrr  t1, stval;      sd t1, 16(t0)
  ecall
# VS-mode handler (scause and stval are vscause and vstval here)
vstrap:
  la    t0, res
  li    t1, 2;          sd t1, 0(t0)
  csrr  t1, scause;     sd t1, 8(t0)
  csrr  t1, stval;      sd t1, 16(t0)
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
  la    a0, s_taken; call puts
  la    t0, res; ld t0, 0(t0); slli t0, t0, 2
  la    a0, s_where; add a0, a0, t0; call puts
  la    a0, s_cause; call puts
  la    t0, res; ld a0, 8(t0); li a1, 2; call puthex
  la    a0, s_tval; call puts
  la    t0, res; ld a0, 16(t0); li a1, 10; call puthex
  la    a0, s_exp; call puts
  la    t0, cur; ld t0, 40(t0); slli t0, t0, 2
  la    a0, s_where; add a0, a0, t0; call puts
  la    a0, s_cause; call puts
  la    t0, cur; ld a0, 48(t0); li a1, 2; call puthex
  la    t0, res; la t1, cur
  ld    t2, 0(t0);  ld t3, 40(t1)
  bne   t2, t3, 2f
  ld    t2, 8(t0);  ld t3, 48(t1)
  bne   t2, t3, 2f
  ld    t2, 16(t0); ld t3, 32(t1)
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
h_cases:   .string "VS-mode access denied by a 4 KiB VS-stage leaf (expected: page fault into VS-mode, tval = VA):\n"
c_sw_rx:   .string "  sw   0xc0001000, leaf RX,     GPA unmapped: "
c_lw_x:    .string "  lw   0xc0002000, leaf X,      GPA unmapped: "
c_jalr_rw: .string "  jalr 0xc0003000, leaf RW,     GPA unmapped: "
c_lw_a0:   .string "  lw   0xc0004000, leaf A = 0,  GPA unmapped: "
c_lw_u:    .string "  lw   0xc0005000, leaf U = 1,  GPA unmapped: "
c_lw_wo:   .string "  lw   0xc0006000, leaf W only, GPA unmapped: "
c_sw_map:  .string "  sw   0xc0007000, leaf RX,     GPA mapped:   "
s_taken:   .string "taken in "
  .balign 4
s_where:   .string "--"
  .balign 4
           .string "HS"
  .balign 4
           .string "VS"
s_cause:   .string " cause="
s_tval:    .string " tval="
s_exp:     .string "  expected "
s_ok:      .string "\n"
s_bad:     .string "   <-- wrong\n"

  .section .data
  .balign 16384
groot:    .fill 2048, 8, 0           # Sv39x4 root: 16 KiB
vroot:    .fill 512, 8, 0
vt1:      .fill 512, 8, 0
vt0:      .fill 512, 8, 0
scratch:  .fill 512, 8, 0
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
