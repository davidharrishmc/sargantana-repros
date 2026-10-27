# Instructions that HS-mode cannot execute either raise a virtual-instruction exception in VS-mode and VU-mode

Reproducer for an issue to be filed against bsc-loca/csr.

Each case `mret`s from M-mode into VS-mode or VU-mode (hgatp = vsatp = Bare) at one instruction followed by an `ecall`. Every trap goes to M-mode (`medeleg` = 0), which records `mcause`. Five cases are illegal in HS-mode too (unimplemented CSRs 0x101 and 0x901 from VU-mode, a write to the read-only `hgeip` and `cycle`, `mret`) and must raise illegal instruction (2); two controls access implemented CSRs and must raise virtual instruction (0x16). The exit code is the number of wrong causes.

| File | |
|---|---|
| [virtill.elf](virtill.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [virtill.S](virtill.S), [harness.inc](harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): virtual instruction for all seven, exit code 5 |
| [spike-expected.log](spike-expected.log) | output on Spike: illegal instruction for the five and virtual instruction for the controls, exit code 0 |
| [fix-csr.patch](fix-csr.patch) | possible fix for bsc-loca/csr c5c8a1d: illegal instruction for read-only CSR writes, CSRs that do not exist and M-mode system instructions |
| [sargantana-patched.log](sargantana-patched.log) | output on core_tile 2528e7d with the fix patches of all four 2026-10-26 reproducers applied: all seven as expected, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/virtill.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. A nonzero exit code ends the tile run in its `l2_behav.sv:464`
assertion, which is how the tile reports a failing test.
