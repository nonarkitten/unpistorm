// tb_ps_top.v - full Pi-facing path: ps_classic_slave -> pistorm_bridge -> chipram_model
module tb_ps_top (
    input clk, input rst_n,
    input ps_a0, input ps_a1, input ps_rd, input ps_wr, input ps_reset,
    input [15:0] ps_d_in,
    output [15:0] ps_d_out, output ps_d_oe, output ps_txn, output ps_ipl_zero
);
    wire req, we, uds_n, lds_n, ack; wire [23:1] addr; wire [15:0] wdata, rdata; wire [2:0] ipl;
    wire [23:1] cpu_address; wire [15:0] cpudata_in, cpu_data;
    wire _cpu_as,_cpu_uds,_cpu_lds,cpu_r_w,_cpu_dtack; wire [2:0] _cpu_ipl;

    ps_classic_slave u_slave(.clk(clk),.rst_n(rst_n),
        .ps_a0(ps_a0),.ps_a1(ps_a1),.ps_rd(ps_rd),.ps_wr(ps_wr),.ps_reset(ps_reset),
        .ps_d_in(ps_d_in),.ps_d_out(ps_d_out),.ps_d_oe(ps_d_oe),
        .ps_txn(ps_txn),.ps_ipl_zero(ps_ipl_zero),
        .req(req),.we(we),.uds_n(uds_n),.lds_n(lds_n),.addr(addr),.wdata(wdata),
        .ack(ack),.rdata(rdata),.ipl(ipl));
    pistorm_bridge u_brg(.clk(clk),.rst_n(rst_n),
        .req(req),.we(we),.uds_n(uds_n),.lds_n(lds_n),.addr(addr),.wdata(wdata),
        .ack(ack),.rdata(rdata),.ipl(ipl),
        .cpu_address(cpu_address),.cpudata_in(cpudata_in),.cpu_data(cpu_data),
        ._cpu_as(_cpu_as),._cpu_uds(_cpu_uds),._cpu_lds(_cpu_lds),.cpu_r_w(cpu_r_w),
        ._cpu_dtack(_cpu_dtack),._cpu_ipl(_cpu_ipl));
    chipram_model u_ram(.clk(clk),.cpu_address(cpu_address),.cpudata_in(cpudata_in),
        .cpu_data(cpu_data),._cpu_as(_cpu_as),._cpu_uds(_cpu_uds),._cpu_lds(_cpu_lds),
        .cpu_r_w(cpu_r_w),._cpu_dtack(_cpu_dtack),._cpu_ipl(_cpu_ipl));
endmodule
