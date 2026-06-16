// ----------------------------------------------------------------------------
// TG68K_ALU.v
// Translated from VHDL TG68K_ALU.vhd
//
// Copyright (c) 2009-2020 Tobias Gubener
// Patches by MikeJ, Till Harbaum, Rok Krajnk, ...
// Subdesign fAMpIGA by TobiFlex
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// ----------------------------------------------------------------------------

`include "TG68K_Pack.vh"

module TG68K_ALU #(
    parameter MUL_Mode      = 0,  // 0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL
    parameter MUL_Hardware  = 0,  // 0=>no, 1=>yes
    parameter DIV_Mode      = 0,  // 0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV
    parameter BarrelShifter = 0   // 0=>no, 1=>yes, 2=>switchable with CPU(1)
)(
    input         clk,
    input         Reset,
    input  [1:0]  CPU,
    input         clkena_lw,
    input         execOPC,
    input         decodeOPC,
    input         exe_condition,
    input         exec_tas,
    input         long_start,
    input         non_aligned,
    input         check_aligned,
    input         movem_presub,
    input         set_stop,
    input         Z_error,
    input  [1:0]  rot_bits,
    input  [88:0] exec,
    input  [31:0] OP1out,
    input  [31:0] OP2out,
    input  [31:0] reg_QA,
    input  [31:0] reg_QB,
    input  [15:0] opcode,
    input  [15:0] exe_opcode,
    input  [1:0]  exe_datatype,
    input  [15:0] sndOPC,
    input  [15:0] last_data_read,
    input  [15:0] data_read,
    input  [7:0]  FlagsSR,
    input  [6:0]  micro_state,
    input  [7:0]  bf_ext_in,
    output reg [7:0]  bf_ext_out,
    input  [5:0]  bf_shift,
    input  [5:0]  bf_width,
    input  [31:0] bf_ffo_offset,
    input  [4:0]  bf_loffset,

    output reg    set_V_Flag,
    output reg [7:0]  Flags,
    output reg [2:0]  c_out,
    output reg [31:0] addsub_q,
    output reg [31:0] ALUout
);

    // Internal signals
    reg  [31:0] OP1in;
    reg  [31:0] addsub_a;
    reg  [31:0] addsub_b;
    reg  [33:0] notaddsub_b;
    reg  [33:0] add_result;
    reg  [2:0]  addsub_ofl;
    reg         opaddsub;
    reg  [3:0]  c_in;
    reg  [2:0]  flag_z;
    reg  [3:0]  set_Flags;   // NZVC
    reg  [7:0]  CCRin;
    reg  [3:0]  last_Flags1; // NZVC

    // BCD
    reg  [9:0]  bcd_pur;
    reg  [8:0]  bcd_kor;
    reg         halve_carry;
    reg         Vflag_a;
    reg         bcd_a_carry;
    reg  [8:0]  bcd_a;
    reg  [127:0] result_mulu;
    reg  [63:0] result_div;
    reg  [31:0] result_div_pre;
    reg         set_mV_Flag;
    reg         V_Flag;

    reg         rot_rot;
    reg         rot_lsb;
    reg         rot_msb;
    reg         rot_X;
    reg         rot_C;
    reg  [31:0] rot_out;
    reg         asl_VFlag;
    reg  [1:0]  bit_bits;
    reg  [4:0]  bit_number;
    reg  [31:0] bits_out;
    reg         one_bit_in;
    reg         bchg;
    reg         bset;

    reg         mulu_sign;
    reg  [16:0] mulu_signext;
    reg         muls_msb;
    reg  [63:0] mulu_reg;
    reg         FAsign;
    reg  [31:0] faktorA;
    reg  [31:0] faktorB;

    reg  [63:0] div_reg;
    reg  [63:0] div_quot;
    reg         div_ovl;
    reg         div_neg;
    reg         div_bit;
    reg  [32:0] div_sub;
    reg  [32:0] div_over;
    reg         nozero;
    reg         div_qsign;
    reg  [63:0] dividend;
    reg         divs;
    reg         signedOP;
    reg         OP1_sign;
    reg         OP2_sign;
    reg  [15:0] OP2outext;

    reg  [5:0]  in_offset;
    reg  [31:0] datareg;
    reg  [31:0] insert;
    reg  [31:0] bf_datareg;
    reg  [39:0] result;
    reg  [39:0] result_tmp;
    reg  [31:0] unshifted_bitmask;
    reg  [39:0] bf_set1;
    reg  [39:0] inmux0;
    reg  [39:0] inmux1;
    reg  [39:0] inmux2;
    reg  [31:0] inmux3;
    reg  [39:0] shifted_bitmask;
    reg  [37:0] bitmaskmux0;
    reg  [35:0] bitmaskmux1;
    reg  [31:0] bitmaskmux2;
    reg  [31:0] bitmaskmux3;
    reg  [31:0] bf_set2;
    reg  [39:0] shift_bf;
    reg  [5:0]  bf_firstbit;
    reg  [3:0]  mux;
    reg  [4:0]  bitnr;
    reg  [31:0] mask;
    reg         mask_not_zero;
    reg         bf_bset;
    reg         bf_NFlag;
    reg         bf_bchg;
    reg         bf_ins;
    reg         bf_exts;
    reg         bf_fffo;
    reg         bf_d32;
    reg         bf_s32;
    reg  [4:0]  index;

    reg  [33:0] hot_msb;
    reg  [32:0] vector;
    reg  [65:0] result_bs;
    reg  [5:0]  bit_nr;
    reg  [5:0]  bit_msb;
    reg  [5:0]  bs_shift;
    reg  [5:0]  bs_shift_mod;
    reg  [32:0] asl_over;
    reg  [32:0] asl_over_xor;
    reg  [32:0] asr_sign;
    reg         msb;
    reg  [5:0]  ring;
    reg  [31:0] ALU;
    reg  [31:0] BSout;
    reg         bs_V;
    reg         bs_C;
    reg         bs_X;

    integer i;

    // -------------------------------------------------------------------------
    // set OP1in / ALUout
    // -------------------------------------------------------------------------
    always @(*) begin
        ALUout    = OP1in;
        ALUout[7] = OP1in[7] | exec_tas;
        if (exec[`opcBFwb]) begin
            ALUout = result[31:0];
            if (bf_fffo)
                ALUout = bf_ffo_offset - {26'b0, bf_firstbit};
        end

        OP1in = addsub_q;
        if (exec[`opcABCD] | exec[`opcSBCD]) begin
            OP1in[7:0] = bcd_a[7:0];
        end else if (exec[`opcMULU] && MUL_Mode != 3) begin
            if (MUL_Hardware == 0) begin
                if (exec[`write_lowlong] && (MUL_Mode == 1 || MUL_Mode == 2))
                    OP1in = result_mulu[31:0];
                else
                    OP1in = result_mulu[63:32];
            end else begin
                if (exec[`write_lowlong])
                    OP1in = result_mulu[31:0];
                else
                    OP1in = mulu_reg[31:0];
            end
        end else if (exec[`opcDIVU] && DIV_Mode != 3) begin
            if (exe_opcode[15] || DIV_Mode == 0) begin
                OP1in = {result_div[47:32], result_div[15:0]}; // word
            end else begin // 64-bit
                if (exec[`write_reminder])
                    OP1in = result_div[63:32];
                else
                    OP1in = result_div[31:0];
            end
        end else if (exec[`opcOR]) begin
            OP1in = OP2out | OP1out;
        end else if (exec[`opcAND]) begin
            OP1in = OP2out & OP1out;
        end else if (exec[`opcScc]) begin
            OP1in[7:0] = {8{exe_condition}};
        end else if (exec[`opcEOR]) begin
            OP1in = OP2out ^ OP1out;
        end else if (exec[`alu_move]) begin
            OP1in = OP2out;
        end else if (exec[`opcROT]) begin
            OP1in = rot_out;
        end else if (exec[`exec_BS]) begin
            OP1in = BSout;
        end else if (exec[`opcSWAP]) begin
            OP1in = {OP1out[15:0], OP1out[31:16]};
        end else if (exec[`opcBITS]) begin
            OP1in = bits_out;
        end else if (exec[`opcBF]) begin
            OP1in = bf_datareg;
        end else if (exec[`opcMOVESR]) begin
            OP1in[7:0] = Flags;
            if (exe_opcode[9])
                OP1in[15:8] = 8'h00;
            else
                OP1in[15:8] = FlagsSR;
        end else if (exec[`opcPACK]) begin
            OP1in[7:0] = {addsub_q[11:8], addsub_q[3:0]};
        end
    end

    // -------------------------------------------------------------------------
    // addsub
    // -------------------------------------------------------------------------
    always @(*) begin
        addsub_a = OP1out;
        if (exec[`get_bfoffset]) begin
            if (sndOPC[11])
                addsub_a = {{4{OP1out[31]}}, OP1out[31:3]};
            else
                addsub_a = {30'b0, sndOPC[10:9]};
        end

        opaddsub = exec[`subidx] ? 1'b1 : 1'b0;

        c_in[0] = 1'b0;
        addsub_b = OP2out;
        if (exec[`opcUNPACK]) begin
            addsub_b[15:0] = {4'b0, OP2out[7:4], 4'b0, OP2out[3:0]};
        end else if (!execOPC && !exec[`OP2out_one] && !exec[`get_bfoffset]) begin
            if (!long_start && exe_datatype == 2'b00 && !exec[`use_SP]) begin
                addsub_b = 32'd1;
            end else if (!long_start && exe_datatype == 2'b10 &&
                         (exec[`presub] | exec[`postadd] | movem_presub)) begin
                if (exec[`movem_action])
                    addsub_b = 32'd6;
                else
                    addsub_b = 32'd4;
            end else begin
                addsub_b = 32'd2;
            end
        end else begin
            if ((exec[`use_XZFlag] && Flags[4]) || exec[`opcCHK])
                c_in[0] = 1'b1;
            opaddsub = exec[`addsub];
        end

        // patch for un-aligned movem (mikej)
        if (exec[`movem_action] || check_aligned) begin
            if (!movem_presub) begin // up
                if (non_aligned && !long_start)
                    addsub_b = 32'b0;
            end else begin
                if (non_aligned && !long_start) begin
                    if (exe_datatype == 2'b10)
                        addsub_b = 32'd8;
                    else
                        addsub_b = 32'd4;
                end
            end
        end

        if (!opaddsub || long_start) begin // ADD
            notaddsub_b = {1'b0, addsub_b, c_in[0]};
        end else begin // SUB
            notaddsub_b = ~{1'b0, addsub_b, c_in[0]};
        end
        add_result  = ({1'b0, addsub_a, notaddsub_b[0]} + notaddsub_b);
        c_in[1]     = add_result[9]  ^ addsub_a[8]  ^ addsub_b[8];
        c_in[2]     = add_result[17] ^ addsub_a[16] ^ addsub_b[16];
        c_in[3]     = add_result[33];
        addsub_q    = add_result[32:1];
        addsub_ofl[0] = c_in[1] ^ add_result[8]  ^ addsub_a[7]  ^ addsub_b[7];  // V Byte
        addsub_ofl[1] = c_in[2] ^ add_result[16] ^ addsub_a[15] ^ addsub_b[15]; // V Word
        addsub_ofl[2] = c_in[3] ^ add_result[32] ^ addsub_a[31] ^ addsub_b[31]; // V Long
        c_out         = c_in[3:1];
    end

    // -------------------------------------------------------------------------
    // BCD_ARITH (04.04.2017 by Tobiflex - BCD handling with all undefined behavior!)
    // -------------------------------------------------------------------------
    always @(*) begin
        bcd_pur     = {c_in[1], add_result[8:0]};
        bcd_kor     = 9'b0;
        halve_carry = OP1out[4] ^ OP2out[4] ^ bcd_pur[5];
        if (halve_carry)
            bcd_kor[3:0] = 4'b0110; // -6
        if (bcd_pur[9])
            bcd_kor[7:4] = 4'b0110; // -60

        if (exec[`opcABCD]) begin
            Vflag_a = ~bcd_pur[8] & bcd_a[7];
            bcd_a   = bcd_pur[9:1] + bcd_kor;
            if (bcd_pur[4] & (bcd_pur[3] | bcd_pur[2]))
                bcd_kor[3:0] = 4'b0110; // +6
            if (bcd_pur[8] & (bcd_pur[7] | bcd_pur[6] |
                (bcd_pur[5] & bcd_pur[4] & (bcd_pur[3] | bcd_pur[2]))))
                bcd_kor[7:4] = 4'b0110; // +60
        end else begin // opcSBCD
            Vflag_a = bcd_pur[8] & ~bcd_a[7];
            bcd_a   = bcd_pur[9:1] - bcd_kor;
        end
        if (CPU[1])
            Vflag_a = 1'b0; // 68020
        bcd_a_carry = bcd_pur[9] | bcd_a[8];
    end

    // -------------------------------------------------------------------------
    // Bits - clocked part (bchg, bset decode)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (clkena_lw) begin
            bchg <= 1'b0;
            bset <= 1'b0;
            case (opcode[7:6])
                2'b01: bchg <= 1'b1; // BCHG
                2'b11: bset <= 1'b1; // BSET
                default: ;
            endcase
        end
    end

    // Bits - combinational part
    always @(*) begin
        if (!exe_opcode[8]) begin
            if (exe_opcode[5:4] == 2'b00)
                bit_number = sndOPC[4:0];
            else
                bit_number = {2'b00, sndOPC[2:0]};
        end else begin
            if (exe_opcode[5:4] == 2'b00)
                bit_number = reg_QB[4:0];
            else
                bit_number = {2'b00, reg_QB[2:0]};
        end

        one_bit_in = OP1out[bit_number];
        bits_out   = OP1out;
        bits_out[bit_number] = (bchg & ~one_bit_in) | bset;
    end

    // -------------------------------------------------------------------------
    // Bit Field - clocked part
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (clkena_lw) begin
            bf_bset  <= 1'b0;
            bf_bchg  <= 1'b0;
            bf_ins   <= 1'b0;
            bf_exts  <= 1'b0;
            bf_fffo  <= 1'b0;
            bf_d32   <= 1'b0;
            bf_s32   <= 1'b0;
            // 000-bftst, 001-bfextu, 010-bfchg, 011-bfexts,
            // 100-bfclr, 101-bfffo, 110-bfset, 111-bfins
            if (opcode[5:4] == 2'b00)
                bf_s32 <= 1'b1;
            case (opcode[10:8])
                3'b010: bf_bchg <= 1'b1; // BFCHG
                3'b011: bf_exts <= 1'b1; // BFEXTS
                3'b101: bf_fffo <= 1'b1; // BFFFO
                3'b110: bf_bset <= 1'b1; // BFSET
                3'b111: begin bf_ins <= 1'b1; bf_s32 <= 1'b1; end // BFINS
                default: ;
            endcase
            if (opcode[4:3] == 2'b00)
                bf_d32 <= 1'b1;
            bf_ext_out <= result[39:32];
        end
    end

    // Bit Field - combinational part
    always @(*) begin
        if (bf_ins)
            datareg = reg_QB;
        else
            datareg = bf_set2;

        // create bitmask for operation
        // unshifted bitmask: '0' => bit is in the Bitfieldvector
        //                    '1' => bit is not in the Bitfieldvector
        unshifted_bitmask = 32'b0;
        for (i = 0; i <= 31; i = i + 1) begin
            if (i > bf_width[4:0]) begin
                datareg[i]          = 1'b0;
                unshifted_bitmask[i] = 1'b1;
            end
        end

        bf_NFlag = datareg[bf_width[4:0]];
        if (bf_exts && bf_NFlag)
            bf_datareg = datareg | unshifted_bitmask;
        else
            bf_datareg = datareg;

        // shift bitmask for operation
        if (bf_loffset[4])
            bitmaskmux3 = {unshifted_bitmask[15:0], unshifted_bitmask[31:16]};
        else
            bitmaskmux3 = unshifted_bitmask;

        if (bf_loffset[3])
            bitmaskmux2 = {bitmaskmux3[23:0], bitmaskmux3[31:24]};
        else
            bitmaskmux2 = bitmaskmux3;

        if (bf_loffset[2]) begin
            bitmaskmux1 = {bitmaskmux2, 4'b1111};
            if (bf_d32)
                bitmaskmux1[3:0] = bitmaskmux2[31:28];
        end else begin
            bitmaskmux1 = {4'b1111, bitmaskmux2};
        end

        if (bf_loffset[1]) begin
            bitmaskmux0 = {bitmaskmux1, 2'b11};
            if (bf_d32)
                bitmaskmux0[1:0] = bitmaskmux1[31:30];
        end else begin
            bitmaskmux0 = {2'b11, bitmaskmux1};
        end

        if (bf_loffset[0]) begin
            shifted_bitmask = {1'b1, bitmaskmux0, 1'b1};
            if (bf_d32)
                shifted_bitmask[0] = bitmaskmux0[31];
        end else begin
            shifted_bitmask = {2'b11, bitmaskmux0};
        end

        // shift for ins
        shift_bf = {bf_ext_in, OP2out};
        if (bf_s32)
            shift_bf[39:32] = OP2out[7:0];

        if (bf_shift[0])
            inmux0 = {shift_bf[0], shift_bf[39:1]};
        else
            inmux0 = shift_bf;

        if (bf_shift[1])
            inmux1 = {inmux0[1:0], inmux0[39:2]};
        else
            inmux1 = inmux0;

        if (bf_shift[2])
            inmux2 = {inmux1[3:0], inmux1[39:4]};
        else
            inmux2 = inmux1;

        if (bf_shift[3])
            inmux3 = {inmux2[7:0], inmux2[31:8]};
        else
            inmux3 = inmux2[31:0];

        if (bf_shift[4])
            bf_set2 = {inmux3[15:0], inmux3[31:16]};
        else
            bf_set2 = inmux3;

        if (bf_ins) begin
            result[31:0]  = bf_set2;
            result[39:32] = bf_set2[7:0];
        end else if (bf_bchg) begin
            result[31:0]  = ~OP2out;
            result[39:32] = ~bf_ext_in;
        end else begin
            result = 40'b0;
        end
        if (bf_bset)
            result = {40{1'b1}};

        if (bf_ins)
            result_tmp = {bf_ext_in, OP1out};
        else
            result_tmp = {bf_ext_in, OP2out};

        for (i = 0; i <= 39; i = i + 1) begin
            if (shifted_bitmask[i])
                result[i] = result_tmp[i]; // restore old data
        end

        // BFFFO priority encoder
        mask           = datareg;
        bitnr          = 5'b11111;
        mask_not_zero  = 1'b1;
        mux            = 4'b0;

        if (mask[31:28] == 4'b0000) begin
            if (mask[27:24] == 4'b0000) begin
                if (mask[23:20] == 4'b0000) begin
                    if (mask[19:16] == 4'b0000) begin
                        bitnr[4] = 1'b0;
                        if (mask[15:12] == 4'b0000) begin
                            if (mask[11:8] == 4'b0000) begin
                                bitnr[3] = 1'b0;
                                if (mask[7:4] == 4'b0000) begin
                                    bitnr[2] = 1'b0;
                                    mux = mask[3:0];
                                end else begin
                                    mux = mask[7:4];
                                end
                            end else begin
                                mux      = mask[11:8];
                                bitnr[2] = 1'b0;
                            end
                        end else begin
                            mux = mask[15:12];
                        end
                    end else begin
                        mux      = mask[19:16];
                        bitnr[3] = 1'b0;
                        bitnr[2] = 1'b0;
                    end
                end else begin
                    mux      = mask[23:20];
                    bitnr[3] = 1'b0;
                end
            end else begin
                mux      = mask[27:24];
                bitnr[2] = 1'b0;
            end
        end else begin
            mux = mask[31:28];
        end

        if (mux[3:2] == 2'b00) begin
            bitnr[1] = 1'b0;
            if (!mux[1]) begin
                bitnr[0] = 1'b0;
                if (!mux[0])
                    mask_not_zero = 1'b0;
            end
        end else begin
            if (!mux[3])
                bitnr[0] = 1'b0;
        end

        bf_firstbit = {1'b0, bitnr} + {5'b0, mask_not_zero};
    end

    // -------------------------------------------------------------------------
    // Rotation
    // -------------------------------------------------------------------------
    always @(*) begin
        case (exe_opcode[7:6])
            2'b00:         rot_rot = OP1out[7];   // Byte
            2'b01, 2'b11:  rot_rot = OP1out[15];  // Word
            2'b10:         rot_rot = OP1out[31];  // Long
            default:       rot_rot = 1'b0;
        endcase

        case (rot_bits)
            2'b00: begin rot_lsb = 1'b0;     rot_msb = rot_rot;   end // ASL, ASR
            2'b01: begin rot_lsb = 1'b0;     rot_msb = 1'b0;      end // LSL, LSR
            2'b10: begin rot_lsb = Flags[4]; rot_msb = Flags[4];  end // ROXL, ROXR
            2'b11: begin rot_lsb = rot_rot;  rot_msb = OP1out[0]; end // ROL, ROR
            default: begin rot_lsb = 1'b0;   rot_msb = 1'b0;      end
        endcase

        if (exec[`rot_nop]) begin
            rot_out = OP1out;
            rot_X   = Flags[4];
            if (rot_bits == 2'b10) // ROXL, ROXR
                rot_C = Flags[4];
            else
                rot_C = 1'b0;
        end else begin
            if (exe_opcode[8]) begin // left
                rot_out = {OP1out[30:0], rot_lsb};
                rot_X   = rot_rot;
                rot_C   = rot_rot;
            end else begin // right
                rot_X   = OP1out[0];
                rot_C   = OP1out[0];
                rot_out = {rot_msb, OP1out[31:1]};
                case (exe_opcode[7:6])
                    2'b00: rot_out[7]  = rot_msb; // Byte
                    2'b01, 2'b11: rot_out[15] = rot_msb; // Word
                    default: ;
                endcase
            end
            if (BarrelShifter != 0)
                rot_out = BSout;
        end
    end

    // -------------------------------------------------------------------------
    // Barrel Shifter
    // -------------------------------------------------------------------------
    always @(*) begin
        ring = 6'b100000;
        if (rot_bits == 2'b10) begin // ROX L/R
            case (exe_opcode[7:6])
                2'b00:         ring = 6'b001001; // Byte
                2'b01, 2'b11:  ring = 6'b010001; // Word
                2'b10:         ring = 6'b100001; // Long
                default:       ring = 6'b100000;
            endcase
        end else begin
            case (exe_opcode[7:6])
                2'b00:         ring = 6'b001000; // Byte
                2'b01, 2'b11:  ring = 6'b010000; // Word
                2'b10:         ring = 6'b100000; // Long
                default:       ring = 6'b100000;
            endcase
        end

        if (exe_opcode[7:6] == 2'b11 || !exec[`exec_BS]) begin
            bs_shift = 6'b000001;
        end else if (exe_opcode[5]) begin
            bs_shift = OP2out[5:0];
        end else begin
            bs_shift[2:0] = exe_opcode[11:9];
            if (exe_opcode[11:9] == 3'b000)
                bs_shift[5:3] = 3'b001;
            else
                bs_shift[5:3] = 3'b000;
        end

        // calc V-Flag by ASL
        bit_msb = 6'b000000;
        hot_msb = 34'b0;
        hot_msb[bit_msb] = 1'b1;
        if (bs_shift < ring)
            bit_msb = ring - bs_shift;

        asl_over_xor = {({1'b0, vector[30:0]} ^ {1'b0, vector[31:1]}), msb};
        case (exe_opcode[7:6])
            2'b00:        asl_over_xor[8]  = 1'b0; // Byte
            2'b01, 2'b11: asl_over_xor[16] = 1'b0; // Word
            default: ;
        endcase
        asl_over = asl_over_xor - {1'b0, hot_msb[31:0]};
        bs_V = 1'b0;
        if (rot_bits == 2'b00 && exe_opcode[8]) // ASL
            bs_V = ~asl_over[32];

        bs_X = bs_C;
        if (!exe_opcode[8]) begin // right shift
            bs_C = result_bs[31];
        end else begin // left shift
            case (exe_opcode[7:6])
                2'b00:         bs_C = result_bs[8];  // Byte
                2'b01, 2'b11:  bs_C = result_bs[16]; // Word
                2'b10:         bs_C = result_bs[32]; // Long
                default:       bs_C = 1'b0;
            endcase
        end

        ALU = 32'bx;
        if (rot_bits == 2'b11) begin // ROL/ROR
            bs_X = Flags[4];
            case (exe_opcode[7:6])
                2'b00: begin // Byte
                    ALU[7:0] = result_bs[7:0] | result_bs[15:8];
                    bs_C     = ALU[7];
                end
                2'b01, 2'b11: begin // Word
                    ALU[15:0] = result_bs[15:0] | result_bs[31:16];
                    bs_C      = ALU[15];
                end
                2'b10: begin // Long
                    ALU  = result_bs[31:0] | result_bs[63:32];
                    bs_C = ALU[31];
                end
                default: ;
            endcase
            if (exe_opcode[8]) // left shift
                bs_C = ALU[0];
        end else if (rot_bits == 2'b10) begin // ROXL/ROXR
            case (exe_opcode[7:6])
                2'b00: begin // Byte
                    ALU[7:0] = result_bs[7:0] | result_bs[16:9];
                    bs_C     = result_bs[8] | result_bs[17];
                end
                2'b01, 2'b11: begin // Word
                    ALU[15:0] = result_bs[15:0] | result_bs[32:17];
                    bs_C      = result_bs[16] | result_bs[33];
                end
                2'b10: begin // Long
                    ALU  = result_bs[31:0] | result_bs[64:33];
                    bs_C = result_bs[32] | result_bs[65];
                end
                default: ;
            endcase
        end else begin
            if (!exe_opcode[8]) // right shift
                ALU = result_bs[63:32];
            else // left shift
                ALU = result_bs[31:0];
        end

        if (bs_shift == 6'b0) begin
            if (rot_bits == 2'b10) // ROXL/ROXR
                bs_C = Flags[4];
            else
                bs_C = 1'b0;
            bs_X = Flags[4];
            bs_V = 1'b0;
        end

        // calc shift count (bs_shift mod ring)
        case (ring)
            6'b001001: begin // ring=9 (Byte ROX)
                if      (bs_shift == 63)         bs_shift_mod = 6'd0;
                else if (bs_shift > 6*9-1)       bs_shift_mod = bs_shift - 6*9;
                else if (bs_shift > 5*9-1)       bs_shift_mod = bs_shift - 5*9;
                else if (bs_shift > 4*9-1)       bs_shift_mod = bs_shift - 4*9;
                else if (bs_shift > 3*9-1)       bs_shift_mod = bs_shift - 3*9;
                else if (bs_shift > 2*9-1)       bs_shift_mod = bs_shift - 2*9;
                else if (bs_shift > 9-1)         bs_shift_mod = bs_shift - 9;
                else                             bs_shift_mod = bs_shift;
            end
            6'b010001: begin // ring=17 (Word ROX)
                if      (bs_shift > 3*17-1)      bs_shift_mod = bs_shift - 3*17;
                else if (bs_shift > 2*17-1)      bs_shift_mod = bs_shift - 2*17;
                else if (bs_shift > 17-1)        bs_shift_mod = bs_shift - 17;
                else                             bs_shift_mod = bs_shift;
            end
            6'b100001: begin // ring=33 (Long ROX)
                if (bs_shift > 32)               bs_shift_mod = bs_shift - 33;
                else                             bs_shift_mod = bs_shift;
            end
            6'b001000: bs_shift_mod = {3'b000, bs_shift[2:0]}; // ring=8 Byte
            6'b010000: bs_shift_mod = {2'b00,  bs_shift[3:0]}; // ring=16 Word
            6'b100000: bs_shift_mod = {1'b0,   bs_shift[4:0]}; // ring=32 Long
            default:   bs_shift_mod = 6'b0;
        endcase

        bit_nr = bs_shift_mod;
        if (!exe_opcode[8]) // right shift
            bit_nr = ring - bs_shift_mod;
        if (!rot_bits[1]) begin // only shift
            if (!exe_opcode[8]) // right shift
                bit_nr = 32 - bs_shift_mod;
            if (bs_shift == ring) begin
                if (!exe_opcode[8]) // right shift
                    bit_nr = 32 - ring;
                else
                    bit_nr = ring;
            end
            if (bs_shift > ring) begin
                if (!exe_opcode[8]) begin // right shift
                    bit_nr = 6'b0;
                    bs_C   = 1'b0;
                end else begin
                    bit_nr = ring + 1;
                end
            end
        end

        // calc ASR sign
        BSout    = ALU;
        asr_sign = 33'b0;
        asr_sign[32:1] = asr_sign[31:0] | hot_msb[31:0];
        if (rot_bits == 2'b00 && !exe_opcode[8] && msb) begin // ASR
            BSout = ALU | asr_sign[32:1];
            if (bs_shift > ring)
                bs_C = 1'b1;
        end

        vector[32:0] = {1'b0, OP1out};
        case (exe_opcode[7:6])
            2'b00: begin // Byte
                msb            = OP1out[7];
                vector[31:8]   = 24'h0;
                BSout[31:8]    = 24'h0;
                if (rot_bits == 2'b10) vector[8] = Flags[4]; // ROX
            end
            2'b01, 2'b11: begin // Word
                msb            = OP1out[15];
                vector[31:16]  = 16'h0;
                BSout[31:16]   = 16'h0;
                if (rot_bits == 2'b10) vector[16] = Flags[4]; // ROX
            end
            2'b10: begin // Long
                msb = OP1out[31];
                if (rot_bits == 2'b10) vector[32] = Flags[4]; // ROX
            end
            default: msb = 1'b0;
        endcase
        result_bs = {1'b0, 32'h0, vector} << bit_nr[5:0];
    end

    // -------------------------------------------------------------------------
    // CCR op - combinational
    // -------------------------------------------------------------------------
    always @(*) begin
        if (exec[`andiSR])
            CCRin = Flags & last_data_read[7:0];
        else if (exec[`eoriSR])
            CCRin = Flags ^ last_data_read[7:0];
        else if (exec[`oriSR])
            CCRin = Flags | last_data_read[7:0];
        else
            CCRin = OP2out[7:0];

        // Flags - NZVC
        flag_z = 3'b000;
        if (exec[`use_XZFlag] && !Flags[2]) begin
            flag_z = 3'b000;
        end else if (OP1in[7:0] == 8'b0) begin
            flag_z[0] = 1'b1;
            if (OP1in[15:8] == 8'b0) begin
                flag_z[1] = 1'b1;
                if (OP1in[31:16] == 16'b0)
                    flag_z[2] = 1'b1;
            end
        end

        if (exe_datatype == 2'b00) begin // Byte
            set_Flags = {OP1in[7], flag_z[0], addsub_ofl[0], c_out[0]};
            if (exec[`opcABCD] | exec[`opcSBCD]) begin
                set_Flags[0] = bcd_a_carry;
                set_Flags[1] = Vflag_a;
            end
        end else if (exe_datatype == 2'b10 || exec[`opcCPMAW]) begin // Long
            set_Flags = {OP1in[31], flag_z[2], addsub_ofl[2], c_out[2]};
        end else begin // Word
            set_Flags = {OP1in[15], flag_z[1], addsub_ofl[1], c_out[1]};
        end
    end

    // CCR - clocked Flags register
    always @(posedge clk) begin
        if (Reset) begin
            Flags[7:0] <= 8'b0;
        end else if (clkena_lw) begin
            if (exec[`directSR] | set_stop)
                Flags[7:0] <= data_read[7:0];
            if (exec[`directCCR])
                Flags[7:0] <= data_read[7:0];

            if (exec[`opcROT] && !decodeOPC)
                asl_VFlag <= (set_Flags[3] ^ rot_rot) | asl_VFlag;
            else
                asl_VFlag <= 1'b0;

            if (exec[`to_CCR]) begin
                Flags[7:0] <= CCRin[7:0]; // CCR
            end else if (Z_error) begin
                if (micro_state == `ms_trap0) begin
                    // Undocumented behavior (flags when div by zero)
                    if (!exe_opcode[8])
                        Flags[3:0] <= {1'b0, ~reg_QA[31], 2'b00};
                    else
                        Flags[3:0] <= 4'b0100;
                end
            end else if (!exec[`no_Flags]) begin
                last_Flags1 <= Flags[3:0];
                if (exec[`opcADD])
                    Flags[4] <= set_Flags[0];
                else if (exec[`opcROT] && rot_bits != 2'b11 && !exec[`rot_nop])
                    Flags[4] <= rot_X;
                else if (exec[`exec_BS])
                    Flags[4] <= bs_X;

                if (exec[`opcCMP] | exec[`alu_setFlags]) begin
                    Flags[3:0] <= set_Flags;
                end else if (exec[`opcDIVU] && DIV_Mode != 3) begin
                    if (V_Flag)
                        Flags[3:0] <= 4'b1010;
                    else if (exe_opcode[15] || DIV_Mode == 0)
                        Flags[3:0] <= {OP1in[15], flag_z[1], 2'b00};
                    else
                        Flags[3:0] <= {OP1in[31], flag_z[2], 2'b00};
                end else if (exec[`write_reminder] && MUL_Mode != 3) begin // z-flag MULU.l
                    Flags[3]   <= set_Flags[3];
                    Flags[2]   <= set_Flags[2] & Flags[2];
                    Flags[1]   <= 1'b0;
                    Flags[0]   <= 1'b0;
                end else if (exec[`write_lowlong] && (MUL_Mode == 1 || MUL_Mode == 2)) begin // flag MULU.l
                    Flags[3]   <= set_Flags[3];
                    Flags[2]   <= set_Flags[2];
                    Flags[1]   <= set_mV_Flag; // V
                    Flags[0]   <= 1'b0;
                end else if (exec[`opcOR] | exec[`opcAND] | exec[`opcEOR] | exec[`opcMOVE] |
                             exec[`opcMOVEQ] | exec[`opcSWAP] | exec[`opcBF] |
                             (exec[`opcMULU] && MUL_Mode != 3)) begin
                    Flags[1:0] <= 2'b00;
                    Flags[3:2] <= set_Flags[3:2];
                    if (exec[`opcBF])
                        Flags[3] <= bf_NFlag;
                end else if (exec[`opcROT]) begin
                    Flags[3:2] <= set_Flags[3:2];
                    Flags[0]   <= rot_C;
                    if (rot_bits == 2'b00 && ((set_Flags[3] ^ rot_rot) | asl_VFlag)) // ASL/ASR
                        Flags[1] <= 1'b1;
                    else
                        Flags[1] <= 1'b0;
                end else if (exec[`exec_BS]) begin
                    Flags[3:2] <= set_Flags[3:2];
                    Flags[0]   <= bs_C;
                    Flags[1]   <= bs_V;
                end else if (exec[`opcBITS]) begin
                    Flags[2] <= ~one_bit_in;
                end else if (exec[`opcCHK2]) begin
                    // micro_state: chk21=LB vs R, chk22=LB vs UB, chk23=UB vs R
                    if (!last_Flags1[0]) begin // unsigned OP
                        Flags[0] <= Flags[0] | (~set_Flags[0] & ~set_Flags[2]);
                    end else begin // signed OP
                        Flags[0] <= (Flags[0] ^ set_Flags[0]) & ~Flags[2] & ~set_Flags[2];
                    end
                    Flags[1] <= 1'b0;
                    Flags[2] <= Flags[2] | set_Flags[2];
                    Flags[3] <= ~last_Flags1[0];
                end else if (exec[`opcCHK]) begin
                    if (exe_datatype == 2'b01) // Word
                        Flags[3] <= OP1out[15];
                    else
                        Flags[3] <= OP1out[31];
                    if (OP1out[15:0] == 16'h0000 && (exe_datatype == 2'b01 ||
                        OP1out[31:16] == 16'h0000))
                        Flags[2] <= 1'b1;
                    else
                        Flags[2] <= 1'b0;
                    Flags[1] <= 1'b0;
                    Flags[0] <= 1'b0;
                end
            end
        end
        Flags[7:5] <= 3'b000; // always cleared (outside clkena guard)
    end

    // -------------------------------------------------------------------------
    // MULU/MULS - combinational
    // -------------------------------------------------------------------------
    always @(*) begin
        result_mulu = 128'b0; // default to avoid latches
        faktorA     = 32'b0;
        faktorB     = 32'b0;
        muls_msb    = 1'b0;
        mulu_sign   = 1'b0;
        set_mV_Flag = 1'b0;
        if (MUL_Hardware == 1) begin
            if (MUL_Mode == 0) begin // 16-Bit
                faktorA = (signedOP && reg_QA[15]) ? 32'hFFFFFFFF : 32'h00000000;
                faktorB = (signedOP && OP2out[15]) ? 32'hFFFFFFFF : 32'h00000000;
                result_mulu[63:0] = ({faktorA[15:0], reg_QA[15:0]}) *
                                    ({faktorB[15:0], OP2out[15:0]});
            end else begin
                if (exe_opcode[15]) begin // 16-Bit
                    faktorA = (signedOP && reg_QA[15]) ? 32'hFFFFFFFF : 32'h00000000;
                    faktorB = (signedOP && OP2out[15]) ? 32'hFFFFFFFF : 32'h00000000;
                end else begin
                    faktorA[15:0]  = reg_QA[31:16];
                    faktorB[15:0]  = OP2out[31:16];
                    faktorA[31:16] = (signedOP && reg_QA[31]) ? 16'hFFFF : 16'h0000;
                    faktorB[31:16] = (signedOP && OP2out[31]) ? 16'hFFFF : 16'h0000;
                end
                result_mulu[127:0] =
                    ({128{1'b0}} | {{faktorA[31:16], faktorA[31:0], reg_QA[15:0]}}) *
                    ({128{1'b0}} | {{faktorB[31:16], faktorB[31:0], OP2out[15:0]}});
            end
            // set_mV_Flag for 32-bit MULU.l
            if ((result_mulu[63:32] == 32'h00000000 && (!signedOP || !result_mulu[31])) ||
                (result_mulu[63:32] == 32'hFFFFFFFF &&  signedOP &&  result_mulu[31]))
                set_mV_Flag = 1'b0;
            else
                set_mV_Flag = 1'b1;
        end else begin // MUL_Hardware == 0: iterative multiply
            // Compute faktorB from current inputs first
            if (exe_opcode[15] || MUL_Mode == 0) begin
                faktorB = {OP2out[15:0], 16'b0};
            end else begin
                faktorB = OP2out;
            end
            // Then compute derived signals using current faktorB
            muls_msb = ((signedOP && faktorB[31]) || FAsign) ? mulu_reg[63] : 1'b0;
            mulu_sign = (signedOP && faktorB[31]) ? 1'b1 : 1'b0;
            faktorA = 32'bx; // not used in MUL_Hardware=0 path

            if (MUL_Mode == 0) begin // 16-Bit
                result_mulu[63:32] = {muls_msb, mulu_reg[63:33]};
                result_mulu[15:0]  = {1'b0, mulu_reg[15:1]};
                if (mulu_reg[0]) begin
                    if (FAsign)
                        result_mulu[63:47] = {muls_msb, mulu_reg[63:48]} - {mulu_sign, faktorB[31:16]};
                    else
                        result_mulu[63:47] = {muls_msb, mulu_reg[63:48]} + {mulu_sign, faktorB[31:16]};
                end
            end else begin // 32-Bit
                result_mulu[63:0] = {muls_msb, mulu_reg[63:1]};
                if (mulu_reg[0]) begin
                    if (FAsign)
                        result_mulu[63:31] = {muls_msb, mulu_reg[63:32]} - {mulu_sign, faktorB};
                    else
                        result_mulu[63:31] = {muls_msb, mulu_reg[63:32]} + {mulu_sign, faktorB};
                end
            end

            // set_mV_Flag
            if ((result_mulu[63:32] == 32'h00000000 && (!signedOP || !result_mulu[31])) ||
                (result_mulu[63:32] == 32'hFFFFFFFF &&  signedOP &&  result_mulu[31]))
                set_mV_Flag = 1'b0;
            else
                set_mV_Flag = 1'b1;
        end
    end

    // MULU clocked: mulu_reg and FAsign
    always @(posedge clk) begin
        if (clkena_lw) begin
            if (MUL_Hardware == 0) begin
                if (micro_state == `ms_mul1) begin
                    mulu_reg[63:32] <= 32'b0;
                    if (divs && ((exe_opcode[15] && reg_QA[15]) ||
                                 (!exe_opcode[15] && reg_QA[31]))) begin // MULS Neg factor
                        FAsign          <= 1'b1;
                        mulu_reg[31:0]  <= 32'd0 - reg_QA;
                    end else begin
                        FAsign          <= 1'b0;
                        mulu_reg[31:0]  <= reg_QA;
                    end
                end else if (!exec[`opcMULU]) begin
                    mulu_reg <= result_mulu[63:0];
                end
            end else begin
                mulu_reg[31:0] <= result_mulu[63:32];
            end
        end
    end

    // -------------------------------------------------------------------------
    // DIVU/DIVS - combinational
    // -------------------------------------------------------------------------
    always @(*) begin
        divs = (opcode[15] & opcode[8]) | (~opcode[15] & sndOPC[11]);

        dividend[15:0]  = 16'b0;
        dividend[63:32] = {16{divs & reg_QA[31]}};

        if (exe_opcode[15] || DIV_Mode == 0) begin // DIV.W
            dividend[47:16] = reg_QA;
            div_qsign = result_div_pre[15];
        end else begin // DIV.L
            dividend[31:0] = reg_QA;
            if (exe_opcode[14] && sndOPC[10])
                dividend[63:32] = reg_QB;
            div_qsign = result_div_pre[31];
        end

        if (signedOP || !opcode[15])
            OP2outext = OP2out[31:16];
        else
            OP2outext = 16'b0;

        if (signedOP && OP2out[31])
            div_sub = (div_reg[63:31]) + {1'b1, OP2out[31:0]};
        else
            div_sub = (div_reg[63:31]) - {1'b0, OP2outext[15:0], OP2out[15:0]};

        if (DIV_Mode == 0)
            div_bit = div_sub[16];
        else
            div_bit = div_sub[32];

        if (div_bit) begin
            div_quot[63:32] = div_reg[62:31];
        end else begin
            div_quot[63:32] = div_sub[31:0];
        end
        div_quot[31:0] = {div_reg[30:0], ~div_bit};

        if (div_neg)
            result_div_pre = 32'd0 - div_quot[31:0];
        else
            result_div_pre = div_quot[31:0];

        // Overflow detection
        if ((((nozero || !div_bit) && signedOP &&
              (OP2out[31] ^ OP1_sign ^ div_qsign)) || // Overflow DIVS
             (!signedOP && !div_over[32])) && DIV_Mode != 3) begin // Overflow DIVU
            set_V_Flag = 1'b1;
        end else begin
            set_V_Flag = 1'b0;
        end
    end

    // DIVU/DIVS - clocked
    always @(posedge clk) begin
        if (clkena_lw) begin
            if (micro_state != `ms_div_end2)
                V_Flag <= set_V_Flag;
            signedOP <= divs;

            if (micro_state == `ms_div1) begin
                nozero <= 1'b0;
                if (divs && dividend[63]) begin // Neg dividend
                    OP1_sign <= 1'b1;
                    div_reg  <= 64'd0 - dividend;
                end else begin
                    OP1_sign <= 1'b0;
                    div_reg  <= dividend;
                end
            end else begin
                div_reg <= div_quot;
                nozero  <= ~div_bit | nozero;
            end

            if (micro_state == `ms_div2) begin
                div_neg <= signedOP & (OP2out[31] ^ OP1_sign);
                if (DIV_Mode == 0) begin
                    div_over[32:16] <= {1'b0, div_reg[47:32]} - {1'b0, OP2out[15:0]};
                end else begin
                    div_over <= {1'b0, div_reg[63:32]} - {1'b0, OP2outext[15:0], OP2out[15:0]};
                end
            end

            if (!exec[`write_reminder]) begin
                result_div[31:0] <= result_div_pre;
                if (OP1_sign)
                    result_div[63:32] <= 32'd0 - div_quot[63:32];
                else
                    result_div[63:32] <= div_quot[63:32];
            end
        end
    end

endmodule
