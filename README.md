# Лабораторна робота № 3 — SPI master на VHDL

Розробка та верифікація послідовного комунікаційного протоколу на ПЛІС.
Варіант: **SPI, VHDL**.

| Компонент | Шлях |
|---|---|
| Передавач + генератор SCLK (FSM) | [`src/spi_master_tx.vhd`](src/spi_master_tx.vhd) |
| Приймач | [`src/spi_master_rx.vhd`](src/spi_master_rx.vhd) |
| Верхній модуль (full-duplex master) | [`src/spi_master.vhd`](src/spi_master.vhd) |
| Тестбенч (4 режими SPI, модель slave, монітор протоколу) | [`tb/tb_spi_master.vhd`](tb/tb_spi_master.vhd) |
| Симуляція | [`sim/run_sim.sh`](sim/run_sim.sh), вигляди GTKWave `sim/*.gtkw` |
| Опис протоколу, FSM | [`docs/design.md`](docs/design.md) |

## Інструменти
GHDL (VHDL-2008), GTKWave; для синтезу — Yosys + ghdl-yosys-plugin + nextpnr
(усе є в [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)).

## Запуск
```bash
export PATH=~/.local/opt/oss-cad-suite/bin:$PATH
./sim/run_sim.sh                                              # TB RESULT: PASS
gtkwave build/sim/tb_spi_master.ghw sim/waves_mode0.gtkw      # осцилограми режиму 0
```
