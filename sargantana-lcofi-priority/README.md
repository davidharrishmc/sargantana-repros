# LCOFI is taken before VSEI, VSSI and VSTI in HS-mode

Reproducer for [bsc-loca/sargantana#ISSUE_LCOFI](https://github.com/bsc-loca/sargantana/issues/ISSUE_LCOFI).

Each case clears every pending and enable bit from M-mode with `mstatus.MIE` = 0, makes a pair of interrupts pending
(`mip.SSIP`, `mip.LCOFIP` and `hvip.VS*IP`, all written from M-mode), enables both in `mie`, records `mip`, `mie` and
`hip`, and `mret`s to HS-mode with `sstatus.SIE` = 1. `mideleg` delegates SSI and LCOFI to HS-mode, the VS-level bits
of `mideleg` are read-only one, and `hideleg` = 0, so every interrupt targets HS-mode. The HS-mode handler records
`scause`. The exit code is the number of cases taking the wrong interrupt first.

| File | |
|---|---|
| [lcofi.elf](lcofi.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [lcofi.S](lcofi.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike (`--isa=rv64imah_zicsr_sscofpmf`) |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 3 |
| [spike-expected.log](spike-expected.log) | output on Spike: the VS-level interrupt is taken before LCOFI, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/lcofi.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
