// chipram_model.v - behavioural stand-in for the Minimig chipset CPU bus
// (chip-RAM region only) for isolated bring-up of pistorm_bridge.
// NOT cycle-accurate to Agnus DMA arbitration; it models only the async
// 68000 handshake (AS/DS -> DTACK) and byte-masked storage, which is all
// that is needed to validate the bridge's bus-master FSM and data path.
// SPDX-License-Identifier: GPL-3.0-or-later
module chipram_model #(parameter AWORDS = 13) ( // 2^13 words = 16 KB test region
    input             clk,
    input      [23:1] cpu_address,
    input      [15:0] cpudata_in,
    output reg [15:0] cpu_data,
    input             _cpu_as,
    input             _cpu_uds,
    input             _cpu_lds,
    input             cpu_r_w,
    output reg        _cpu_dtack,
    output     [2:0]  _cpu_ipl
);
    assign _cpu_ipl = 3'b111;             // no interrupts in this model
    reg [15:0] mem [0:(1<<AWORDS)-1];
    reg [1:0]  lat;
    wire [AWORDS-1:0] wa = cpu_address[AWORDS:1];
    always @(posedge clk) begin
        if (_cpu_as) begin
            _cpu_dtack <= 1'b1; lat <= 2'd0;
        end else if (lat != 2'd2) begin
            lat <= lat + 2'd1;
        end else begin
            _cpu_dtack <= 1'b0;           // ack a couple of cycles after AS
            if (cpu_r_w) cpu_data <= mem[wa];
            else begin
                if (!_cpu_uds) mem[wa][15:8] <= cpudata_in[15:8];
                if (!_cpu_lds) mem[wa][7:0]  <= cpudata_in[7:0];
            end
        end
    end
endmodule
