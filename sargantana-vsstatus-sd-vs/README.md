# vsstatus.SD ignores vsstatus.VS

Reproducer for ISSUE_LINK.

Cases A-D write `vsstatus` from M-mode, wait 32 nops and read it back. Case E enters VS-mode
(hgatp = vsatp = Bare) with `vsstatus.VS` = Initial, executes `vadd.vv`, reads `sstatus`
(= `vsstatus`), and ecalls back to M-mode, which reads `vsstatus` again. Each line prints VS, FS
and SD of the value read. The exit code is the number of cases whose SD is wrong.

| File | |
|---|---|
| [vssd.elf](vssd.elf) | prebuilt ELF (rv64imafdvh_zicsr, linked at 0x8000_0000) |
| [vssd.S](vssd.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 3 |
| [spike-expected.log](spike-expected.log) | output on Spike: SD = 1 whenever VS or FS is Dirty, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/vssd.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
