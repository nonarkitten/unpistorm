# Un-PiStorm

**An ECS Amiga chipset on a Sipeed Tang Nano 20K that presents itself to a
Raspberry Pi 400 running Emu68 as if it were a real Amiga's custom chips.**
The Pi is the 68k CPU (and Kickstart + fast RAM); the FPGA is Agnus/Denise/
Paula/Gary + the CIAs. HDMI out, USB HID in. The inverse of a normal PiStorm:
no real Amiga, the FPGA *is* the chipset.

> **Status:** Pi-facing path is built and green in Verilator. `ps_classic_slave`
> + `pistorm_bridge` decode the classic PiStorm protocol end-to-end and pass an
> Emu68-style `buptest` (word + byte, UDS/LDS masking, TXN handshake) driven by
> a C++ model of the Pi. Not yet grafted into the live `minimig.v`, and not yet
> run on real hardware. The 9K remains a stretch goal, not a promise.

---

## 1. This is a fork of NanoMig

Un-PiStorm is an overlay on **MiSTle-Dev/NanoMig** (GPLv3). It deletes the
TG68/fx68k softcore (`cpu_wrapper`) and feeds Minimig's CPU bus from the Pi
instead.

---

## 2. Architecture

```
   Raspberry Pi 400 (BCM2711):  Emu68 68k JIT | Kickstart maprom | Z2/Z3 fast RAM | PiSCSI HD
        |  classic PiStorm GPIO bus: 16b data (mux), A0/A1, RD/WR, RESET, TXN, IPL_ZERO
   ===== 40-pin header ==========================================================
   Tang Nano 20K (GW2AR-18)
     ps_classic_slave  --req/ack/ipl-->  pistorm_bridge  --cpu_* 68000 bus-->  MINIMIG ECS
        (GPIO decode,                     (AS/DS/DTACK,                          Agnus Denise
         TXN handshake)                    IPL back to Pi)                       Paula Gary CIAx
                                                                                   |    |    |
                                                          chip DMA <-> 8MB SDRAM (CHIP RAM)
                                                          pixel -> scandouble + Amber bright/dim -> TMDS HDMI
                                                          Paula -> sigmadelta 1b -> decimate -> HDMI LPCM
     FPGA-Companion MCU (BL616/M0S) -- USB HID --> injects kbd/mouse/pad into CIA/Denise regs
   SPI flash holds the bitstream only; loaded at power-on. The Pi never reprograms the FPGA.
```

---

## 3. What changed vs. NanoMig

| NanoMig | Un-PiStorm |
|---|---|
| TG68/fx68k softcore (`cpu_wrapper`) | **deleted** — the Pi is the CPU via `pistorm_bridge` |
| Fast RAM / floppy / IDE / Kick ROM in FPGA | **dropped** — Emu68 provides all of these on the Pi |
| Dimming scanlines | energy-preserving bright/dim pair (avg = original) |
| HDMI audio from internal mix | Paula 1-bit `sigmadelta` → decimate → 16-bit LPCM |
| USB HID via FPGA-Companion | **kept** (same SPI companion path) |
| SDRAM chip-RAM controller | **kept** — solves Amiga-timed chip RAM on the 20K |

---

## 4. Pinout — Pi 400 (BCM2711) ↔ Tang Nano 20K

Both sides are 3.3 V LVCMOS, so **no level shifting** — wire directly, keep the
ribbon short, add small series resistors on RD/WR/CLK, and tie several grounds.
The classic protocol clocks off the RD/WR edges; CLK is routed but largely
unused by the classic variant.

**Pi side is fixed** by the protocol + the Pi 40-pin header (J8):

| Signal | BCM | Pi pin | | Signal | BCM | Pi pin |
|---|---|---|---|---|---|---|
| TXN_IN_PROGRESS (FPGA→Pi) | 0 | 27 | | D4 | 12 | 32 |
| IPL_ZERO (FPGA→Pi) | 1 | 28 | | D5 | 13 | 33 |
| A0 | 2 | 3 | | D6 | 14 | 8 |
| A1 | 3 | 5 | | D7 | 15 | 10 |
| CLK | 4 | 7 | | D8 | 16 | 36 |
| RESET | 5 | 29 | | D9 | 17 | 11 |
| RD | 6 | 31 | | D10 | 18 | 12 |
| WR | 7 | 26 | | D11 | 19 | 35 |
| D0 | 8 | 24 | | D12 | 20 | 38 |
| D1 | 9 | 21 | | D13 | 21 | 40 |
| D2 | 10 | 19 | | D14 | 22 | 15 |
| D3 | 11 | 23 | | D15 | 23 | 16 |

GND: Pi pins 6, 9, 14, 20, 25, 30, 34, 39 (use several). The Pi data bus is a
fixed *scattered* permutation of header pins — the carrier PCB sorts it out.

**Tang side**, grounded in NanoMig's freed header pins (Gowin pin numbers).
D0–D15 land on the DB9/MIDI/buzzer pins freed by going USB:

```
D0=25  D1=26  D2=27  D3=28  D4=29  D5=30  D6=31  D7=49
D8=52  D9=53 D10=71 D11=72 D12=73 D13=74 D14=77 D15=88
```

The 8 control lines (TXN, IPL_ZERO, A0, A1, CLK, RESET, RD, WR) go on free
header GPIO. They're marked TODO in `unpistorm.cst`.

---

## 5. Build, simulate, program

Simulate (no hardware):
```
cd sim
verilator --cc --exe --build -I../src/unpistorm -I. \
  ps_buptest.cpp ../src/unpistorm/ps_classic_slave.v ../src/unpistorm/pistorm_bridge.v \
  chipram_model.v tb_ps_top.v --top-module tb_ps_top -o ps_buptest
./obj_dir/ps_buptest     # expect: "ps_buptest: 4416 checks, 0 errors -> PASS"
```
(`buptest` / `tb_top.v` is the same for the bridge in isolation.)

Synthesize + program (open toolchain): unchanged from NanoMig's flow —
yosys + nextpnr-himbaechel-gowin + apicula, or Gowin EDA. Program the bitstream
to SPI flash with `openFPGALoader -b tangnano20k -f unpistorm.fs`. USB HID +
OSD come from FPGA-Companion on the BL616/M0S, exactly as NanoMig.

---

## 6. Software on the Pi

Target is the **classic** PiStorm protocol (no Pi-side FPGA flashing — required,
since our bitstream self-loads from flash). It runs with either Pi stack:

- **Emu68** (fast, bare-metal): HDD via PiSCSI; networking only via `genet` +
  Roadshow on the Pi 4. No A314 `a314fs`/`pi` (those need Linux). USB HID is
  handled by our companion MCU through the real Amiga input path, so kbd/mouse
  work under Kickstart regardless of Emu68's own lack of a USB HID driver.
- **Musashi** (slower, stale): full A314 — `a314fs`/`PiDisk:`, the `pi` command,
  the experimental bsdsocket bridge.

Either way it's a Pi-side choice and is transparent to the FPGA. Pi 400 = Pi 4;
the Pi 500/500+ are Pi 5 (RP1 GPIO) and Emu68/PiStorm do not run there.

---

## 7. Milestones

1. [done] `pistorm_bridge` (replaces cpu_wrapper) + Emu68-style buptest.
2. [done] `ps_classic_slave` (classic protocol) + full Pi-path buptest.
3. Graft into live `minimig.v` (phase-accurate cpu_ph1/ph2/clk7_en, DMA contention).
4. Real Pi 400 hardware: pass Emu68 buptest, boot to PiSCSI HD.
5. Amber bright/dim scanlines + 1-bit→LPCM HDMI audio.
6. Attempt the 9K squeeze.

## 8. Attribution & license
GPL-3.0-or-later. Stands on: Minimig (Dennis van Weeren, +JB/SB/TF/AMR),
MiSTer Minimig, NanoMig (MiSTle-Dev), MiSTeryNano/FPGA-Companion (Till Harbaum),
PiStorm (Claude Schwarz), Emu68 (Michal Schulz). Amber scanline rework and
PDM+PWM audio integration by Renee (nonarkitten). See per-file headers.
