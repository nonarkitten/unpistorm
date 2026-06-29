// pistorm_bridge.v - chipset-facing 68000 bus master for Un-PiStorm.
//
// Replaces NanoMig's `cpu_wrapper` (TG68/fx68k softcore). Instead of an
// internal CPU, accesses arrive from the Pi-facing PiStorm GPIO front-end
// over the abstract request interface below, and are turned into cycles on
// the Minimig chipset's asynchronous 68000 bus (minimig.v cpu_* signals).
//
// SCOPE: chipset-facing half only -- this is PROTOCOL-INDEPENDENT and is what
// the buptest bench exercises. The Pi-facing GPIO decoder is a separate module
// whose pin map depends on the chosen Emu68/PiStorm variant (TBD per host).
//
// Bus contract taken verbatim from NanoMig minimig.v:
//   cpu_address[23:1], cpudata_in[15:0] (CPU->chip), cpu_data[15:0] (chip->CPU),
//   _cpu_as,_cpu_uds,_cpu_lds (active low), cpu_r_w (1=read), _cpu_dtack, _cpu_ipl.
//
// SPDX-License-Identifier: GPL-3.0-or-later
module pistorm_bridge (
    input             clk,
    input             rst_n,
    // ---- abstract request interface (from Pi-facing front-end) ----
    input             req,        // start an access (held until ack)
    input             we,         // 1 = write, 0 = read
    input             uds_n,      // requested upper data strobe (active low)
    input             lds_n,      // requested lower data strobe (active low)
    input      [23:1] addr,
    input      [15:0] wdata,
    output reg        ack,        // 1-cycle completion strobe
    output reg [15:0] rdata,
    output reg  [2:0] ipl,        // active-high IPL handed back to the Pi
    // ---- Minimig chipset 68000 bus ----
    output reg [23:1] cpu_address,
    output reg [15:0] cpudata_in,
    input      [15:0] cpu_data,
    output reg        _cpu_as,
    output reg        _cpu_uds,
    output reg        _cpu_lds,
    output reg        cpu_r_w,
    input             _cpu_dtack,
    input       [2:0] _cpu_ipl
);
    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_TERM = 2'd2;
    reg [1:0] state;

    always @(posedge clk) ipl <= ~_cpu_ipl;   // bus IPL is active-low

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; _cpu_as <= 1'b1; _cpu_uds <= 1'b1; _cpu_lds <= 1'b1;
            cpu_r_w <= 1'b1; cpu_address <= 0; cpudata_in <= 0; rdata <= 0; ack <= 1'b0;
        end else begin
            ack <= 1'b0;
            case (state)
                S_IDLE: if (req) begin
                    cpu_address <= addr;
                    cpu_r_w     <= ~we;
                    cpudata_in  <= wdata;
                    _cpu_as     <= 1'b0;
                    _cpu_uds    <= uds_n;
                    _cpu_lds    <= lds_n;
                    state       <= S_WAIT;
                end
                S_WAIT: if (!_cpu_dtack) begin
                    if (cpu_r_w) rdata <= cpu_data;
                    state <= S_TERM;
                end
                S_TERM: begin
                    _cpu_as <= 1'b1; _cpu_uds <= 1'b1; _cpu_lds <= 1'b1;
                    ack <= 1'b1; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
