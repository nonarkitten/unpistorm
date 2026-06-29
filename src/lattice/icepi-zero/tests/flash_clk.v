// https://0x04.net/~mwk/doc/lattice/ecp5/FPGA-TN-02039-2-3-ECP5-and-ECP5-5G-sysCONFIG.pdf

// openFPGALoader -cft231X --pins=7:3:5:6 impl/flash_clk_impl.bit 

module USRMCLK (USRMCLKI, USRMCLKTS);
input USRMCLKI, USRMCLKTS;
endmodule

module top(
  input         clk,
  output [4:0]  leds
);
  
// run reset counter @ 50 Mhz
reg [31:0] reset_cnt;
always @(posedge clk)
	if(reset_cnt < 32'hffffffff)
		reset_cnt <= reset_cnt + 32'd1;

// generate one short positive reset pulse after startup
wire reset = reset_cnt > 32'd1_000 && reset_cnt < 32'd100_000;
assign leds[1] = reset;

// just some free running counter to generate test signals
reg [31:0] counter;
always @(posedge clk)
	counter <= counter + 32'd1;
  
assign leds[0] = counter[22];

USRMCLK usrmclk (
 .USRMCLKI(counter[10]),
 .USRMCLKTS(reset)   // 0 = drive clock, this cannot be a constant!
)/* synthesis syn_noprune = 1 */;

endmodule
