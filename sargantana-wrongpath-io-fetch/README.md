# A wrong-path fetch from the IO region deadlocks core_tile

Reproducer for a Sargantana issue (link added once filed).

A taken `beq` skips a `jal` whose target, 0x7fff_f00c, is in DracDefaultConfig's IO section (0x4000_0000-0x7fff_ffff).
The `jal` is never executed, but the frontend follows it while the `beq` is unresolved. The fetch goes out as a
non-cacheable request, the testbench never answers it, and the core stops committing: the 200-cycle no-commit
watchdog fires (also with `+deadlock-cycles=20000`). With the `jal` target in RAM (`. + 0x1000`) the program exits 0.

| File | |
|---|---|
| [wpfetch.elf](wpfetch.elf) | prebuilt ELF (rv64i, linked at 0x8000_0000) |
| [wpfetch.S](wpfetch.S), [link.ld](link.ld), [Makefile](Makefile) | source; `make` rebuilds the ELF with riscv64-unknown-elf-gcc |
| [run.sh](run.sh) | runs the ELF on core_tile's `sim` and, if found, on Spike |
| [sargantana.log](sargantana.log) | output on core_tile 2528e7d (Sargantana 403975c): no commit for 200 cycles |
| [spike-expected.log](spike-expected.log) | output on Spike 5ef2766: exit code 0 |

Run from a core_tile checkout built with `make sim`:

```sh
./sim +bootrom=bootrom.hex +max-cycles=3000000 +load=/path/to/wpfetch.elf
```

or `SARGANTANA_TILE=/path/to/core_tile ./run.sh`.
