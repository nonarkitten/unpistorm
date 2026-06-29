// ----------------------------------------------------------------------------
// sim_main.cpp - simple Verilator testbench for the TG68KdotC_Kernel Verilog port
//
// Wraps the M68000 core in a zero-wait-state 16-bit memory, loads a tiny
// hand-assembled program, runs it, and checks the value the program stores
// back to memory. Run with VERBOSE=1 to dump every bus transaction.
//
// Bus interface of the core:
//   - busstate: 00=fetch, 10=read, 11=write, 01=internal (no bus access)
//   - data_in / data_write are 16 bit, big-endian; nUDS selects the even byte
//     (D15:8), nLDS the odd byte (D7:0).
//   - IPL is active low in the core (IPL_nr = ~IPL), so IPL=7 means "no IRQ".
//   - clkena_in advances the core. Here it is held high, modelling a memory
//     that completes every access in a single clock (zero wait states).
// ----------------------------------------------------------------------------

#include <verilated.h>
#include "VTG68KdotC_Kernel.h"
#include "VTG68KdotC_Kernel___024root.h"   // internal-signal access (--public-flat-rw)

#include <cstdio>
#include <cstdint>
#include <cstdlib>

static const uint32_t MEM_BYTES = 0x10000;   // 64 KiB
static uint8_t mem[MEM_BYTES];

static inline uint8_t rd8(uint32_t a)            { return mem[a & (MEM_BYTES - 1)]; }
static inline void    wr8(uint32_t a, uint8_t v) { mem[a & (MEM_BYTES - 1)] = v; }

// Lay down big-endian words/longs when building the program image.
static void poke16(uint32_t a, uint16_t v) { wr8(a, v >> 8); wr8(a + 1, v); }
static void poke32(uint32_t a, uint32_t v) { poke16(a, v >> 16); poke16(a + 2, v); }

static uint32_t peek32(uint32_t a) {
    return (rd8(a) << 24) | (rd8(a + 1) << 16) | (rd8(a + 2) << 8) | rd8(a + 3);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VTG68KdotC_Kernel* dut = new VTG68KdotC_Kernel;
    const bool verbose = getenv("VERBOSE") != nullptr;

    // ---- Program image -----------------------------------------------------
    // M68000 reset vectors. The program lives at PC_START (well away from the
    // vectors) so the very first fetch after reset reveals whether the PC was
    // actually loaded from the reset vector at address 4.
    const uint32_t PC_START = 0x0008;
    poke32(0x000, 0x00001000);                          // initial SSP = 0x1000
    poke32(0x004, PC_START);                            // initial PC  = 0x0400
    // Fill the gap between the vectors and the program with ILLEGAL (0x4AFC) so
    // a CPU that fails to load the reset PC cannot "NOP-slide" through zeroed
    // memory and accidentally reach PC_START -- only a real PC load gets there.
    for (uint32_t a = 0x008; a < PC_START; a += 2) poke16(a, 0x4AFC);
    // Program at PC_START:
    uint32_t p = PC_START;
    poke16(p, 0x303C); poke16(p + 2, 0xAABB);   p += 4; // move.w #$AABB,d0
    poke16(p, 0x31C0); poke16(p + 2, 0x0100);   p += 4; // move.w d0,($0100).W
    poke16(p, 0x223C); poke32(p + 2, 0x12345678); p += 6; // move.l #$12345678,d1
    poke16(p, 0x23C1); poke32(p + 2, 0x00000120); p += 6; // move.l d1,($0120).L
    poke16(p, 0x60FE);                                  // bra.s *  (spin)

    const uint32_t RESULT_ADDR = 0x0120;
    const uint32_t EXPECTED    = 0x12345678;

    // ---- Static inputs -----------------------------------------------------
    dut->clk            = 0;
    dut->nReset         = 0;     // assert reset (active low)
    dut->clkena_in      = 1;     // zero-wait-state memory: always enabled
    dut->data_in        = 0;
    dut->IPL            = 7;     // active low -> no interrupt
    dut->IPL_autovector = 0;
    dut->berr           = 0;
    dut->CPU            = 0;      // 00 -> 68000

    auto eval = [&]() { dut->eval(); };

    bool wrote_result   = false;
    bool reached_start  = false; // saw an instruction fetch at PC_START
    int  drain = -1;             // cycles to keep running after the result store
    const long MAX_CYCLES = 4000;

    for (long cyc = 0; cyc < MAX_CYCLES && !Verilated::gotFinish(); ++cyc) {
        if (cyc == 8) dut->nReset = 1;       // release reset after a few cycles

        // Settle combinational outputs for this cycle (clock low).
        dut->clk = 0;
        eval();

        uint32_t addr = dut->addr_out;
        uint8_t  bs   = dut->busstate;
        uint32_t even = addr & ~1u;
        uint32_t odd  = even | 1u;

        // Present read/fetch data, then let it propagate before the edge.
        if (bs == 0b00 || bs == 0b10)
            dut->data_in = (rd8(even) << 8) | rd8(odd);
        eval();

        if (dut->nReset) {
            if (verbose) {
                auto* r = dut->rootp;
                int longaktion = (r->TG68KdotC_Kernel__DOT__set[2] >> (73 - 64)) & 1;
                printf("  .[%4ld] bs=%d addr=%06X dwrite=%04X nUDS=%d nLDS=%d lw=%d | "
                       "dtype=%d set_dt=%d longakt=%d memmask=%02X memread=%X "
                       "setstate=%d ustate=%d->%d\n",
                       cyc, bs, addr, dut->data_write, dut->nUDS, dut->nLDS, dut->longword,
                       r->TG68KdotC_Kernel__DOT__datatype,
                       r->TG68KdotC_Kernel__DOT__set_datatype,
                       longaktion,
                       r->TG68KdotC_Kernel__DOT__memmask,
                       r->TG68KdotC_Kernel__DOT__memread,
                       r->TG68KdotC_Kernel__DOT__setstate,
                       r->TG68KdotC_Kernel__DOT__micro_state,
                       r->TG68KdotC_Kernel__DOT__next_micro_state);
                if (getenv("DP"))
                    printf("        dp: direct=%d use_dd=%d set_dd=%d nextpass=%d "
                           "regin=%08X OP1=%08X OP2=%08X ea_data=%08X ldr=%08X exe_dt=%d\n",
                           r->TG68KdotC_Kernel__DOT__direct_data,
                           r->TG68KdotC_Kernel__DOT__use_direct_data,
                           r->TG68KdotC_Kernel__DOT__set_direct_data,
                           r->TG68KdotC_Kernel__DOT__nextpass,
                           r->TG68KdotC_Kernel__DOT__regin,
                           r->TG68KdotC_Kernel__DOT__OP1out,
                           r->TG68KdotC_Kernel__DOT__OP2out,
                           r->TG68KdotC_Kernel__DOT__ea_data,
                           r->TG68KdotC_Kernel__DOT__last_data_read,
                           r->TG68KdotC_Kernel__DOT__exe_datatype);
            }

            if (bs == 0b11) {                            // write
                if (!dut->nUDS) wr8(even, dut->data_write >> 8);
                if (!dut->nLDS) wr8(odd,  dut->data_write & 0xFF);
                const char* lane = (!dut->nUDS && !dut->nLDS) ? "word"
                                 : (!dut->nUDS ? "high byte" : "low byte");
                printf("[%4ld] WRITE %06X <= %04X (%s)\n", cyc, addr, dut->data_write, lane);
                if (even == RESULT_ADDR || even == RESULT_ADDR + 2) wrote_result = true;
            } else if (bs == 0b00 || bs == 0b10) {       // fetch / read
                printf("[%4ld] %-5s %06X => %04X\n",
                       cyc, bs == 0b00 ? "FETCH" : "READ", addr, dut->data_in);
                // Require *sustained* execution from PC_START (fetch PC_START then
                // PC_START+2) so a single stray prefetch of PC_START is not
                // mistaken for the reset PC actually being loaded.
                if (bs == 0b00 && !reached_start) {
                    static uint32_t prev_fetch = 0xFFFFFFFF;
                    if (addr == PC_START + 2 && prev_fetch == PC_START) {
                        reached_start = true;
                        printf("       ^ executing from PC_START (reset PC loaded correctly)\n");
                    }
                    prev_fetch = addr;
                }
            }
        }

        // Rising edge: the core samples data_in and advances.
        dut->clk = 1;
        eval();

        if (wrote_result && peek32(RESULT_ADDR) == EXPECTED) {
            printf("\n[%4ld] expected result observed, stopping.\n", cyc);
            break;
        }
        // Once the program has stored to the result address, let any second
        // word of a long store land, then stop (the program then spins on bra).
        if (wrote_result && drain < 0) drain = 4;
        if (drain >= 0 && drain-- == 0) { printf("\n[%4ld] result stored, stopping.\n", cyc); break; }

        // If the reset PC is never loaded, the core just fetches its way through
        // memory forever -- bail out early instead of flooding the log.
        if (!reached_start && cyc > 120) {
            printf("\n[%4ld] PC never reached PC_START (0x%04X): reset vector load failed.\n",
                   cyc, PC_START);
            break;
        }
    }

    dut->final();
    delete dut;

    uint32_t got = peek32(RESULT_ADDR);
    printf("\nreset PC loaded : %s\n", reached_start ? "yes" : "NO");
    printf("mem[0x%04X]     = 0x%08X  (expected 0x%08X)\n", RESULT_ADDR, got, EXPECTED);
    if (got == EXPECTED) {
        printf("PASS\n");
        return 0;
    }
    if (!reached_start)
        printf("FAIL: reset vector loading is broken -- the 32-bit PC vector is not "
               "read in full / not loaded, so execution never reaches PC_START.\n");
    else
        printf("FAIL: core reached PC_START but the stored value is wrong.\n");
    return 1;
}
