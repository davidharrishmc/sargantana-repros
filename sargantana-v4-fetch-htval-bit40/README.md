# core_tile v4.0: an instruction guest-page fault drops guest-physical-address bit 40 from mtval2/htval

Reproducer for the v4.0 comment on [sargantana#142](https://github.com/bsc-loca/sargantana/issues/142).

Two-stage translation; VS-mode `lw`, `sw` and `jalr` to a VS-stage leaf whose guest physical address has bit 40 set,
and a `jalr` to one with bit 39 set (control). Both addresses are below Sv39x4's 41-bit limit; their G-stage root
entries are invalid, so each access takes a guest-page fault. The load and store report the full address; the fetch
loses bit 40.

Every trap goes to M-mode. Each case `mret`s into the mode shown, performs one access with `a0` = the address and
executes `ecall`. The M-mode handler records `mcause`, `mstatus.GVA`, `mtval2`, `mtinst` and `a1`; a field printed as
dashes in the expected column is not checked. The exit code is the number of cases that differ from the expected values.

| File | |
|---|---|
| [fetchbit40.elf](fetchbit40.elf) | prebuilt ELF (rv64imah_zicsr_zicbom_zicboz, linked at 0x8000_0000) |
| [fetchbit40.S](fetchbit40.S), [mmu-harness.inc](mmu-harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 1b9529b (v4.0.0; Sargantana 8db4398, vidriol 3895af8): 1 wrong case |
| [spike-expected.log](spike-expected.log) | output on Spike 1.1.1-dev: 0 wrong cases |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +deadlock-cycles=20000 +load=/path/to/fetchbit40.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
