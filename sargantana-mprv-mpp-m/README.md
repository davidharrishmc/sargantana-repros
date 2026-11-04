# With mstatus.MPRV = 1 and MPP = M, loads and stores are still translated by the G stage when MPV = 1

Reproducer for [csr#17](https://github.com/bsc-loca/csr/issues/17).

vsatp = Bare, hgatp = Sv39x4 with an empty table. M-mode `lw`/`sw` with MPRV = 1 and MPP/MPV = M/1, M/0 and S/1.

Every trap goes to M-mode. Each case `mret`s into the mode shown, performs one access with `a0` = the address and
executes `ecall`, so a case that does not trap reports the ecall (`mcause` 8 from VU-mode, 9 from HS-mode, 10 from
VS-mode, 11 from M-mode). The M-mode handler records `mcause`, `mstatus.GVA`, `mtval2`, `mtinst` and `a1` (the loaded
word, or ffffffff if nothing was loaded); a field printed as dashes in the expected column is not checked. The exit
code is the number of cases that differ from the expected values. The comment block at the top of [mprvm.S](mprvm.S)
cites the specification and describes the page tables.

| File | |
|---|---|
| [mprvm.elf](mprvm.elf) | prebuilt ELF (rv64imah_zicsr_zicbom_zicboz, linked at 0x8000_0000) |
| [mprvm.S](mprvm.S), [mmu-harness.inc](mmu-harness.inc), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c, mmu 0f4727a, csr c5c8a1d): 2 wrong case(s) |
| [spike-expected.log](spike-expected.log) | output on Spike 5ef2766: 0 wrong case(s) |
| [possible-fix-csr.patch](possible-fix-csr.patch) | a possible fix against bsc-loca/csr c5c8a1d (`git apply` in that repository); with only this change, the reproducer passes on core_tile 2528e7d |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +deadlock-cycles=20000 +load=/path/to/mprvm.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`. `+deadlock-cycles` raises the testbench's 200-cycle no-commit
watchdog, which a cold two-stage page-table walk can exceed.
