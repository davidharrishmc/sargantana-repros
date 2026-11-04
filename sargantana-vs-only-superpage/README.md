# With hgatp = Bare, a VS-stage superpage translates every address to the superpage's first 4 KiB page

Reproducer for [sargantana#136](https://github.com/bsc-loca/sargantana/issues/136).

hgatp = Bare, vsatp = Sv39. VS-mode loads of `marker` through a 1 GiB and a 2 MiB VS-stage leaf on PA 0x8000_0000, and through a 4 KiB leaf (control). The loaded word is printed as `a1`.

Every trap goes to M-mode. Each case `mret`s into the mode shown, performs one access with `a0` = the address and
executes `ecall`, so a case that does not trap reports the ecall (`mcause` 8 from VU-mode, 9 from HS-mode, 10 from
VS-mode, 11 from M-mode). The M-mode handler records `mcause`, `mstatus.GVA`, `mtval2`, `mtinst` and `a1` (the loaded
word, or ffffffff if nothing was loaded); a field printed as dashes in the expected column is not checked. The exit
code is the number of cases that differ from the expected values. The comment block at the top of [vssuper.S](vssuper.S)
cites the specification and describes the page tables.

| File | |
|---|---|
| [vssuper.elf](vssuper.elf) | prebuilt ELF (rv64imah_zicsr_zicbom_zicboz, linked at 0x8000_0000) |
| [vssuper.S](vssuper.S), [mmu-harness.inc](mmu-harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, mmu 0f4727a, csr c5c8a1d): 2 wrong case(s) |
| [spike-expected.log](spike-expected.log) | output on Spike 5ef2766: 0 wrong case(s) |
| [possible-fix-mmu.patch](possible-fix-mmu.patch) | a possible fix against bsc-loca/mmu 0f4727a (`git apply` in that repository); with only this change, the reproducer passes on core_tile 2528e7d |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +deadlock-cycles=20000 +load=/path/to/vssuper.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. `+deadlock-cycles` raises the testbench's 200-cycle no-commit
watchdog, which a cold two-stage page-table walk can exceed.
