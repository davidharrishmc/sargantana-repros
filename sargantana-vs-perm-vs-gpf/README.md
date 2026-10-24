# VS-stage leaf permission fault is reported as a guest-page fault when the leaf's GPA is unmapped in the G-stage

Reproducer for bsc-loca/sargantana#124.

Two-stage translation, Sv39 over Sv39x4. The G-stage maps only GPA 0x8000_0000..0xbfff_ffff. VA 0xc000_n000 are 4 KiB
VS-stage leaves that deny the access (no W for `sw`, no R for `lw`, no X for `jalr`, A = 0, or U = 1 from VS-mode
with SUM = 0) and whose GPA, 0x1_4000_n000, is unmapped in the G-stage. `hedeleg` delegates page faults to VS-mode
and `medeleg` sends guest-page faults to HS-mode. Each case `mret`s from M-mode into VS-mode and accesses the VA; the
VS-mode and HS-mode handlers record where the trap was taken, its cause and tval. The last two cases are controls (a
reserved W-only leaf, and a leaf at a mapped GPA). The exit code is the number of wrong cases.

| File | |
|---|---|
| [vsperm.elf](vsperm.elf) | prebuilt ELF (rv64imah_zicsr, linked at 0x8000_0000) |
| [vsperm.S](vsperm.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, mmu 0f4727a): exit code 5 |
| [spike-expected.log](spike-expected.log) | output on Spike 2c300cd: page fault into VS-mode in every case, exit code 0 (Sail 0.16 also exits 0) |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/vsperm.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
