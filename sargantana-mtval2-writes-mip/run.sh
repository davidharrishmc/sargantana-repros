#!/usr/bin/env bash
# Run mtval2.elf on the Sargantana core_tile simulator and, if spike is on PATH, on Spike.
# Usage: SARGANTANA_TILE=/path/to/core_tile ./run.sh
set -u
cd "$(dirname "$0")"
TILE="${SARGANTANA_TILE:?set SARGANTANA_TILE to a core_tile checkout built with make sim}"
echo "== Sargantana"
"$TILE/sim" +bootrom="$TILE/bootrom.hex" +max-cycles=3000000 +load=mtval2.elf
if command -v spike >/dev/null; then
  echo "== Spike"
  spike --isa=rv64imah_zicsr mtval2.elf
  echo "spike exit code $?"
fi
