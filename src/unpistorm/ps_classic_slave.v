// ps_classic_slave.v - Pi-facing front-end for Un-PiStorm.
//
// Emulates the SLAVE side of the *classic* PiStorm GPIO protocol (the one with
// no Pi-side FPGA flashing), so Emu68/Musashi on a Pi 4 think they are talking
// to a normal PiStorm. Decodes the 4 multiplexed registers, assembles the
// access, and hands it to pistorm_bridge over the abstract request interface.
//
// Protocol decoded from michalsc/Emu68 src/pistorm/ps_classic_protocol.c +
// ps_protocol.h (pin map). All Pi GPIO are async to clk and are synchronised.
//
// Pin map (Pi BCM GPIO): A0=2 A1=3 RESET=5 RD=6 WR=7 D0..15=8..23,
//   TXN_IN_PROGRESS=0 (out), IPL_ZERO=1 (out). Registers: 0 DATA 1 ADDR_LO
//   2 ADDR_HI 3 STATUS. STATUS[15:13]=IPL, [1]=reset, [0]=init.
//
// The bidirectional data bus is split here (ps_d_in / ps_d_out / ps_d_oe);
// the actual inout tristate lives at the board top.
//
// SPDX-License-Identifier: GPL-3.0-or-later
module ps_classic_slave (
    input             clk,         // chipset bus clock domain
    input             rst_n,
    // ---- Pi-facing GPIO (asynchronous) ----
    input             ps_a0,
    input             ps_a1,
    input             ps_rd,
    input             ps_wr,
    input             ps_reset,
    input      [15:0] ps_d_in,
    output     [15:0] ps_d_out,
    output            ps_d_oe,
    output            ps_txn,       // TXN_IN_PROGRESS (high while busy)
    output            ps_ipl_zero,  // high when IPL == 0
    // ---- bridge request interface ----
    output reg        req,
    output reg        we,
    output reg        uds_n,
    output reg        lds_n,
    output reg [23:1] addr,
    output reg [15:0] wdata,
    input             ack,
    input      [15:0] rdata,
    input       [2:0] ipl
);
    localparam REG_DATA = 2'd0, REG_ADDR_LO = 2'd1, REG_ADDR_HI = 2'd2, REG_STATUS = 2'd3;

    // ---- synchronise async Pi strobes/levels into clk ----
    reg [2:0] wr_s, rd_s;
    reg [1:0] a_s0, a_s1;
    reg [1:0] rst_s;
    reg [15:0] d_s0, d_s1;
    always @(posedge clk) begin
        wr_s <= {wr_s[1:0], ps_wr};
        rd_s <= {rd_s[1:0], ps_rd};
        a_s0 <= {a_s0[0], ps_a0};
        a_s1 <= {a_s1[0], ps_a1};
        rst_s <= {rst_s[0], ps_reset};
        d_s0 <= ps_d_in; d_s1 <= d_s0;     // 2-FF on data bus
    end
    wire wr_rise = (wr_s[2:1] == 2'b01);
    wire [1:0] reg_sel = {a_s1[1], a_s0[1]};
    wire rd_active = rd_s[1];

    // ---- latched protocol registers ----
    reg [15:0] addr_lo;
    reg  [7:0] addr_hi;
    reg  [7:0] type_b;
    reg [15:0] rd_data_reg;

    // ---- slave FSM ----
    localparam S_IDLE = 1'b0, S_BUSY = 1'b1;
    reg state;
    reg busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; req <= 1'b0;
            we <= 1'b0; uds_n <= 1'b1; lds_n <= 1'b1; addr <= 0; wdata <= 0;
            addr_lo <= 0; addr_hi <= 0; type_b <= 0; rd_data_reg <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    req <= 1'b0;
                    if (wr_rise) begin
                        case (reg_sel)
                            REG_DATA:    wdata   <= d_s1;
                            REG_ADDR_LO: addr_lo <= d_s1;
                            REG_ADDR_HI: begin
                                addr_hi <= d_s1[7:0];
                                type_b  <= d_s1[15:8];
                                // assemble + launch the access.
                                // full byte addr = {d_s1[7:0], addr_lo}; addr[23:1] drops bit0.
                                addr  <= {d_s1[7:0], addr_lo[15:1]};
                                we    <= ~d_s1[9];           // type bit1 (read) -> we=0
                                // byte/word strobes (type bit0 = byte)
                                if (d_s1[8]) begin           // byte
                                    uds_n <= addr_lo[0] ? 1'b1 : 1'b0;
                                    lds_n <= addr_lo[0] ? 1'b0 : 1'b1;
                                end else begin               // word
                                    uds_n <= 1'b0; lds_n <= 1'b0;
                                end
                                req   <= 1'b1;
                                busy  <= 1'b1;
                                state <= S_BUSY;
                            end
                            default: ; // STATUS write: ignored
                        endcase
                    end
                end
                S_BUSY: begin
                    if (ack) begin
                        rd_data_reg <= rdata;
                        req   <= 1'b0;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- data bus drive (only while the Pi is reading) ----
    wire [15:0] status_word = {ipl, 11'b0, rst_s[1], 1'b1}; // [15:13]=ipl [1]=reset [0]=init
    assign ps_d_out = (reg_sel == REG_STATUS) ? status_word : rd_data_reg;
    assign ps_d_oe  = rd_active;
    assign ps_txn   = busy;
    assign ps_ipl_zero = (ipl == 3'b000);
endmodule
