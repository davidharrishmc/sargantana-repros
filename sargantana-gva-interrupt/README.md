# hstatus.GVA is set on interrupts taken from VS-mode or VU-mode

Reproducer for [bsc-loca/sargantana#ISSUE](https://github.com/bsc-loca/sargantana/issues/ISSUE).

Cases A and B set `mip.SSIP` (with `mideleg.SSI` = 1) from M-mode and `mret` into VS-mode or
VU-mode (hgatp = vsatp = Bare), where the supervisor software interrupt is taken into HS-mode at
once. Case C ecalls from VS-mode (delegated to HS-mode by `medeleg`). Case D is case A with a
VS-level software interrupt (`hvip.VSSIP`, `hie.VSSIE` = 1, `hideleg` = 0). The HS-mode handler
records `scause` and `hstatus`; each line prints `scause` and GVA, SPV and SPVP. The exit code is
the number of cases with GVA = 1.

| File | |
|---|---|
| [gva.elf](gva.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [gva.S](gva.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 3 |
| [spike-expected.log](spike-expected.log) | output on Spike: GVA = 0 in every case, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/gva.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
