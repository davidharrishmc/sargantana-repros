# Interrupts delegated to VS-mode by hideleg are taken in HS-mode and U-mode

Reproducer for [bsc-loca/sargantana#ISSUE](https://github.com/bsc-loca/sargantana/issues/ISSUE).

Each case sets `hie` = 0x444, `hideleg` and `hvip` from M-mode, with `sstatus.SIE` = `vsstatus.SIE` = 1, and `mret`s to
HS-mode, U-mode or VS-mode (hgatp = vsatp = Bare), which spins and then ecalls to M-mode. The HS-mode and VS-mode
handlers record where the interrupt was taken and its cause. The last two cases are controls. The exit code is the
number of wrong cases.

| File | |
|---|---|
| [hideleg.elf](hideleg.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [hideleg.S](hideleg.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 3 |
| [spike-expected.log](spike-expected.log) | output on Spike: no interrupt taken while V = 0, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/hideleg.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
