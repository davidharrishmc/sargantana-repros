# WFI in VU-mode with mstatus.TW = 1 raises a virtual-instruction exception

Reproducer for [bsc-loca/sargantana#ISSUE_WFI](https://github.com/bsc-loca/sargantana/issues/ISSUE_WFI).

Each case sets `mstatus.TW` and `hstatus.VTW` from M-mode and `mret`s into VU-mode or VS-mode (hgatp = vsatp = Bare) at
a `wfi` followed by an `ecall`. Nothing is pending and every trap goes to M-mode (`medeleg` = `mideleg` = 0), which
records `mcause`; an `ecall` cause means the `wfi` completed. The exit code is the number of cases whose cause is not
allowed by the spec.

| File | |
|---|---|
| [vuwfi.elf](vuwfi.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [vuwfi.S](vuwfi.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 2 |
| [spike-expected.log](spike-expected.log) | output on Spike: illegal instruction for VU-mode with TW = 1, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/vuwfi.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
