#!/usr/bin/env bash
# Functional simulation of the SPI master with GHDL (VHDL-2008).
# Output: build/sim/tb_spi_master.ghw (all signals, for GTKWave),
#         build/sim/tb_spi_master.vcd, build/sim/sim.log
# Exit code 0 only if the testbench prints "TB RESULT: PASS".
set -euo pipefail
cd "$(dirname "$0")/.."

GHDL=${GHDL:-ghdl}
OUT=build/sim
mkdir -p "$OUT"
FLAGS=(--std=08 --workdir="$OUT" -frelaxed)

"$GHDL" --version | head -1
for f in src/spi_master_tx.vhd src/spi_master_rx.vhd src/spi_master.vhd tb/tb_spi_master.vhd; do
  "$GHDL" -a "${FLAGS[@]}" "$f"
done
"$GHDL" -e "${FLAGS[@]}" tb_spi_master
"$GHDL" -r "${FLAGS[@]}" tb_spi_master \
  --wave="$OUT/tb_spi_master.ghw" --vcd="$OUT/tb_spi_master.vcd" 2>&1 | tee "$OUT/sim.log"

grep -q "TB RESULT: PASS" "$OUT/sim.log"
echo "sim: OK"
