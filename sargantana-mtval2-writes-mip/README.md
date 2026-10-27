# A CSR write to mtval2 writes mip

Reproducer for [csr#14](https://github.com/bsc-loca/csr/issues/14).

In M-mode with `mie` = 0 the program writes 0x2222 to `mtval2` and reads back `mip` and `mtval2`. The exit code is the number of wrong values.

| File | |
|---|---|
| [mtval2.elf](mtval2.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [mtval2.S](mtval2.S), [harness.inc](harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): mip & 0x2222 = 0x2222 and mtval2 = 0, exit code 2 |
| [spike-expected.log](spike-expected.log) | output on Spike: mip unchanged and mtval2 = 0x2222, exit code 0 |
| [fix-csr.patch](fix-csr.patch) | possible fix for bsc-loca/csr c5c8a1d: a separate `CSR_MTVAL2` write arm |
| [sargantana-patched.log](sargantana-patched.log) | output on core_tile 2528e7d with the fixes for csr#14, csr#15, csr#16 and sargantana#128 applied: both values as expected, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/mtval2.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. A nonzero exit code ends the tile run in its `l2_behav.sv:464`
assertion, which is how the tile reports a failing test.
