// tb_top.v - wires pistorm_bridge to the chip-RAM model for Verilator.
module tb_top (
    input clk, input rst_n,
    input req, input we, input uds_n, input lds_n,
    input [23:1] addr, input [15:0] wdata,
    output ack, output [15:0] rdata, output [2:0] ipl
);
    wire [23:1] cpu_address; wire [15:0] cpudata_in, cpu_data;
    wire _cpu_as,_cpu_uds,_cpu_lds,cpu_r_w,_cpu_dtack; wire [2:0] _cpu_ipl;
    pistorm_bridge u_brg(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.uds_n(uds_n),
        .lds_n(lds_n),.addr(addr),.wdata(wdata),.ack(ack),.rdata(rdata),.ipl(ipl),
        .cpu_address(cpu_address),.cpudata_in(cpudata_in),.cpu_data(cpu_data),
        ._cpu_as(_cpu_as),._cpu_uds(_cpu_uds),._cpu_lds(_cpu_lds),.cpu_r_w(cpu_r_w),
        ._cpu_dtack(_cpu_dtack),._cpu_ipl(_cpu_ipl));
    chipram_model u_ram(.clk(clk),.cpu_address(cpu_address),.cpudata_in(cpudata_in),
        .cpu_data(cpu_data),._cpu_as(_cpu_as),._cpu_uds(_cpu_uds),._cpu_lds(_cpu_lds),
        .cpu_r_w(cpu_r_w),._cpu_dtack(_cpu_dtack),._cpu_ipl(_cpu_ipl));
endmodule
