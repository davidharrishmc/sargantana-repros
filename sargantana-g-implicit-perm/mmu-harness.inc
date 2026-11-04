# Shared harness for the Sargantana two-stage translation reproducers.
#
# Every trap goes to M-mode (medeleg = mideleg = hedeleg = 0, interrupts disabled). Each CASE sets mstatus, hstatus
# and vsstatus bits from M-mode and mrets to the case's guest code in the requested mode with a0 = the case's address.
# The guest code does one access, leaves any loaded value in a1, and executes ecall, so an access that does not trap
# shows up as the ecall (mcause 8 from VU-mode, 10 from VS-mode, 9 from HS-mode, 11 from M-mode). The M-mode handler
# records mcause, mstatus.GVA, mtval2, mtinst and a1. Printed per case: those values and the expected ones; a field
# whose expected value is ANY is not checked. Exit code = number of cases that differ from the expected values.
#
# The including file defines: init (page tables, hgatp and vsatp; returns with ret), cases (CASE lines, then
# j finish), the guest code, the rodata strings (h_cases and one name per case) and its page tables.

#define MSTATUS_MPRV  (1 << 17)
#define MSTATUS_SUM   (1 << 18)
#define MSTATUS_MXR   (1 << 19)
#define MSTATUS_MPV   (1 << 39)
#define MSTATUS_GVA   (1 << 38)
#define MSTATUS_MPP   0x1800
#define MPP_U         0x0000
#define MPP_S         0x0800
#define MPP_M         0x1800
#define HSTATUS_SPVP  (1 << 8)
#define SSTATUS_SUM   (1 << 18)
#define SSTATUS_MXR   (1 << 19)
#define ANY           0x5555
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_U 0x10
#define PTE_A 0x40
#define PTE_D 0x80
#define SV39_MODE     (8 << 60)

# SETPTE table, index, register holding the physical address, flags
.macro SETPTE table, idx, pa, flags
  la    t0, \table
  li    t1, (\idx) * 8
  add   t0, t0, t1
  srli  t2, \pa, 12
  slli  t2, t2, 10
  li    t1, \flags
  or    t2, t2, t1
  sd    t2, 0(t0)
.endm

# MAP4K table, register holding the physical address of entry 0, flags: fill all 512 entries with 4 KiB leaves
.macro MAP4K table, pa, flags
  la    t0, \table
  srli  t2, \pa, 12
  slli  t2, t2, 10
  li    t1, \flags
  or    t2, t2, t1
  li    t3, 512
  li    t4, 1 << 10
1: sd   t2, 0(t0)
  addi  t0, t0, 8
  add   t2, t2, t4
  addi  t3, t3, -1
  bnez  t3, 1b
.endm

# SETATP csr, table: write Sv39 or Sv39x4 mode and the table's PPN
.macro SETATP csr, table
  la    t0, \table
  srli  t0, t0, 12
  li    t1, SV39_MODE
  or    t0, t0, t1
  csrw  \csr, t0
.endm

# CASE(name, guest code, MPV, MPP, mstatus bits, hstatus bits, vsstatus bits, address, mcause, GVA, mtval2, a1)
#define CASE(name, code, mpv, mpp, mbits, hbits, vsbits, addr, cause, gva, tval2, a1v) \
  la    t0, cur                 ;\
  la    t1, name;   sd t1, 0(t0) ;\
  la    t1, code;   sd t1, 8(t0) ;\
  li    t1, mpv;    sd t1, 16(t0);\
  li    t1, mpp;    sd t1, 24(t0);\
  li    t1, mbits;  sd t1, 32(t0);\
  li    t1, hbits;  sd t1, 40(t0);\
  li    t1, vsbits; sd t1, 48(t0);\
  li    t1, addr;   sd t1, 56(t0);\
  li    t1, cause;  sd t1, 64(t0);\
  li    t1, gva;    sd t1, 72(t0);\
  li    t1, tval2;  sd t1, 80(t0);\
  li    t1, a1v;    sd t1, 88(t0);\
  call  run_case

# CASE_SYM: like CASE, with address = sym + adj (adj is a constant, sym a label)
#define CASE_SYM(name, code, mpv, mpp, mbits, hbits, vsbits, sym, adj, cause, gva, tval2, a1v) \
  la    t0, cur                 ;\
  la    t1, name;   sd t1, 0(t0) ;\
  la    t1, code;   sd t1, 8(t0) ;\
  li    t1, mpv;    sd t1, 16(t0);\
  li    t1, mpp;    sd t1, 24(t0);\
  li    t1, mbits;  sd t1, 32(t0);\
  li    t1, hbits;  sd t1, 40(t0);\
  li    t1, vsbits; sd t1, 48(t0);\
  la    t1, sym;    li t2, adj; add t1, t1, t2; sd t1, 56(t0);\
  li    t1, cause;  sd t1, 64(t0);\
  li    t1, gva;    sd t1, 72(t0);\
  li    t1, tval2;  sd t1, 80(t0);\
  li    t1, a1v;    sd t1, 88(t0);\
  call  run_case

  .section .text.init
  .globl _start
_start:
  la    sp, stack_top
  la    t0, skip
  csrw  mtvec, t0                    # skip CSR writes that trap (absent PMP, envcfg)
  li    t0, -1
  csrw  pmpaddr0, t0
  li    t0, 0x1f
  csrw  pmpcfg0, t0                  # NAPOT RWX over everything (Spike needs it for S/U accesses)
  li    t0, 0xd0
  csrw  menvcfg, t0                  # CBIE = 01, CBCFE = 1, CBZE = 1
  csrw  henvcfg, t0
  csrw  senvcfg, t0
  la    t0, mtrap
  csrw  mtvec, t0
  csrw  medeleg, zero
  csrw  mideleg, zero
  csrw  hedeleg, zero
  csrw  hideleg, zero
  csrw  mie, zero
  csrw  satp, zero
  csrw  hgatp, zero
  csrw  vsatp, zero
  li    s1, 0
  call  init
  hfence.gvma
  hfence.vvma
  sfence.vma
  la    a0, h_cases; call puts
  la    a0, h_cols; call puts
  call  flush
  la    t0, outlen
  sd    zero, 0(t0)
  j     cases

finish:
  la    t0, outlen
  ld    t0, 0(t0)
  beqz  t0, 2f
  call  flush
2:
  slli  t0, s1, 1
  ori   t0, t0, 1
  la    t1, tohost
  sd    t0, 0(t1)
1: j 1b

# run_case: set the case's status bits and mret into its guest code with a0 = address; mtrap returns to report
run_case:
  la    t0, saved_ra
  sd    ra, 0(t0)
  hfence.gvma
  hfence.vvma
  la    t0, cur
  ld    t1, 40(t0); csrs hstatus, t1
  ld    t1, 48(t0); csrs vsstatus, t1
  li    t1, MSTATUS_MPP; csrc mstatus, t1
  ld    t1, 24(t0); csrs mstatus, t1
  li    t1, MSTATUS_MPV; csrc mstatus, t1
  ld    t2, 16(t0)
  beqz  t2, 1f
  csrs  mstatus, t1
1: ld   t1, 8(t0);  csrw mepc, t1
  ld    a0, 56(t0)
  li    a1, -1
  ld    t1, 32(t0)
  csrs  mstatus, t1                  # mstatus bits last: MPRV changes M-mode loads
  mret

# M-mode handler: any trap ends the case
mtrap:
  li    t0, MSTATUS_MPRV
  csrc  mstatus, t0                  # first, so that the handler's own accesses are not translated
  la    t0, res
  csrr  t1, mcause;  sd t1, 0(t0)
  csrr  t1, mstatus
  srli  t1, t1, 38
  andi  t1, t1, 1;   sd t1, 8(t0)
  csrr  t1, mtval2;  sd t1, 16(t0)
  csrr  t1, mtinst;  sd t1, 24(t0)
  sd    a1, 32(t0)
  la    t0, cur
  ld    t1, 32(t0); csrc mstatus, t1
  ld    t1, 40(t0); csrc hstatus, t1
  ld    t1, 48(t0); csrc vsstatus, t1
  li    t1, MSTATUS_MPV
  csrc  mstatus, t1
  li    t1, MSTATUS_MPP
  csrs  mstatus, t1                  # back to M-mode
  la    t1, report
  csrw  mepc, t1
  mret

skip:
  csrr  t1, mepc
  addi  t1, t1, 4
  csrw  mepc, t1
  mret

# report: print the recorded and expected values, count a mismatch
report:
  la    t0, cur; ld a0, 0(t0); call puts
  la    t0, res; ld a0, 0(t0);  li a1, 2;  call puthex
  la    a0, s_sp; call puts
  la    t0, res; ld a0, 8(t0);  li a1, 1;  call puthex
  la    a0, s_sp; call puts
  la    t0, res; ld a0, 16(t0); li a1, 14; call puthex
  la    a0, s_sp; call puts
  la    t0, res; ld a0, 24(t0); li a1, 8;  call puthex
  la    a0, s_sp; call puts
  la    t0, res; ld a0, 32(t0); li a1, 8;  call puthex
  la    a0, s_exp; call puts
  la    t0, cur; ld a0, 64(t0); li a1, 2;  call putexp
  la    a0, s_sp; call puts
  la    t0, cur; ld a0, 72(t0); li a1, 1;  call putexp
  la    a0, s_sp; call puts
  la    t0, cur; ld a0, 80(t0); li a1, 14; call putexp
  la    a0, s_sp; call puts
  la    t0, cur; ld a0, 88(t0); li a1, 8;  call putexp
  li    s2, 0                        # mismatch flag
  la    t0, res; la t1, cur
  ld    t2, 0(t0);  ld t3, 64(t1); call cmpfld
  ld    t2, 8(t0);  ld t3, 72(t1); call cmpfld
  ld    t2, 16(t0); ld t3, 80(t1); call cmpfld
  ld    t2, 32(t0); ld t3, 88(t1)
  slli  t2, t2, 32; srli t2, t2, 32  # a1 compared on its low 32 bits
  call  cmpfld
  la    a0, s_ok
  beqz  s2, 1f
  addi  s1, s1, 1
  la    a0, s_bad
1: call puts
  call  flush                        # print each case as it finishes, so that a later hang loses nothing
  la    t0, outlen
  sd    zero, 0(t0)
  la    t0, saved_ra
  ld    ra, 0(t0)
  ret

# cmpfld: t2 = observed, t3 = expected (ANY = not checked); sets s2 on a mismatch; keeps t0, t1
cmpfld:
  li    t4, ANY
  beq   t3, t4, 1f
  beq   t2, t3, 1f
  li    s2, 1
1: ret

# putexp(a0 = value, a1 = digits): "-" padded to the field width for ANY, else puthex
putexp:
  li    t0, ANY
  bne   a0, t0, puthex
  la    t1, outlen; ld t2, 0(t1)
  la    t3, htif_iobuf; add t3, t3, t2
  li    t0, '-'
1: sb   t0, 0(t3)
  addi  t3, t3, 1; addi t2, t2, 1
  addi  a1, a1, -1
  bnez  a1, 1b
  sd    t2, 0(t1)
  ret

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
  li    t0, 5000                      # let the host (Spike polls every few thousand steps) see the syscall before the next tohost write
1: addi t0, t0, -1
  bnez  t0, 1b
  ret

  .section .rodata
h_cols:  .string "                                        cause G mtval2         mtinst   a1          expected\n"
s_sp:    .string " "
s_exp:   .string "   expected "
s_ok:    .string "\n"
s_bad:   .string "   <-- wrong\n"

  .section .data
  .balign 8
cur:      .fill 12, 8, 0
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
