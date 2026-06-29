// ----------------------------------------------------------------------------
// TG68K_Pack.vh
// Translated from VHDL TG68K_Pack.vhd
//
// Copyright (c) 2009-2020 Tobias Gubener
// Patches by MikeJ, Till Harbaum, Rok Krajnk, ...
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// ----------------------------------------------------------------------------

`ifndef TG68K_PACK_VH
`define TG68K_PACK_VH

// micro_states encoding (7 bits, 91 states)
`define ms_idle         7'd0
`define ms_nop          7'd1
`define ms_ld_nn        7'd2
`define ms_st_nn        7'd3
`define ms_ld_dAn1      7'd4
`define ms_ld_AnXn1     7'd5
`define ms_ld_AnXn2     7'd6
`define ms_st_dAn1      7'd7
`define ms_ld_AnXnbd1   7'd8
`define ms_ld_AnXnbd2   7'd9
`define ms_ld_AnXnbd3   7'd10
`define ms_ld_229_1     7'd11
`define ms_ld_229_2     7'd12
`define ms_ld_229_3     7'd13
`define ms_ld_229_4     7'd14
`define ms_st_229_1     7'd15
`define ms_st_229_2     7'd16
`define ms_st_229_3     7'd17
`define ms_st_229_4     7'd18
`define ms_st_AnXn1     7'd19
`define ms_st_AnXn2     7'd20
`define ms_bra1         7'd21
`define ms_bsr1         7'd22
`define ms_bsr2         7'd23
`define ms_nopnop       7'd24
`define ms_dbcc1        7'd25
`define ms_movem1       7'd26
`define ms_movem2       7'd27
`define ms_movem3       7'd28
`define ms_andi         7'd29
`define ms_pack1        7'd30
`define ms_pack2        7'd31
`define ms_pack3        7'd32
`define ms_op_AxAy      7'd33
`define ms_cmpm         7'd34
`define ms_link1        7'd35
`define ms_link2        7'd36
`define ms_unlink1      7'd37
`define ms_unlink2      7'd38
`define ms_int1         7'd39
`define ms_int2         7'd40
`define ms_int3         7'd41
`define ms_int4         7'd42
`define ms_rte1         7'd43
`define ms_rte2         7'd44
`define ms_rte3         7'd45
`define ms_rte4         7'd46
`define ms_rte5         7'd47
`define ms_rtd1         7'd48
`define ms_rtd2         7'd49
`define ms_trap00       7'd50
`define ms_trap0        7'd51
`define ms_trap1        7'd52
`define ms_trap2        7'd53
`define ms_trap3        7'd54
`define ms_cas1         7'd55
`define ms_cas2         7'd56
`define ms_cas21        7'd57
`define ms_cas22        7'd58
`define ms_cas23        7'd59
`define ms_cas24        7'd60
`define ms_cas25        7'd61
`define ms_cas26        7'd62
`define ms_cas27        7'd63
`define ms_cas28        7'd64
`define ms_chk20        7'd65
`define ms_chk21        7'd66
`define ms_chk22        7'd67
`define ms_chk23        7'd68
`define ms_chk24        7'd69
`define ms_trap4        7'd70
`define ms_trap5        7'd71
`define ms_trap6        7'd72
`define ms_movec1       7'd73
`define ms_movep1       7'd74
`define ms_movep2       7'd75
`define ms_movep3       7'd76
`define ms_movep4       7'd77
`define ms_movep5       7'd78
`define ms_rota1        7'd79
`define ms_bf1          7'd80
`define ms_mul1         7'd81
`define ms_mul2         7'd82
`define ms_mul_end1     7'd83
`define ms_mul_end2     7'd84
`define ms_div1         7'd85
`define ms_div2         7'd86
`define ms_div3         7'd87
`define ms_div4         7'd88
`define ms_div_end1     7'd89
`define ms_div_end2     7'd90

// exec bit indices (used to index into exec[88:0])
`define opcMOVE         0
`define opcMOVEQ        1
`define opcMOVESR       2
`define opcADD          3
`define opcADDQ         4
`define opcOR           5
`define opcAND          6
`define opcEOR          7
`define opcCMP          8
`define opcROT          9
`define opcCPMAW        10
`define opcEXT          11
`define opcABCD         12
`define opcSBCD         13
`define opcBITS         14
`define opcSWAP         15
`define opcScc          16
`define andiSR          17
`define eoriSR          18
`define oriSR           19
`define opcMULU         20
`define opcDIVU         21
`define dispouter       22
`define rot_nop         23
`define ld_rot_cnt      24
`define writePC_add     25
`define ea_data_OP1     26
`define ea_data_OP2     27
`define use_XZFlag      28
`define get_bfoffset    29
`define save_memaddr    30
`define opcCHK          31
`define movec_rd        32
`define movec_wr        33
`define Regwrena        34
`define update_FC       35
`define linksp          36
`define movepl          37
`define update_ld       38
`define OP1addr         39
`define write_reg       40
`define changeMode      41
`define ea_build        42
`define trap_chk        43
`define store_ea_data   44
`define addrlong        45
`define postadd         46
`define presub          47
`define subidx          48
`define no_Flags        49
`define use_SP          50
`define to_CCR          51
`define to_SR           52
`define OP2out_one      53
`define OP1out_zero     54
`define mem_addsub      55
`define addsub          56
`define directPC        57
`define direct_delta    58
`define directSR        59
`define directCCR       60
`define exg             61
`define get_ea_now      62
`define ea_to_pc        63
`define hold_dwr        64
`define to_USP          65
`define from_USP        66
`define write_lowlong   67
`define write_reminder  68
`define movem_action    69
`define briefext        70
`define get_2ndOPC      71
`define mem_byte        72
`define longaktion      73
`define opcRESET        74
`define opcBF           75
`define opcBFwb         76
`define opcPACK         77
`define opcUNPACK       78
`define hold_ea_data    79
`define store_ea_packdata 80
`define exec_BS         81
`define hold_OP2        82
`define restore_ADDR    83
`define alu_exec        84
`define alu_move        85
`define alu_setFlags    86
`define opcCHK2         87
`define opcEXTB         88

`define lastOpcBit      88

`endif // TG68K_PACK_VH
