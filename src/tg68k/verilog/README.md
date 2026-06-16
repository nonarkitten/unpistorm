# TG68k Verilog

This is an _incomplete_ attempt to use AI to convert the VHDL TG68K to
Verilog. The main objective of this is to run tg68k in verilator as
part of a full verilator simulation of NanoMig.  The current
simulation uses a [Verilog variant of tg68k which has been converted
to Verilog using an automated tool](../../../sim/TG68KdotC_Kernel.v).

The tool converted version does indeed work but is not human-readable
and is not suited to actually work on the code. The AI generated
variant looks much cleaner and would be a candidate for further
work. But it does not work properly. The AI generated version also
includes a AI generated verilator test bench. This allows the AI to
test the generated code itself. However, the test bench is currently
very simple and while it passes the tests its intended to run, the
NanoMig malfunctions within the first instruction executed when using
this core.

Further work on this might:

- extend the test bench
- fix the Verilog tg68k to a point where it can run AmigaOS again
- comment the code
- refactor the code foe simplicity, readability, ...
- ...
