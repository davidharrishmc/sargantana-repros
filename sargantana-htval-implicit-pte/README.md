# htval on a guest-page fault during a VS-stage page-table read is not the PTE's guest physical address

Reproducer for bsc-loca/sargantana#NNN.

Two-stage translation, Sv39 over Sv39x4. The G-stage maps only GPA 0x8000_0000..0xbfff_ffff. VA 0x40a4_5678 walks
through a VS-stage level-1 table at GPA 0xc012_3000 and VA 0x00a4_5678 through a level-0 table at GPA 0xc045_6000;
neither table is mapped in the G-stage, so the implicit read of the PTE (at 0xc012_3028 and 0xc045_6228) takes a
guest-page fault. VA 0xc004_5678 is a VS-stage 1 GiB leaf at the unmapped GPA 0x1_4000_0000 (final access faults,
control). Each case `mret`s from M-mode into VS-mode (or HS-mode with `hstatus.SPVP` = 1 for `hlv.w`), accesses the
VA, and the HS-mode handler records `scause`, `stval`, `htval` and `htinst`. `htinst` is printed but not checked (0
is always legal). The exit code is the number of wrong cases.

| File | |
|---|---|
| [htval.elf](htval.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [htval.S](htval.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, mmu 0f4727a): exit code 5 |
| [spike-expected.log](spike-expected.log) | output on Spike 2c300cd: htval = PTE GPA >> 2, exit code 0 (Sail 0.16 also exits 0) |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/htval.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
