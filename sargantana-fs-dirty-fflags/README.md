# Instructions that raise fflags without writing an f register leave mstatus.FS clean

Reproducer for [bsc-loca/sargantana#117](https://github.com/bsc-loca/sargantana/issues/117).

For each case, `fsdirty.S` sets `mstatus.FS` = Initial, clears `fflags`, executes one
instruction, waits 32 nops, and prints `mstatus.FS`, `mstatus.SD` and `fflags` on the HTIF
console. The exit code is the number of cases whose FS should be Dirty but is not.
(SD reads 1 throughout because VS is Dirty for the vector cases.)

| File | |
|---|---|
| [fsdirty.elf](fsdirty.elf) | prebuilt ELF (rv64imafdv_zicsr_zfa, linked at 0x8000_0000) |
| [fsdirty.S](fsdirty.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, csr c5c8a1d): exit code 10 |
| [spike-expected.log](spike-expected.log) | output on Spike: every case that must be Dirty is Dirty, exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/fsdirty.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
