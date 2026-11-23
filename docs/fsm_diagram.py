#!/usr/bin/env python3
"""Draws the transmitter FSM of spi_master_tx to docs/images/fsm_tx.png."""
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch

OUT = Path(__file__).resolve().parent / 'images' / 'fsm_tx.png'
STATES = {  # name: (x, y, subtitle)
    'S_IDLE': (1.0, 3.0, 'SS_n=1\nSCLK=CPOL'),
    'S_SETUP': (4.0, 3.0, 'SS_n=0\nMOSI=MSB*'),
    'S_TRANSFER': (7.0, 3.0, '2N SCLK edges\nshift / sample'),
    'S_HOLD': (7.0, 0.6, 'SS_n=0\nSCLK=CPOL'),
    'S_DONE': (4.0, 0.6, 'SS_n=1\ndone=1'),
}
R = 0.78


def edge(a, b, label, rad=0.0, lx=0.0, ly=0.0):
    (x1, y1, _), (x2, y2, _) = STATES[a], STATES[b]
    arrow = FancyArrowPatch((x1, y1), (x2, y2), connectionstyle=f'arc3,rad={rad}', arrowstyle='-|>',
                            mutation_scale=18, lw=1.6, color='#1f3b73', shrinkA=R * 72 * 0.62, shrinkB=R * 72 * 0.62)
    ax.add_patch(arrow)
    ax.text((x1 + x2) / 2 + lx, (y1 + y2) / 2 + ly, label, ha='center', va='center', fontsize=9,
            bbox=dict(boxstyle='round,pad=0.25', fc='white', ec='#999999', lw=0.6))


def loop(name, label, dy):
    x, y, _ = STATES[name]
    sign = 1 if dy > 0 else -1
    arrow = FancyArrowPatch((x - 0.35, y + sign * R * 0.93), (x + 0.35, y + sign * R * 0.93),
                            connectionstyle=f'arc3,rad={-1.6 * sign}', arrowstyle='-|>', mutation_scale=14,
                            lw=1.3, color='#1f3b73')
    ax.add_patch(arrow)
    ax.text(x, y + dy, label, ha='center', va='center', fontsize=8.5, color='#333333')


fig, ax = plt.subplots(figsize=(10, 5.6), dpi=150)
for name, (x, y, sub) in STATES.items():
    ax.add_patch(Circle((x, y), R, fc='#eaf1fb', ec='#1f3b73', lw=2))
    ax.text(x, y + 0.2, name, ha='center', va='center', fontsize=9.5, weight='bold')
    ax.text(x, y - 0.25, sub, ha='center', va='center', fontsize=8)

edge('S_IDLE', 'S_SETUP', 'i_start=1\nlatch i_data', ly=0.35)
edge('S_SETUP', 'S_TRANSFER', 'tick\n(half-period)', ly=0.35)
edge('S_TRANSFER', 'S_HOLD', 'tick and\nedge_cnt = 2N', lx=0.85)
edge('S_HOLD', 'S_DONE', 'tick\nSS_n<=1, done<=1', ly=-0.62)
edge('S_DONE', 'S_IDLE', 'next clk', lx=-0.55, ly=-0.15)
loop('S_IDLE', 'i_start=0', 1.38)
loop('S_SETUP', 'tick=0', 1.38)
loop('S_TRANSFER', 'tick: SCLK toggles,\nedge_cnt+1', 1.5)
loop('S_HOLD', 'tick=0', -1.3)
ax.text(0.1, -1.35, 'any state: i_rst=1 -> S_IDLE      tick = last clk of an SCLK half-period (G_CLK_DIV cycles)\n'
        '* CPHA=0: MSB is put on MOSI when SS_n is asserted; CPHA=1: on the first SCLK edge', fontsize=8.5,
        color='#444444', va='center')
ax.set_xlim(-0.3, 8.6)
ax.set_ylim(-1.75, 4.9)
ax.set_aspect('equal')
ax.axis('off')
ax.set_title('spi_master_tx: transmitter FSM', fontsize=12, weight='bold')
OUT.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(OUT, bbox_inches='tight', facecolor='white')
print(f'saved {OUT}')
