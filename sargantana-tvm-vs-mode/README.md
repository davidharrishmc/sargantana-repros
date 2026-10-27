# mstatus.TVM = 1 makes SFENCE.VMA trap in VS-mode

Reproducer for an issue to be filed against bsc-loca/csr.

Each case sets `mstatus.TVM` and `hstatus.VTVM` from M-mode and `mret`s into VS-mode or HS-mode at an `sfence.vma` (or a `csrr satp`) followed by an `ecall`; every trap goes to M-mode. With TVM = 1 and VTVM = 0 the VS-mode `sfence.vma` must complete (ecall, 0x0a). The exit code is the number of wrong causes.

| File | |
|---|---|
| [tvm.elf](tvm.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [tvm.S](tvm.S), [harness.inc](harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): illegal instruction for the VS-mode sfence.vma with TVM = 1, exit code 1 |
| [spike-expected.log](spike-expected.log) | output on Spike: all four as expected, exit code 0 |
| [fix-csr.patch](fix-csr.patch) | possible fix for bsc-loca/csr c5c8a1d: `mstatus.TVM` traps `sfence.vma` only when V = 0 |
| [sargantana-patched.log](sargantana-patched.log) | output on core_tile 2528e7d with the fix patches of all four 2026-10-26 reproducers applied: all four as expected, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/tvm.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. A nonzero exit code ends the tile run in its `l2_behav.sv:464`
assertion, which is how the tile reports a failing test.
