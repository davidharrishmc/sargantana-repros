# mstatus.GVA and hstatus.GVA are wrong on exceptions taken from VS-mode

Reproducer for an issue to be filed against bsc-loca/sargantana.

Each case `mret`s into VS-mode at one instruction followed by an `ecall`; every trap goes to M-mode, which records `mcause` and `mstatus.GVA`. A breakpoint and a misaligned `jal` write a guest virtual address to `mtval`, so GVA = 1; a virtual-instruction exception writes the instruction bits, so GVA = 0. The misaligned `jalr` and the `ecall` are controls. The exit code is the number of wrong cases.

| File | |
|---|---|
| [gvaexc.elf](gvaexc.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [gvaexc.S](gvaexc.S), [harness.inc](harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): GVA = 0 for ebreak and jal, GVA = 1 for hlv.w, exit code 3 |
| [spike-expected.log](spike-expected.log) | output on Spike: all five as expected, exit code 0 |
| [fix-sargantana.patch](fix-sargantana.patch), [fix-csr.patch](fix-csr.patch) | possible fix: decoder GVA for misaligned `jal` and virtual instruction (bsc-loca/sargantana 403975c), and breakpoint GVA (bsc-loca/csr c5c8a1d) |
| [sargantana-patched.log](sargantana-patched.log) | output on core_tile 2528e7d with the fix patches of all four 2026-10-26 reproducers applied: all five as expected, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/gvaexc.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. A nonzero exit code ends the tile run in its `l2_behav.sv:464`
assertion, which is how the tile reports a failing test.
