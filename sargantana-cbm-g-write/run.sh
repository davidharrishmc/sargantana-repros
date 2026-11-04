#!/usr/bin/env bash
# Run cbmg.elf on the Sargantana core_tile simulator and, if spike is on PATH, on Spike.
# Usage: SARGANTANA_TILE=/path/to/core_tile ./run.sh
# +deadlock-cycles raises the testbench's no-commit watchdog (default 200 cycles), which a cold two-stage
# page-table walk can exceed.
set -u
cd "$(dirname "$0")"
TILE="${SARGANTANA_TILE:?set SARGANTANA_TILE to a core_tile checkout built with make sim}"
echo "== Sargantana"
"$TILE/sim" +bootrom="$TILE/bootrom.hex" +max-cycles=3000000 +deadlock-cycles=20000 +load=cbmg.elf
if command -v spike >/dev/null; then
  echo "== Spike"
  spike --isa=rv64imah_zicsr_zicbom_zicboz cbmg.elf
  echo "spike exit code $?"
fi
