// ----------------------------------------------------------------------------
// TG68KdotC_Kernel.v
// Fresh translation from VHDL TG68KdotC_Kernel.vhd (do not derive from prior .v/.sv)
//
// Copyright (c) 2009-2020 Tobias Gubener
// Patches by MikeJ, Till Harbaum, Rok Krajnk, ...
// Subdesign fAMpIGA by TobiFlex
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// SystemVerilog. Combinational VHDL processes -> always_comb (blocking, last
// write wins, matching VHDL signal-feedback convergence since each such process
// is sensitive to its own outputs and assignments precede reads textually).
// Clocked VHDL processes -> always_ff. Mixed processes are split.
// ----------------------------------------------------------------------------

`include "TG68K_Pack.vh"

module TG68KdotC_Kernel #(
    parameter SR_Read        = 2,  // 0=>user, 1=>privileged, 2=>switchable with CPU(0)
    parameter VBR_Stackframe = 2,  // 0=>no, 1=>yes/extended, 2=>switchable with CPU(0)
    parameter extAddr_Mode   = 2,  // 0=>no, 1=>yes, 2=>switchable with CPU(1)
    parameter MUL_Mode       = 2,  // 0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL
    parameter DIV_Mode       = 2,  // 0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV
    parameter BitField       = 2,  // 0=>no, 1=>yes, 2=>switchable with CPU(1)
    parameter BarrelShifter  = 1,  // 0=>no, 1=>yes, 2=>switchable with CPU(1)
    parameter MUL_Hardware   = 1   // 0=>no, 1=>yes
)(
    input             clk,
    input             nReset,          // low active
    input             clkena_in,
    input      [15:0] data_in,
    input      [2:0]  IPL,
    input             IPL_autovector,
    input             berr,            // only 68000 Stackpointer dummy
    input      [1:0]  CPU,             // 00->68000  01->68010  11->68020
    output     [31:0] addr_out,
    output reg [15:0] data_write,
    output            nWr,
    output            nUDS,
    output            nLDS,
    output     [1:0]  busstate,        // 00->fetch 10->read 11->write 01->no memaccess
    output            longword,
    output            nResetOut,
    output     [2:0]  FC,
    output            clr_berr,
    // for debug
    output reg        skipFetch,
    output     [31:0] regin_out,
    output     [3:0]  CACR_out,
    output     [31:0] VBR_out
);

    // -------------------------------------------------------------------------
    // signals (architecture decls, VHDL 148-366)
    // -------------------------------------------------------------------------
    logic        use_VBR_Stackframe;
    logic [3:0]  syncReset;
    logic        Reset;
    logic        clkena_lw;
    logic [31:0] TG68_PC;
    logic [31:0] tmp_TG68_PC;
    logic [31:0] TG68_PC_add;
    logic [31:0] PC_dataa;
    logic [31:0] PC_datab;
    logic [31:0] memaddr;
    logic [1:0]  state;
    logic [1:0]  datatype;
    logic [1:0]  set_datatype;
    logic [1:0]  exe_datatype;
    logic [1:0]  setstate;
    logic        setaddrvalue;
    logic        addrvalue;

    logic [15:0] opcode;
    logic [15:0] exe_opcode;
    logic [15:0] sndOPC;

    logic [31:0] exe_pc;
    logic [31:0] last_opc_pc;
    logic [15:0] last_opc_read;
    logic [31:0] reg_QA;
    logic [31:0] reg_QB;
    logic        Wwrena, Lwrena;
    logic        Bwrena;
    logic        Regwrena_now;
    logic [3:0]  rf_dest_addr;
    logic [3:0]  rf_source_addr;
    logic [3:0]  rf_source_addrd;

    logic [31:0] regin;
    logic [31:0] regfile [0:15];
    logic [3:0]  RDindex_A;
    logic [3:0]  RDindex_B;
    logic        WR_AReg;

    logic [31:0] addr;
    logic [31:0] memaddr_reg;
    logic [31:0] memaddr_delta;
    logic [31:0] memaddr_delta_rega;
    logic [31:0] memaddr_delta_regb;
    logic        use_base;

    logic [31:0] ea_data;
    logic [31:0] OP1out;
    logic [31:0] OP2out;
    logic [15:0] OP1outbrief;
    logic [31:0] ALUout;           // from ALU
    logic [31:0] data_write_tmp;
    logic [31:0] data_write_muxin;
    logic [47:0] data_write_mux;
    logic        nextpass;
    logic        setnextpass;
    logic        setdispbyte;
    logic        setdisp;
    logic        regdirectsource;
    logic [31:0] addsub_q;         // from ALU
    logic [31:0] briefdata;
    logic [2:0]  c_out;            // from ALU

    logic [31:0] memaddr_a;

    logic        TG68_PC_brw;
    logic        TG68_PC_word;
    logic        getbrief;
    logic [15:0] brief;
    logic        data_is_source;
    logic        store_in_tmp;
    logic        write_back;
    logic        exec_write_back;
    logic        setstackaddr;
    logic        writePC;
    logic        writePCbig;
    logic        set_writePCbig;
    logic        writePCnext;
    logic        setopcode;
    logic        decodeOPC;
    logic        execOPC;
    logic        execOPC_ALU;
    logic        setexecOPC;
    logic        endOPC;
    logic        setendOPC;
    logic [7:0]  Flags;            // from ALU  ...XNZVC
    logic [7:0]  FlagsSR;          // T.S.0III
    logic [7:0]  SRin;
    logic        exec_DIRECT;
    logic        exec_tas;
    logic        set_exec_tas;

    logic        exe_condition;
    logic        ea_only;
    logic        source_areg;
    logic        source_lowbits;
    logic        source_LDRLbits;
    logic        source_LDRMbits;
    logic        source_2ndHbits;
    logic        source_2ndMbits;
    logic        source_2ndLbits;
    logic        dest_areg;
    logic        dest_LDRareg;
    logic        dest_LDRHbits;
    logic        dest_LDRLbits;
    logic        dest_2ndHbits;
    logic        dest_2ndLbits;
    logic        dest_hbits;
    logic [1:0]  rot_bits;
    logic [1:0]  set_rot_bits;
    logic [5:0]  rot_cnt;
    logic [5:0]  set_rot_cnt;
    logic        movem_actiond;
    logic [3:0]  movem_regaddr;
    logic [3:0]  movem_mux;
    logic        movem_presub;
    logic        movem_run;
    logic        set_direct_data;
    logic        use_direct_data;
    logic        direct_data;

    logic        set_V_Flag;       // from ALU
    logic        set_vectoraddr;
    logic        writeSR;
    logic        trap_berr;
    logic        trap_illegal;
    logic        trap_addr_error;
    logic        trap_priv;
    logic        trap_trace;
    logic        trap_1010;
    logic        trap_1111;
    logic        trap_trap;
    logic        trap_trapv;
    logic        trap_interrupt;
    logic        trapmake;
    logic        trapd;
    logic [7:0]  trap_SR;
    logic        make_trace;
    logic        make_berr;
    logic        useStackframe2;

    logic        set_stop;
    logic        stop;
    logic [31:0] trap_vector;
    logic [31:0] trap_vector_vbr;
    logic [31:0] USP;

    logic [2:0]  IPL_nr;
    logic [2:0]  rIPL_nr;
    logic [7:0]  IPL_vec;
    logic        interrupt;
    logic        setinterrupt;
    logic        SVmode;
    logic        preSVmode;
    logic        Suppress_Base;
    logic        set_Suppress_Base;
    logic        set_Z_error;
    logic        Z_error;
    logic        ea_build_now;
    logic        build_logical;
    logic        build_bcd;

    logic [31:0] data_read;
    logic [7:0]  bf_ext_in;
    logic [7:0]  bf_ext_out;       // from ALU
    logic        long_start;
    logic        long_start_alu;
    logic        non_aligned;
    logic        check_aligned;
    logic        long_done;
    logic [5:0]  memmask;
    logic [5:0]  set_memmask;
    logic [3:0]  memread;
    logic [5:0]  wbmemmask;
    logic [5:0]  memmaskmux;
    logic        oddout;
    logic        set_oddout;
    logic        PCbase;
    logic        set_PCbase;

    logic [31:0] last_data_read;
    logic [31:0] last_data_in;

    logic [5:0]  bf_offset;
    logic [5:0]  bf_width;
    logic [5:0]  bf_bhits;
    logic [5:0]  bf_shift;
    logic [5:0]  alu_width;
    logic [5:0]  alu_bf_shift;
    logic [5:0]  bf_loffset;
    logic [31:0] bf_full_offset;
    logic [31:0] alu_bf_ffo_offset;
    logic [5:0]  alu_bf_loffset;

    logic [31:0] movec_data;
    logic [31:0] VBR;
    logic [3:0]  CACR;
    logic [2:0]  DFC;
    logic [2:0]  SFC;

    logic [`lastOpcBit:0] set;
    logic [`lastOpcBit:0] set_exec;
    logic [`lastOpcBit:0] exec;

    logic [6:0]  micro_state;
    logic [6:0]  next_micro_state;

    // FC is driven bitwise by two clocked processes in the VHDL (FC[2] by the SR
    // process, FC[1:0] by the PC-calc process). Use disjoint internal regs and
    // recombine, so each net has a single driver.
    logic        FC_2;
    logic [1:0]  FC_10;
    assign FC = {FC_2, FC_10};

    // -------------------------------------------------------------------------
    // ALU instance (VHDL 372-421)
    // -------------------------------------------------------------------------
    TG68K_ALU #(
        .MUL_Mode      (MUL_Mode),
        .MUL_Hardware  (MUL_Hardware),
        .DIV_Mode      (DIV_Mode),
        .BarrelShifter (BarrelShifter)
    ) ALU (
        .clk            (clk),
        .Reset          (Reset),
        .CPU            (CPU),
        .clkena_lw      (clkena_lw),
        .execOPC        (execOPC_ALU),
        .decodeOPC      (decodeOPC),
        .exe_condition  (exe_condition),
        .exec_tas       (exec_tas),
        .long_start     (long_start_alu),
        .non_aligned    (non_aligned),
        .check_aligned  (check_aligned),
        .movem_presub   (movem_presub),
        .set_stop       (set_stop),
        .Z_error        (Z_error),
        .rot_bits       (rot_bits),
        .exec           (exec),
        .OP1out         (OP1out),
        .OP2out         (OP2out),
        .reg_QA         (reg_QA),
        .reg_QB         (reg_QB),
        .opcode         (opcode),
        .exe_opcode     (exe_opcode),
        .exe_datatype   (exe_datatype),
        .sndOPC         (sndOPC),
        .last_data_read (last_data_read[15:0]),
        .data_read      (data_read[15:0]),
        .FlagsSR        (FlagsSR),
        .micro_state    (micro_state),
        .bf_ext_in      (bf_ext_in),
        .bf_ext_out     (bf_ext_out),
        .bf_shift       (alu_bf_shift),
        .bf_width       (alu_width),
        .bf_ffo_offset  (alu_bf_ffo_offset),
        .bf_loffset     (alu_bf_loffset[4:0]),
        .set_V_Flag     (set_V_Flag),
        .Flags          (Flags),
        .c_out          (c_out),
        .addsub_q       (addsub_q),
        .ALUout         (ALUout)
    );

    // -------------------------------------------------------------------------
    // concurrent assignments (VHDL 423-451)
    // -------------------------------------------------------------------------
    assign longword       = ~memmaskmux[3];
    assign long_start_alu = ~memmaskmux[3];
    assign execOPC_ALU    = execOPC | exec[`alu_exec];

    always_comb begin
        non_aligned = 1'b0;
        if (memmaskmux[5:4] == 2'b01 || memmaskmux[5:4] == 2'b10)
            non_aligned = 1'b1;
    end

    assign regin_out  = regin;
    assign nWr        = (state == 2'b11) ? 1'b0 : 1'b1;
    assign busstate   = state;
    assign nResetOut  = exec[`opcRESET] ? 1'b0 : 1'b1;
    assign memmaskmux = addr[0] ? memmask : {memmask[4:0], 1'b1};
    assign nUDS       = memmaskmux[5];
    assign nLDS       = memmaskmux[4];
    assign clkena_lw  = (clkena_in && memmaskmux[3]) ? 1'b1 : 1'b0;
    assign clr_berr   = (setopcode && trap_berr) ? 1'b1 : 1'b0;

    // -------------------------------------------------------------------------
    // sync reset (VHDL 453-471)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge nReset) begin
        if (!nReset) begin
            syncReset <= 4'b0000;
            Reset     <= 1'b1;
        end else if (clkena_in) begin
            syncReset <= {syncReset[2:0], 1'b1};
            Reset     <= ~syncReset[3];
        end
    end

    always_ff @(posedge clk) begin
        if (VBR_Stackframe == 1 || (CPU[0] && VBR_Stackframe == 2))
            use_VBR_Stackframe <= 1'b1;
        else
            use_VBR_Stackframe <= 1'b0;
    end

    // -------------------------------------------------------------------------
    // data_read mux + latches (VHDL 473-509)
    // -------------------------------------------------------------------------
    always_comb begin
        if (!memmaskmux[4])
            data_read = {last_data_in[15:0], data_in};
        else
            data_read = {last_data_in[23:0], data_in[15:8]};
        if (memread[0] || (memread[1:0] == 2'b10 && memmaskmux[4]))
            data_read[31:16] = {16{data_read[15]}};
    end

    assign long_start = ~memmask[1];
    assign long_done  = ~memread[1];

    always_ff @(posedge clk) begin
        if (clkena_lw && state == 2'b10) begin
            if (!memmaskmux[4]) bf_ext_in <= last_data_in[23:16];
            else                bf_ext_in <= last_data_in[31:24];
        end
        if (Reset) begin
            last_data_read <= 32'b0;
        end else if (clkena_in) begin
            if (state == 2'b00 || exec[`update_ld]) begin
                last_data_read <= data_read;
                if (!state[1] && !memmask[1])
                    last_data_read[31:16] <= last_opc_read;
                else if (!state[1] || memread[1])
                    last_data_read[31:16] <= {16{data_in[15]}};
            end
            last_data_in <= {last_data_in[15:0], data_in[15:0]};
        end
    end

    // -------------------------------------------------------------------------
    // data_write mux (VHDL 511-551)
    // -------------------------------------------------------------------------
    always_comb begin
        if (exec[`write_reg]) data_write_muxin = reg_QB;
        else                  data_write_muxin = data_write_tmp;

        if (BitField == 0) begin
            if (oddout == addr[0]) data_write_mux = {16'h0000, data_write_muxin};
            else                   data_write_mux = {8'h00, data_write_muxin, 8'h00};
        end else begin
            if (oddout == addr[0]) data_write_mux = {8'h00, bf_ext_out, data_write_muxin};
            else                   data_write_mux = {bf_ext_out, data_write_muxin, 8'h00};
        end

        if (!memmaskmux[1])
            data_write = data_write_mux[47:32];
        else if (!memmaskmux[3])
            data_write = data_write_mux[31:16];
        else begin
            // a single byte shows up on both bus halfs
            if (memmaskmux[5:4] == 2'b10)
                data_write = {data_write_mux[7:0], data_write_mux[7:0]};
            else if (memmaskmux[5:4] == 2'b01)
                data_write = {data_write_mux[15:8], data_write_mux[15:8]};
            else
                data_write = data_write_mux[15:0];
        end
        if (exec[`mem_byte])   // movep
            data_write = {data_write_tmp[15:8], data_write_tmp[15:8]};
    end

    // -------------------------------------------------------------------------
    // Register file (VHDL 556-575)
    // -------------------------------------------------------------------------
    assign reg_QA = regfile[RDindex_A];
    assign reg_QB = regfile[RDindex_B];

    always_ff @(posedge clk) begin
        if (clkena_lw) begin
            rf_source_addrd <= rf_source_addr;
            WR_AReg         <= rf_dest_addr[3];
            RDindex_A       <= rf_dest_addr;
            RDindex_B       <= rf_source_addr;
            if (Wwrena)
                regfile[RDindex_A] <= regin;
            if (exec[`to_USP])
                USP <= reg_QA;
        end
    end

    // -------------------------------------------------------------------------
    // Write Reg (VHDL 580-621)
    // NB: VHDL reads Bwrena/Lwrena to build regin while assigning them later in
    // the same (self-sensitive) process -> converged value is the *final* one.
    // Compute the enables first so blocking semantics match that fixpoint.
    // -------------------------------------------------------------------------
    always_comb begin
        Bwrena = 1'b0;
        Wwrena = 1'b0;
        Lwrena = 1'b0;
        if (exec[`presub] || exec[`postadd] || exec[`changeMode]) begin  // -(An)+
            Wwrena = 1'b1;
            Lwrena = 1'b1;
        end else if (Regwrena_now) begin                                  // dbcc
            Wwrena = 1'b1;
        end else if (exec[`Regwrena]) begin                               // read (mem)
            Wwrena = 1'b1;
            case (exe_datatype)
                2'b00:   Bwrena = 1'b1;                                    // BYTE
                2'b01:   if (WR_AReg || movem_actiond) Lwrena = 1'b1;      // WORD
                default: Lwrena = 1'b1;                                    // LONG
            endcase
        end

        regin = ALUout;
        if (exec[`save_memaddr])                  regin = memaddr;
        else if (exec[`get_ea_now] && ea_only)    regin = memaddr_a;
        else if (exec[`from_USP])                 regin = USP;
        else if (exec[`movec_rd])                 regin = movec_data;
        if (Bwrena)  regin[15:8]  = reg_QA[15:8];
        if (!Lwrena) regin[31:16] = reg_QA[31:16];
    end

    // -------------------------------------------------------------------------
    // set dest regaddr (VHDL 626-657)
    // -------------------------------------------------------------------------
    always_comb begin
        if (exec[`movem_action])
            rf_dest_addr = rf_source_addrd;
        else if (set[`briefext])
            rf_dest_addr = brief[15:12];
        else if (set[`get_bfoffset])
            rf_dest_addr = {1'b0, sndOPC[8:6]};
        else if (dest_2ndHbits)
            rf_dest_addr = {dest_LDRareg, sndOPC[14:12]};
        else if (dest_LDRHbits)
            rf_dest_addr = last_data_read[15:12];
        else if (dest_LDRLbits)
            rf_dest_addr = {1'b0, last_data_read[2:0]};
        else if (dest_2ndLbits)
            rf_dest_addr = {1'b0, sndOPC[2:0]};
        else if (setstackaddr)
            rf_dest_addr = 4'b1111;
        else if (dest_hbits)
            rf_dest_addr = {dest_areg, opcode[11:9]};
        else begin
            if (opcode[5:3] == 3'b000 || data_is_source)
                rf_dest_addr = {dest_areg, opcode[2:0]};
            else
                rf_dest_addr = {1'b1, opcode[2:0]};
        end
    end

    // -------------------------------------------------------------------------
    // set source regaddr (VHDL 662-687)
    // -------------------------------------------------------------------------
    always_comb begin
        if (exec[`movem_action] || set[`movem_action]) begin
            if (movem_presub)
                rf_source_addr = movem_regaddr ^ 4'b1111;
            else
                rf_source_addr = movem_regaddr;
        end else if (source_2ndLbits)
            rf_source_addr = {1'b0, sndOPC[2:0]};
        else if (source_2ndHbits)
            rf_source_addr = {1'b0, sndOPC[14:12]};
        else if (source_2ndMbits)
            rf_source_addr = {1'b0, sndOPC[8:6]};
        else if (source_LDRLbits)
            rf_source_addr = {1'b0, last_data_read[2:0]};
        else if (source_LDRMbits)
            rf_source_addr = {1'b0, last_data_read[8:6]};
        else if (source_lowbits)
            rf_source_addr = {source_areg, opcode[2:0]};
        else if (exec[`linksp])
            rf_source_addr = 4'b1111;
        else
            rf_source_addr = {source_areg, opcode[11:9]};
    end

    // -------------------------------------------------------------------------
    // set OP1out (VHDL 692-702)
    // -------------------------------------------------------------------------
    always_comb begin
        OP1out = reg_QA;
        if (exec[`OP1out_zero])
            OP1out = 32'b0;
        else if (exec[`ea_data_OP1] && store_in_tmp)
            OP1out = ea_data;
        else if (exec[`movem_action] || !memmaskmux[3] || exec[`OP1addr])
            OP1out = addr;
    end

    // -------------------------------------------------------------------------
    // set OP2out (VHDL 707-735)
    // -------------------------------------------------------------------------
    always_comb begin
        OP2out[15:0]  = reg_QB[15:0];
        OP2out[31:16] = {16{OP2out[15]}};
        if (exec[`OP2out_one])
            OP2out[15:0] = 16'hFFFF;
        else if (use_direct_data || (exec[`exg] && execOPC) || exec[`get_bfoffset])
            OP2out = data_write_tmp;
        else if ((!exec[`ea_data_OP1] && store_in_tmp) || exec[`ea_data_OP2])
            OP2out = ea_data;
        else if (exec[`opcMOVEQ]) begin
            OP2out[7:0]  = exe_opcode[7:0];
            OP2out[15:8] = {8{exe_opcode[7]}};
        end else if (exec[`opcADDQ]) begin
            OP2out[2:0] = exe_opcode[11:9];
            if (exe_opcode[11:9] == 3'b000) OP2out[3] = 1'b1;
            else                            OP2out[3] = 1'b0;
            OP2out[15:4] = 12'b0;
        end else if (exe_datatype == 2'b10 && !exec[`opcEXT]) begin
            OP2out[31:16] = reg_QB[31:16];
        end
        if (exec[`opcEXTB])
            OP2out[31:8] = {24{OP2out[7]}};
    end

    // -------------------------------------------------------------------------
    // handle EA_data, data_write (VHDL 741-839) - clocked
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (Reset) begin
            store_in_tmp  <= 1'b0;
            direct_data   <= 1'b0;
            use_direct_data <= 1'b0;
            Z_error       <= 1'b0;
            writePCnext   <= 1'b0;
        end else if (clkena_lw) begin
            useStackframe2 <= 1'b0;
            direct_data    <= 1'b0;
            if (exec[`hold_OP2])
                use_direct_data <= 1'b1;
            if (set_direct_data) begin
                direct_data     <= 1'b1;
                use_direct_data <= 1'b1;
            end else if (endOPC || set[`ea_data_OP2]) begin
                use_direct_data <= 1'b0;
            end
            exec_DIRECT <= set_exec[`opcMOVE];

            if (endOPC) begin
                store_in_tmp <= 1'b0;
                Z_error      <= 1'b0;
                writePCnext  <= 1'b0;
            end else begin
                if (set_Z_error)
                    Z_error <= 1'b1;
                if (set_exec[`opcMOVE] && state == 2'b11)
                    use_direct_data <= 1'b1;
                if (state == 2'b10 || exec[`store_ea_packdata])
                    store_in_tmp <= 1'b1;
                if (direct_data && state == 2'b00)
                    store_in_tmp <= 1'b1;
            end

            if (state == 2'b10 && !exec[`hold_ea_data])
                ea_data <= data_read;
            else if (exec[`get_2ndOPC])
                ea_data <= addr;
            else if (exec[`store_ea_data] || (direct_data && state == 2'b00))
                ea_data <= last_data_read;

            if (writePC)
                data_write_tmp <= TG68_PC;
            else if (exec[`writePC_add])
                data_write_tmp <= TG68_PC_add;
            else if (micro_state == `ms_trap00) begin
                data_write_tmp <= exe_pc;
                useStackframe2 <= 1'b1;
                writePCnext    <= trap_trap | trap_trapv | exec[`trap_chk] | Z_error;
            end else if (micro_state == `ms_trap0) begin
                // only active for 010+ since in 000 writePC is true in state trap0
                if (useStackframe2)
                    data_write_tmp[15:0] <= {4'b0010, trap_vector[11:0]};  // stack frame format #2
                else begin
                    data_write_tmp[15:0] <= {4'b0000, trap_vector[11:0]};
                    writePCnext <= trap_trap | trap_trapv | exec[`trap_chk] | Z_error;
                end
            end else if (exec[`hold_dwr])
                data_write_tmp <= data_write_tmp;
            else if (exec[`exg])
                data_write_tmp <= OP1out;
            else if (exec[`get_ea_now] && ea_only)   // for pea
                data_write_tmp <= addr;
            else if (execOPC)
                data_write_tmp <= ALUout;
            else if (exec_DIRECT && state == 2'b10) begin
                data_write_tmp <= data_read;
                if (exec[`movepl])
                    data_write_tmp[31:8] <= data_write_tmp[23:0];
            end else if (exec[`movepl])
                data_write_tmp[15:0] <= reg_QB[31:16];
            else if (direct_data)
                data_write_tmp <= last_data_read;
            else if (writeSR)
                data_write_tmp[15:0] <= {trap_SR[7:0], Flags[7:0]};
            else
                data_write_tmp <= OP2out;
        end
    end

    // -------------------------------------------------------------------------
    // brief (VHDL 844-861)
    // -------------------------------------------------------------------------
    always_comb begin
        if (brief[11])
            OP1outbrief = OP1out[31:16];
        else
            OP1outbrief = {16{OP1out[15]}};
        briefdata = {OP1outbrief, OP1out[15:0]};
        if (extAddr_Mode == 1 || (CPU[1] && extAddr_Mode == 2)) begin
            case (brief[10:9])
                2'b00: briefdata = {OP1outbrief, OP1out[15:0]};
                2'b01: briefdata = {OP1outbrief[14:0], OP1out[15:0], 1'b0};
                2'b10: briefdata = {OP1outbrief[13:0], OP1out[15:0], 2'b00};
                2'b11: briefdata = {OP1outbrief[12:0], OP1out[15:0], 3'b000};
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // MEM_IO (VHDL 866-991)
    // -------------------------------------------------------------------------
    // trap_vector register (clkena_lw)
    always_ff @(posedge clk) begin
        if (clkena_lw) begin
            trap_vector[31:10] <= 22'b0;
            if (trap_berr)         trap_vector[9:0] <= {2'b00, 8'h08};
            if (trap_addr_error)   trap_vector[9:0] <= {2'b00, 8'h0C};
            if (trap_illegal)      trap_vector[9:0] <= {2'b00, 8'h10};
            if (set_Z_error)       trap_vector[9:0] <= {2'b00, 8'h14};
            if (exec[`trap_chk])   trap_vector[9:0] <= {2'b00, 8'h18};
            if (trap_trapv)        trap_vector[9:0] <= {2'b00, 8'h1C};
            if (trap_priv)         trap_vector[9:0] <= {2'b00, 8'h20};
            if (trap_trace)        trap_vector[9:0] <= {2'b00, 8'h24};
            if (trap_1010)         trap_vector[9:0] <= {2'b00, 8'h28};
            if (trap_1111)         trap_vector[9:0] <= {2'b00, 8'h2C};
            if (trap_trap)         trap_vector[9:0] <= {2'b0010, opcode[3:0], 2'b00};
            if (trap_interrupt || set_vectoraddr) trap_vector[9:0] <= {IPL_vec, 2'b00};
        end
    end

    assign trap_vector_vbr = use_VBR_Stackframe ? (trap_vector + VBR) : trap_vector;

    // memaddr_a : VHDL chains a default sign-extension that, by signal feedback,
    // sign-extends whatever low bits the conditional sets. Reproduce the fixpoint
    // by sign-extending each partial case directly to 32 bits.
    always_comb begin
        if (setdisp) begin
            if (exec[`briefext])      memaddr_a = briefdata + memaddr_delta;
            else if (setdispbyte)     memaddr_a = {{24{last_data_read[7]}}, last_data_read[7:0]};
            else                      memaddr_a = last_data_read;
        end else if (set[`presub]) begin
            if (set[`longaktion])                          memaddr_a = {{27{1'b1}}, 5'b11100};
            else if (datatype == 2'b00 && !set[`use_SP])   memaddr_a = {{27{1'b1}}, 5'b11111};
            else                                           memaddr_a = {{27{1'b1}}, 5'b11110};
        end else if (interrupt) begin
            memaddr_a = {{27{1'b1}}, 1'b1, rIPL_nr, 1'b0};
        end else begin
            memaddr_a = 32'b0;
        end
    end

    // address registers (clkena_in)
    always_ff @(posedge clk) begin
        if (clkena_in) begin
            if (exec[`get_2ndOPC] || (state == 2'b10 && memread[0]))
                tmp_TG68_PC <= addr;
            use_base           <= 1'b0;
            memaddr_delta_regb <= 32'b0;
            if (!memmaskmux[3] || exec[`mem_addsub])
                memaddr_delta_rega <= addsub_q;
            else if (set[`restore_ADDR])
                memaddr_delta_rega <= tmp_TG68_PC;
            else if (exec[`direct_delta])
                memaddr_delta_rega <= data_read;
            else if (exec[`ea_to_pc] && setstate == 2'b00)
                memaddr_delta_rega <= addr;
            else if (set[`addrlong])
                memaddr_delta_rega <= last_data_read;
            else if (setstate == 2'b00)
                memaddr_delta_rega <= TG68_PC_add;
            else if (exec[`dispouter]) begin
                memaddr_delta_rega <= ea_data;
                memaddr_delta_regb <= memaddr_a;
            end else if (set_vectoraddr)
                memaddr_delta_rega <= trap_vector_vbr;
            else begin
                memaddr_delta_rega <= memaddr_a;
                if (!interrupt && !Suppress_Base)
                    use_base <= 1'b1;
            end
            // only used for movem address update (fix for unaligned movem, mikej)
            if ((memread[0] && state[1]) || !movem_presub)
                memaddr <= addr;
        end
    end

    assign memaddr_delta = memaddr_delta_rega + memaddr_delta_regb;
    assign addr          = memaddr_reg + memaddr_delta;
    assign addr_out      = memaddr_reg + memaddr_delta;
    assign memaddr_reg   = use_base ? reg_QA : 32'b0;

    // -------------------------------------------------------------------------
    // PC Calc + fetch opcode (VHDL 996-1278)
    // -------------------------------------------------------------------------
    always_comb begin
        IPL_nr = ~IPL;

        PC_dataa = TG68_PC;
        if (TG68_PC_brw) PC_dataa = tmp_TG68_PC;

        // PC_datab : same sign-extension-by-feedback pattern as memaddr_a
        if (TG68_PC_brw && TG68_PC_word) begin
            PC_datab = last_data_read;
        end else if (TG68_PC_brw) begin
            PC_datab = {{24{opcode[7]}}, opcode[7:0]};
        end else begin
            PC_datab[0]   = 1'b0;
            PC_datab[3:1] = 3'b000;
            if (interrupt) PC_datab[2:1] = 2'b11;
            if (exec[`writePC_add]) begin
                if (writePCbig) begin
                    PC_datab[3] = 1'b1;
                    PC_datab[1] = 1'b1;
                end else
                    PC_datab[2] = 1'b1;
                if ((!use_VBR_Stackframe && (trap_trap || trap_trapv || exec[`trap_chk] || Z_error)) || writePCnext)
                    PC_datab[1] = 1'b1;
            end else if (state == 2'b00)
                PC_datab[1] = 1'b1;
            // VHDL TG68KdotC_Kernel.vhd:1006 `PC_datab(3) <= PC_datab(2)` is a
            // self-referential combinational assignment that iterates to a fixpoint,
            // i.e. bit3 follows bit2 (unless writePCbig already forced bit3=1).
            // Without this, the interrupt and writePC_add(!big) cases zero-extend
            // instead of sign-extend, leaving the PC adjustment off by 16 bytes.
            PC_datab[3]    = PC_datab[2] | PC_datab[3];
            PC_datab[31:4] = {28{PC_datab[3]}};
        end

        TG68_PC_add = PC_dataa + PC_datab;

        setopcode    = 1'b0;
        setendOPC    = 1'b0;
        setinterrupt = 1'b0;
        if (setstate == 2'b00 && next_micro_state == `ms_idle && !setnextpass &&
            (!exec_write_back || state == 2'b11) && set_rot_cnt == 6'b000001 && !set_exec[`opcCHK]) begin
            setendOPC = 1'b1;
            if (FlagsSR[2:0] < IPL_nr || IPL_nr == 3'b111 || make_trace || make_berr)
                setinterrupt = 1'b1;
            else if (!stop)
                setopcode = 1'b1;
        end
        setexecOPC = 1'b0;
        if (setstate == 2'b00 && next_micro_state == `ms_idle && !set_direct_data &&
            (!exec_write_back || (state == 2'b10 && !addrvalue)))
            setexecOPC = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (Reset) begin
            state          <= 2'b01;
            addrvalue      <= 1'b0;
            opcode         <= 16'h2E79;   // move $0,a7
            trap_interrupt <= 1'b0;
            interrupt      <= 1'b0;
            last_opc_read  <= 16'h4EF9;   // jmp nn.l
            TG68_PC        <= 32'h00000004;
            decodeOPC      <= 1'b0;
            endOPC         <= 1'b0;
            TG68_PC_word   <= 1'b0;
            execOPC        <= 1'b0;
            stop           <= 1'b0;
            rot_cnt        <= 6'b000001;
            trap_trace     <= 1'b0;
            trap_berr      <= 1'b0;
            writePCbig     <= 1'b0;
            Suppress_Base  <= 1'b0;
            make_berr      <= 1'b0;
            memmask        <= 6'b111111;
            exec_write_back <= 1'b0;
        end else begin
            if (clkena_in) begin
                memmask <= {memmask[3:0], 2'b11};
                memread <= {memread[1:0], memmaskmux[5:4]};
                if (exec[`directPC])
                    TG68_PC <= data_read;
                else if (exec[`ea_to_pc])
                    TG68_PC <= addr;
                else if ((state == 2'b00 || TG68_PC_brw) && !stop)
                    TG68_PC <= TG68_PC_add;
            end
            if (clkena_lw) begin
                interrupt  <= setinterrupt;
                decodeOPC  <= setopcode;
                endOPC     <= setendOPC;
                execOPC    <= setexecOPC;

                exe_datatype <= set_datatype;
                exe_opcode   <= opcode;

                if (!trap_berr) make_berr <= (berr | make_berr);
                else            make_berr <= 1'b0;

                stop <= set_stop | (stop & ~setinterrupt);
                if (setinterrupt) begin
                    trap_interrupt <= 1'b0;
                    trap_trace     <= 1'b0;
                    make_berr      <= 1'b0;
                    trap_berr      <= 1'b0;
                    if (make_trace)
                        trap_trace <= 1'b1;
                    else if (make_berr)
                        trap_berr <= 1'b1;
                    else begin
                        rIPL_nr        <= IPL_nr;
                        IPL_vec        <= {5'b00011, IPL_nr};
                        trap_interrupt <= 1'b1;
                    end
                end
                if (micro_state == `ms_trap0 && !IPL_autovector)
                    IPL_vec <= last_data_read[7:0];
                if (state == 2'b00) begin
                    last_opc_read <= data_read[15:0];
                    last_opc_pc   <= TG68_PC;
                end
                if (setopcode) begin
                    trap_interrupt <= 1'b0;
                    trap_trace     <= 1'b0;
                    TG68_PC_word   <= 1'b0;
                    trap_berr      <= 1'b0;
                end else if (opcode[7:0] == 8'b00000000 || opcode[7:0] == 8'b11111111 || data_is_source)
                    TG68_PC_word <= 1'b1;

                if (exec[`get_bfoffset]) begin
                    alu_width         <= bf_width;
                    alu_bf_shift      <= bf_shift;
                    alu_bf_loffset    <= bf_loffset;
                    alu_bf_ffo_offset <= bf_full_offset + bf_width + 1;
                end
                memread <= 4'b1111;
                FC_10[1] <= ~setstate[1] | (PCbase & ~setstate[0]);
                FC_10[0] <= setstate[1] & (~PCbase | setstate[0]);
                if (interrupt)
                    FC_10 <= 2'b11;

                if (state == 2'b11)
                    exec_write_back <= 1'b0;
                else if (setstate == 2'b10 && !setaddrvalue && write_back)
                    exec_write_back <= 1'b1;

                if ((state == 2'b10 && !addrvalue && write_back && setstate != 2'b10) ||
                    set_rot_cnt != 6'b000001 || (stop && !interrupt) || set_exec[`opcCHK]) begin
                    state     <= 2'b01;
                    memmask   <= 6'b111111;
                    addrvalue <= 1'b0;
                end else if (execOPC && exec_write_back) begin
                    state     <= 2'b11;
                    FC_10     <= 2'b01;
                    memmask   <= wbmemmask;
                    addrvalue <= 1'b0;
                end else begin
                    state     <= setstate;
                    addrvalue <= setaddrvalue;
                    if (setstate == 2'b01) begin
                        memmask   <= 6'b111111;
                        wbmemmask <= 6'b111111;
                    end else if (exec[`get_bfoffset]) begin
                        memmask   <= set_memmask;
                        wbmemmask <= set_memmask;
                        oddout    <= set_oddout;
                    end else if (set[`longaktion]) begin
                        memmask   <= 6'b100001;
                        wbmemmask <= 6'b100001;
                        oddout    <= 1'b0;
                    end else if (set_datatype == 2'b00 && setstate[1]) begin
                        memmask   <= 6'b101111;
                        wbmemmask <= 6'b101111;
                        if (set[`mem_byte]) oddout <= 1'b0;
                        else                oddout <= 1'b1;
                    end else begin
                        memmask   <= 6'b100111;
                        wbmemmask <= 6'b100111;
                        oddout    <= 1'b0;
                    end
                end

                if (decodeOPC) begin
                    rot_bits   <= set_rot_bits;
                    writePCbig <= 1'b0;
                end else
                    writePCbig <= set_writePCbig | writePCbig;
                if (decodeOPC || exec[`ld_rot_cnt] || rot_cnt != 6'b000001)
                    rot_cnt <= set_rot_cnt;

                if (set_Suppress_Base)
                    Suppress_Base <= 1'b1;
                else if (setstate[1] || (ea_only && set[`get_ea_now]))
                    Suppress_Base <= 1'b0;
                if (getbrief) begin
                    if (state[1]) brief <= last_opc_read[15:0];
                    else          brief <= data_read[15:0];
                end

                if (setopcode && !berr) begin
                    if (state == 2'b00) begin
                        opcode <= data_read[15:0];
                        exe_pc <= TG68_PC;
                    end else begin
                        opcode <= last_opc_read[15:0];
                        exe_pc <= last_opc_pc;
                    end
                    nextpass <= 1'b0;
                end else if (setinterrupt || setopcode) begin
                    opcode   <= 16'h4E71;   // nop
                    nextpass <= 1'b0;
                end else begin
                    if (setnextpass || regdirectsource)
                        nextpass <= 1'b1;
                end

                if (decodeOPC || interrupt)
                    trap_SR <= FlagsSR;
            end
        end
    end

    // PCbase + exec register (VHDL 1254-1277)
    always_ff @(posedge clk) begin
        if (Reset)
            PCbase <= 1'b1;
        else if (clkena_lw) begin
            PCbase <= set_PCbase | PCbase;
            if (setexecOPC || (state[1] && !movem_run))
                PCbase <= 1'b0;
        end
        if (clkena_lw) begin
            exec               <= set;
            exec[`alu_move]    <= set[`opcMOVE] | set[`alu_move];
            exec[`alu_setFlags] <= set[`opcADD] | set[`alu_setFlags];
            exec_tas           <= 1'b0;
            exec[`subidx]      <= set[`presub] | set[`subidx];
            if (setexecOPC) begin
                exec               <= set_exec | set;
                exec[`alu_move]    <= set_exec[`opcMOVE] | set[`opcMOVE] | set[`alu_move];
                exec[`alu_setFlags] <= set_exec[`opcADD] | set[`opcADD] | set[`alu_setFlags];
                exec_tas           <= set_exec_tas;
            end
            exec[`get_2ndOPC]  <= set[`get_2ndOPC] | setopcode;
        end
    end

    // -------------------------------------------------------------------------
    // prepare Bitfield Parameters (VHDL 1283-1347)
    // Reordered so each value reads the converged (final) operands.
    // -------------------------------------------------------------------------
    always_comb begin
        if (sndOPC[11]) bf_offset = {1'b0, reg_QA[4:0]};
        else            bf_offset = {1'b0, sndOPC[10:6]};

        if (sndOPC[11]) bf_full_offset = reg_QA;
        else begin
            bf_full_offset       = 32'b0;
            bf_full_offset[4:0]  = sndOPC[10:6];
        end

        // VHDL line 1329 zeroes bf_offset[4:3] when opcode[4:3]!="00"; that feeds
        // bf_bhits through feedback, so apply it before computing bf_bhits.
        if (opcode[4:3] != 2'b00)
            bf_offset[4:3] = 2'b00;

        bf_width[5] = 1'b0;
        if (sndOPC[5]) bf_width[4:0] = reg_QB[4:0] - 5'd1;
        else           bf_width[4:0] = sndOPC[4:0] - 5'd1;

        bf_bhits   = bf_width + bf_offset;
        set_oddout = ~bf_bhits[3];

        if (opcode[4:3] == 2'b00) begin
            if (opcode[10:8] == 3'b111) bf_shift = bf_bhits + 6'd1;   // INS
            else                        bf_shift = 6'd31 - bf_bhits;
            bf_shift[5] = 1'b0;
        end else begin
            if (opcode[10:8] == 3'b111) begin                          // INS
                bf_shift    = 6'b011001 + {3'b000, bf_bhits[2:0]};
                bf_shift[5] = 1'b0;
            end else
                bf_shift = {3'b000, (3'b111 - bf_bhits[2:0])};
        end

        if (opcode[10:8] == 3'b111) bf_loffset = 6'd32 - bf_shift;     // INS
        else                        bf_loffset = bf_shift;
        bf_loffset[5] = 1'b0;

        case (bf_bhits[5:3])
            3'b000:  set_memmask = 6'b101111;
            3'b001:  set_memmask = 6'b100111;
            3'b010:  set_memmask = 6'b100011;
            3'b011:  set_memmask = 6'b100001;
            default: set_memmask = 6'b100000;
        endcase
        if (setstate == 2'b00)
            set_memmask = 6'b100111;
    end

    // -------------------------------------------------------------------------
    // SR op (VHDL 1352-1417)
    // -------------------------------------------------------------------------
    always_comb begin
        if (exec[`andiSR])      SRin = FlagsSR & last_data_read[15:8];
        else if (exec[`eoriSR]) SRin = FlagsSR ^ last_data_read[15:8];
        else if (exec[`oriSR])  SRin = FlagsSR | last_data_read[15:8];
        else                    SRin = OP2out[15:8];
    end

    always_ff @(posedge clk) begin
        if (Reset) begin
            FC_2       <= 1'b1;
            SVmode     <= 1'b1;
            preSVmode  <= 1'b1;
            FlagsSR    <= 8'b00100111;
            make_trace <= 1'b0;
        end else if (clkena_lw) begin
            if (setopcode) begin
                make_trace <= FlagsSR[7];
                if (set[`changeMode]) SVmode <= ~SVmode;
                else                  SVmode <= preSVmode;
            end
            if (trap_berr || trap_illegal || trap_addr_error || trap_priv || trap_1010 || trap_1111) begin
                make_trace <= 1'b0;
                FlagsSR[7] <= 1'b0;
            end
            if (set[`changeMode]) begin
                preSVmode  <= ~preSVmode;
                FlagsSR[5] <= ~preSVmode;
                FC_2       <= ~preSVmode;
            end
            if (micro_state == `ms_trap3)
                FlagsSR[7] <= 1'b0;
            if (trap_trace && state == 2'b10)
                make_trace <= 1'b0;
            if (exec[`directSR] || set_stop)
                FlagsSR <= data_read[15:8];
            if (interrupt && trap_interrupt)
                FlagsSR[2:0] <= rIPL_nr;
            if (exec[`to_SR]) begin
                FlagsSR[7:0] <= SRin;   // SR
                FC_2         <= SRin[5];
            end else if (exec[`update_FC])
                FC_2 <= FlagsSR[5];
            if (interrupt)
                FC_2 <= 1'b1;
            if (!CPU[1]) begin
                FlagsSR[4] <= 1'b0;
                FlagsSR[6] <= 1'b0;
            end
            FlagsSR[3] <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // decode opcode (VHDL 1422-3234, combinational part) + micro_state CASE.
    // Translated in VHDL textual order; the design relies on intra-process
    // signal-feedback convergence (reads of set()/setstate/datatype before
    // their dominant writes), which the simulator settles combinationally.
    // -------------------------------------------------------------------------
    always_comb begin
        // ---- defaults (VHDL 1428-1496) ----
        TG68_PC_brw       = 1'b0;
        setstate          = 2'b00;
        setaddrvalue      = 1'b0;
        Regwrena_now      = 1'b0;
        movem_presub      = 1'b0;
        setnextpass       = 1'b0;
        regdirectsource   = 1'b0;
        setdisp           = 1'b0;
        setdispbyte       = 1'b0;
        getbrief          = 1'b0;
        dest_LDRareg      = 1'b0;
        dest_areg         = 1'b0;
        source_areg       = 1'b0;
        data_is_source    = 1'b0;
        write_back        = 1'b0;
        setstackaddr      = 1'b0;
        writePC           = 1'b0;
        ea_build_now      = 1'b0;
        set_rot_bits      = opcode[4:3];
        set_rot_cnt       = 6'b000001;
        dest_hbits        = 1'b0;
        source_lowbits    = 1'b0;
        source_LDRLbits   = 1'b0;
        source_LDRMbits   = 1'b0;
        source_2ndHbits   = 1'b0;
        source_2ndMbits   = 1'b0;
        source_2ndLbits   = 1'b0;
        dest_LDRHbits     = 1'b0;
        dest_LDRLbits     = 1'b0;
        dest_2ndHbits     = 1'b0;
        dest_2ndLbits     = 1'b0;
        ea_only           = 1'b0;
        set_direct_data   = 1'b0;
        set_exec_tas      = 1'b0;
        trap_illegal      = 1'b0;
        trap_addr_error   = 1'b0;
        trap_priv         = 1'b0;
        trap_1010         = 1'b0;
        trap_1111         = 1'b0;
        trap_trap         = 1'b0;
        trap_trapv        = 1'b0;
        trapmake          = 1'b0;
        set_vectoraddr    = 1'b0;
        writeSR           = 1'b0;
        set_stop          = 1'b0;
        set_Z_error       = 1'b0;
        check_aligned     = 1'b0;
        next_micro_state  = `ms_idle;
        build_logical     = 1'b0;
        build_bcd         = 1'b0;
        skipFetch         = make_berr;
        set_writePCbig    = 1'b0;
        set_Suppress_Base = 1'b0;
        set_PCbase        = 1'b0;

        if (rot_cnt != 6'b000001)
            set_rot_cnt = rot_cnt - 6'd1;
        set_datatype = datatype;

        set      = '0;
        set_exec = '0;

        // ---- Sourcepass datatype (VHDL 1501-1505) ----
        case (opcode[7:6])
            2'b00:   datatype = 2'b00;  // Byte
            2'b01:   datatype = 2'b01;  // Word
            default: datatype = 2'b10;  // Long
        endcase

        if (execOPC && exec_write_back)
            set[`restore_ADDR] = 1'b1;

        if (interrupt && trap_berr) begin
            next_micro_state = `ms_trap0;
            if (!preSVmode) set[`changeMode] = 1'b1;
            setstate = 2'b01;
        end
        if (trapmake && !trapd) begin
            if (CPU[1] && (trap_trapv || set_Z_error || exec[`trap_chk]))
                next_micro_state = `ms_trap00;
            else
                next_micro_state = `ms_trap0;
            if (!use_VBR_Stackframe) set[`writePC_add] = 1'b1;
            if (!preSVmode)          set[`changeMode]  = 1'b1;
            setstate = 2'b01;
        end
        if (micro_state == `ms_int1 || (interrupt && trap_trace)) begin
            if (trap_trace && CPU[1]) next_micro_state = `ms_trap00;
            else                      next_micro_state = `ms_trap0;
            if (!preSVmode) set[`changeMode] = 1'b1;
            setstate = 2'b01;
        end
        if (micro_state == `ms_int1 || (interrupt && trap_trace)) begin
            if (!preSVmode) set[`changeMode] = 1'b1;
            setstate = 2'b01;
        end

        if (setexecOPC && FlagsSR[5] != preSVmode)
            set[`changeMode] = 1'b1;

        if (interrupt && trap_interrupt) begin
            next_micro_state = `ms_int1;
            set[`update_ld]  = 1'b1;
            setstate         = 2'b10;
        end

        if (set[`changeMode]) begin
            set[`to_USP]   = 1'b1;
            set[`from_USP] = 1'b1;
            setstackaddr   = 1'b1;
        end

        // NB: the generic "get_ea_now => setstate=10" default (VHDL 1576) and the
        // longaktion rule (VHDL 1582) are evaluated at the END of this process --
        // see below. In the VHDL they read the *converged* set()/setstate signals,
        // but set[`get_ea_now] is assigned later (in the EA build and the
        // micro_state CASE, e.g. ld_nn), and setstate is assigned later too. With
        // blocking assignments, evaluating them here would read stale values and
        // never set up the read state / longaktion for those accesses.

        // ---- EA build (VHDL 1586-1636) ----
        if ((ea_build_now && decodeOPC) || exec[`ea_build]) begin
            case (opcode[5:3])
                3'b010, 3'b011, 3'b100: begin   // (An), (An)+, -(An)
                    set[`get_ea_now] = 1'b1;
                    setnextpass      = 1'b1;
                    if (opcode[3]) begin        // (An)+
                        set[`postadd] = 1'b1;
                        if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                    end
                    if (opcode[5]) begin        // -(An)
                        set[`presub] = 1'b1;
                        if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                    end
                end
                3'b101: next_micro_state = `ms_ld_dAn1;     // (d16,An)
                3'b110: begin                               // (d8,An,Xn)
                    next_micro_state = `ms_ld_AnXn1;
                    getbrief         = 1'b1;
                end
                3'b111: begin
                    case (opcode[2:0])
                        3'b000: next_micro_state = `ms_ld_nn;            // (xxxx).w
                        3'b001: begin                                   // (xxxx).l
                            set[`longaktion] = 1'b1;
                            next_micro_state = `ms_ld_nn;
                        end
                        3'b010: begin                                   // (d16,PC)
                            next_micro_state  = `ms_ld_dAn1;
                            set[`dispouter]   = 1'b1;
                            set_Suppress_Base = 1'b1;
                            set_PCbase        = 1'b1;
                        end
                        3'b011: begin                                   // (d8,PC,Xn)
                            next_micro_state  = `ms_ld_AnXn1;
                            getbrief          = 1'b1;
                            set[`dispouter]   = 1'b1;
                            set_Suppress_Base = 1'b1;
                            set_PCbase        = 1'b1;
                        end
                        3'b100: begin                                   // #data
                            setnextpass     = 1'b1;
                            set_direct_data = 1'b1;
                            if (datatype == 2'b10) set[`longaktion] = 1'b1;
                        end
                        default: ;
                    endcase
                end
                default: ;
            endcase
        end

        // ---- prepare opcode (VHDL 1640-3181) ----
        case (opcode[15:12])
        // 0000 -------------------------------------------------------------
        4'b0000: begin
            if (opcode[8] && opcode[5:3] == 3'b001) begin   // movep
                datatype       = 2'b00;       // Byte
                set[`use_SP]   = 1'b1;        // addr+2
                set[`no_Flags] = 1'b1;
                if (!opcode[7]) begin         // to register
                    set_exec[`Regwrena] = 1'b1;
                    set_exec[`opcMOVE]  = 1'b1;
                    set[`movepl]        = 1'b1;
                end
                if (decodeOPC) begin
                    if (opcode[6]) set[`movepl] = 1'b1;
                    if (!opcode[7]) set_direct_data = 1'b1;  // to register
                    next_micro_state = `ms_movep1;
                end
                if (setexecOPC) dest_hbits = 1'b1;
            end else begin
                if (opcode[8] || opcode[11:9] == 3'b100) begin   // Bits
                    if (opcode[5:3] != 3'b001 &&
                        (opcode[8:3] != 6'b000111 || !opcode[2]) &&
                        (opcode[8:2] != 7'b1001111 || opcode[1:0] == 2'b00) &&
                        (opcode[7:6] == 2'b00 || opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                        set_exec[`opcBITS]     = 1'b1;
                        set_exec[`ea_data_OP1] = 1'b1;
                        if (opcode[7:6] != 2'b00) begin
                            if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                            write_back = 1'b1;
                        end
                        if (opcode[5:4] == 2'b00) datatype = 2'b10;  // Long
                        else                      datatype = 2'b00;  // Byte
                        if (!opcode[8]) begin
                            if (decodeOPC) begin
                                next_micro_state   = `ms_nop;
                                set[`get_2ndOPC]   = 1'b1;
                                set[`ea_build]     = 1'b1;
                            end
                        end else
                            ea_build_now = 1'b1;
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end else if (opcode[8:6] == 3'b011) begin   // CAS/CAS2/CMP2/CHK2
                    if (CPU[1]) begin
                        if (opcode[11]) begin               // CAS/CAS2
                            if ((opcode[10:9] != 2'b00 &&
                                 opcode[5:4] != 2'b00 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) ||
                                (opcode[10] && opcode[5:0] == 6'b111100)) begin
                                case (opcode[10:9])
                                    2'b01:   datatype = 2'b00;  // Byte
                                    2'b10:   datatype = 2'b01;  // Word
                                    default: datatype = 2'b10;  // Long
                                endcase
                                if (opcode[10] && opcode[5:0] == 6'b111100) begin   // CAS2
                                    if (decodeOPC) begin
                                        set[`get_2ndOPC] = 1'b1;
                                        next_micro_state = `ms_cas21;
                                    end
                                end else begin                                      // CAS
                                    if (decodeOPC) begin
                                        next_micro_state = `ms_nop;
                                        set[`get_2ndOPC] = 1'b1;
                                        set[`ea_build]   = 1'b1;
                                    end
                                    if (micro_state == `ms_idle && nextpass) begin
                                        source_2ndLbits   = 1'b1;
                                        set[`ea_data_OP1] = 1'b1;
                                        set[`addsub]      = 1'b1;
                                        set[`alu_exec]    = 1'b1;
                                        set[`alu_setFlags]= 1'b1;
                                        setstate          = 2'b01;
                                        next_micro_state  = `ms_cas1;
                                    end
                                end
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end else begin   // CMP2/CHK2
                            if (opcode[10:9] != 2'b11 &&
                                opcode[5:4] != 2'b00 && opcode[5:3] != 3'b011 && opcode[5:3] != 3'b100 && opcode[5:2] != 4'b1111) begin
                                set[`trap_chk] = 1'b1;
                                datatype       = opcode[10:9];
                                if (decodeOPC) begin
                                    next_micro_state = `ms_nop;
                                    set[`get_2ndOPC] = 1'b1;
                                    set[`ea_build]   = 1'b1;
                                end
                                if (set[`get_ea_now]) begin
                                    set[`mem_addsub] = 1'b1;
                                    set[`OP1addr]    = 1'b1;
                                end
                                if (micro_state == `ms_idle && nextpass) begin
                                    setstate     = 2'b10;
                                    set[`hold_OP2] = 1'b1;
                                    if (exe_datatype != 2'b00) check_aligned = 1'b1;
                                    next_micro_state = `ms_chk20;
                                end
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end else if (opcode[11:9] == 3'b111) begin   // MOVES not in 68000
                    if (CPU[0] && opcode[7:6] != 2'b11 && opcode[5:4] != 2'b00 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                        if (SVmode) begin
                            // TODO: implement MOVES (mirrors VHDL TODO)
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end else begin
                            trap_priv = 1'b1;
                            trapmake  = 1'b1;
                        end
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end else begin   // andi, ...xxxi
                    if (opcode[7:6] != 2'b11 && opcode[5:3] != 3'b001) begin
                        if (opcode[11:9] == 3'b000) begin   // ORI
                            if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00 || (opcode[2:0] == 3'b100 && !opcode[7]))
                                set_exec[`opcOR] = 1'b1;
                            else begin trap_illegal = 1'b1; trapmake = 1'b1; end
                        end
                        if (opcode[11:9] == 3'b001) begin   // ANDI
                            if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00 || (opcode[2:0] == 3'b100 && !opcode[7]))
                                set_exec[`opcAND] = 1'b1;
                            else begin trap_illegal = 1'b1; trapmake = 1'b1; end
                        end
                        if (opcode[11:9] == 3'b010 || opcode[11:9] == 3'b011) begin   // SUBI, ADDI
                            if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)
                                set_exec[`opcADD] = 1'b1;
                            else begin trap_illegal = 1'b1; trapmake = 1'b1; end
                        end
                        if (opcode[11:9] == 3'b101) begin   // EORI
                            if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00 || (opcode[2:0] == 3'b100 && !opcode[7]))
                                set_exec[`opcEOR] = 1'b1;
                            else begin trap_illegal = 1'b1; trapmake = 1'b1; end
                        end
                        if (opcode[11:9] == 3'b110) begin   // CMPI
                            if (opcode[5:3] != 3'b111 || !opcode[2])
                                set_exec[`opcCMP] = 1'b1;
                            else begin trap_illegal = 1'b1; trapmake = 1'b1; end
                        end
                        if (set_exec[`opcOR] || set_exec[`opcAND] || set_exec[`opcADD] || set_exec[`opcEOR] || set_exec[`opcCMP]) begin
                            if (!opcode[7] && opcode[5:0] == 6'b111100 && (set_exec[`opcAND] || set_exec[`opcOR] || set_exec[`opcEOR])) begin   // SR
                                if (decodeOPC && !SVmode && opcode[6]) begin   // SR
                                    trap_priv = 1'b1;
                                    trapmake  = 1'b1;
                                end else begin
                                    set[`no_Flags] = 1'b1;
                                    if (decodeOPC) begin
                                        if (opcode[6]) set[`to_SR] = 1'b1;
                                        set[`to_CCR]     = 1'b1;
                                        set[`andiSR]     = set_exec[`opcAND];
                                        set[`eoriSR]     = set_exec[`opcEOR];
                                        set[`oriSR]      = set_exec[`opcOR];
                                        setstate         = 2'b01;
                                        next_micro_state = `ms_nopnop;
                                    end
                                end
                            end else if (!opcode[7] || opcode[5:0] != 6'b111100 || !(set_exec[`opcAND] || set_exec[`opcOR] || set_exec[`opcEOR])) begin
                                if (decodeOPC) begin
                                    next_micro_state = `ms_andi;
                                    set[`get_2ndOPC] = 1'b1;
                                    set[`ea_build]   = 1'b1;
                                    set_direct_data  = 1'b1;
                                    if (datatype == 2'b10) set[`longaktion] = 1'b1;
                                end
                                if (opcode[5:4] != 2'b00) set_exec[`ea_data_OP1] = 1'b1;
                                if (opcode[11:9] != 3'b110) begin   // not CMPI
                                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                    write_back = 1'b1;
                                end
                                if (opcode[10:9] == 2'b10) set[`addsub] = 1'b1;   // CMPI, SUBI
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end
            end
        end
        // 0001, 0010, 0011 ------------------------------------------------
        4'b0001, 4'b0010, 4'b0011: begin   // move.b, move.l, move.w
            if ((opcode[11:10] == 2'b00 || opcode[8:6] != 3'b111) &&
                (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00) &&
                (opcode[13] || (opcode[8:6] != 3'b001 && opcode[5:3] != 3'b001))) begin
                set_exec[`opcMOVE] = 1'b1;
                ea_build_now       = 1'b1;
                if (opcode[8:6] == 3'b001) set[`no_Flags] = 1'b1;
                if (opcode[5:4] == 2'b00) begin   // Dn, An
                    if (opcode[8:7] == 2'b00) set_exec[`Regwrena] = 1'b1;
                end
                case (opcode[13:12])
                    2'b01:   datatype = 2'b00;  // Byte
                    2'b10:   datatype = 2'b10;  // Long
                    default: datatype = 2'b01;  // Word
                endcase
                source_lowbits = 1'b1;            // Dn=>  An=>
                if (opcode[3]) source_areg = 1'b1;
                if (nextpass || opcode[5:4] == 2'b00) begin
                    dest_hbits = 1'b1;
                    if (opcode[8:6] != 3'b000) dest_areg = 1'b1;
                end
                if (micro_state == `ms_idle && (nextpass || (opcode[5:4] == 2'b00 && decodeOPC))) begin
                    case (opcode[8:6])   // destination
                        3'b000, 3'b001: set_exec[`Regwrena] = 1'b1;   // Dn, An
                        3'b010, 3'b011, 3'b100: begin                 // -(an)+
                            if (opcode[6]) begin   // (An)+
                                set[`postadd] = 1'b1;
                                if (opcode[11:9] == 3'b111) set[`use_SP] = 1'b1;
                            end
                            if (opcode[8]) begin   // -(An)
                                set[`presub] = 1'b1;
                                if (opcode[11:9] == 3'b111) set[`use_SP] = 1'b1;
                            end
                            setstate         = 2'b11;
                            next_micro_state = `ms_nop;
                            if (!nextpass) set[`write_reg] = 1'b1;
                        end
                        3'b101: next_micro_state = `ms_st_dAn1;       // (d16,An)
                        3'b110: begin                                 // (d8,An,Xn)
                            next_micro_state = `ms_st_AnXn1;
                            getbrief         = 1'b1;
                        end
                        3'b111: begin
                            case (opcode[11:9])
                                3'b000: next_micro_state = `ms_st_nn;     // (xxxx).w
                                3'b001: begin                             // (xxxx).l
                                    set[`longaktion] = 1'b1;
                                    next_micro_state = `ms_st_nn;
                                end
                                default: ;
                            endcase
                        end
                        default: ;
                    endcase
                end
            end else begin
                trap_illegal = 1'b1;
                trapmake     = 1'b1;
            end
        end
        // 0100 -------------------------------------------------------------
        4'b0100: begin   // rts_group
            if (opcode[8]) begin   // lea, extb.l, chk
                if (opcode[6]) begin   // lea, extb.l
                    if (opcode[11:9] == 3'b100 && opcode[5:3] == 3'b000) begin   // extb.l
                        if (opcode[7] && CPU[1]) begin
                            source_lowbits      = 1'b1;
                            set_exec[`opcEXT]   = 1'b1;
                            set_exec[`opcEXTB]  = 1'b1;
                            set_exec[`opcMOVE]  = 1'b1;
                            set_exec[`Regwrena] = 1'b1;
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end else begin   // lea
                        if (opcode[7] && (opcode[5] || opcode[4:3] == 2'b10) &&
                            opcode[5:3] != 3'b100 && opcode[5:2] != 4'b1111) begin
                            source_lowbits      = 1'b1;
                            source_areg         = 1'b1;
                            ea_only             = 1'b1;
                            set_exec[`Regwrena] = 1'b1;
                            set_exec[`opcMOVE]  = 1'b1;
                            set[`no_Flags]      = 1'b1;
                            if (opcode[5:3] == 3'b010) begin   // lea (Am),An
                                dest_areg  = 1'b1;
                                dest_hbits = 1'b1;
                            end else
                                ea_build_now = 1'b1;
                            if (set[`get_ea_now]) begin
                                setstate        = 2'b01;
                                set_direct_data = 1'b1;
                            end
                            if (setexecOPC) begin
                                dest_areg  = 1'b1;
                                dest_hbits = 1'b1;
                            end
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end
                end else begin   // chk
                    if (opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                        if (opcode[7]) begin
                            datatype       = 2'b01;  // Word
                            set[`trap_chk] = 1'b1;
                            if ((!c_out[1] || OP1out[15] || OP2out[15]) && exec[`opcCHK])
                                trapmake = 1'b1;
                        end else if (CPU[1]) begin   // chk long for 68020
                            datatype       = 2'b10;  // Long
                            set[`trap_chk] = 1'b1;
                            if ((!c_out[2] || OP1out[31] || OP2out[31]) && exec[`opcCHK])
                                trapmake = 1'b1;
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                        if (opcode[7] || CPU[1]) begin
                            if ((nextpass || opcode[5:4] == 2'b00) && !exec[`opcCHK] && micro_state == `ms_idle)
                                set_exec[`opcCHK] = 1'b1;
                            ea_build_now  = 1'b1;
                            set[`addsub]  = 1'b1;
                            if (setexecOPC) begin
                                dest_hbits     = 1'b1;
                                source_lowbits = 1'b1;
                            end
                        end
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end
            end else begin
                case (opcode[11:9])
                    3'b000: begin
                        if (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                            if (opcode[7:6] == 2'b11) begin   // move from SR
                                if (SR_Read == 0 || (!CPU[0] && SR_Read == 2) || SVmode) begin
                                    ea_build_now         = 1'b1;
                                    set_exec[`opcMOVESR] = 1'b1;
                                    datatype             = 2'b01;
                                    write_back           = 1'b1;
                                    if (CPU[0] && state == 2'b10 && !addrvalue) skipFetch = 1'b1;
                                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                end else begin
                                    trap_priv = 1'b1;
                                    trapmake  = 1'b1;
                                end
                            end else begin   // negx
                                ea_build_now        = 1'b1;
                                set_exec[`use_XZFlag] = 1'b1;
                                write_back          = 1'b1;
                                set_exec[`opcADD]   = 1'b1;
                                set[`addsub]        = 1'b1;
                                source_lowbits      = 1'b1;
                                if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                if (setexecOPC) set[`OP1out_zero] = 1'b1;
                            end
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end
                    3'b001: begin
                        if (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                            if (opcode[7:6] == 2'b11) begin   // move from CCR 68010
                                if (SR_Read == 1 || (CPU[0] && SR_Read == 2)) begin
                                    ea_build_now         = 1'b1;
                                    set_exec[`opcMOVESR] = 1'b1;
                                    datatype             = 2'b01;
                                    write_back           = 1'b1;
                                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                end else begin
                                    trap_illegal = 1'b1;
                                    trapmake     = 1'b1;
                                end
                            end else begin   // clr
                                ea_build_now      = 1'b1;
                                write_back        = 1'b1;
                                set_exec[`opcAND] = 1'b1;
                                if (CPU[0] && state == 2'b10 && !addrvalue) skipFetch = 1'b1;
                                if (setexecOPC) set[`OP1out_zero] = 1'b1;
                                if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                            end
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end
                    3'b010: begin
                        if (opcode[7:6] == 2'b11) begin   // move to CCR
                            if (opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                                ea_build_now   = 1'b1;
                                datatype       = 2'b01;
                                source_lowbits = 1'b1;
                                if ((decodeOPC && opcode[5:4] == 2'b00) || (state == 2'b10 && !addrvalue) || direct_data)
                                    set[`to_CCR] = 1'b1;
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end else begin   // neg
                            if (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                                ea_build_now      = 1'b1;
                                write_back        = 1'b1;
                                set_exec[`opcADD] = 1'b1;
                                set[`addsub]      = 1'b1;
                                source_lowbits    = 1'b1;
                                if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                if (setexecOPC) set[`OP1out_zero] = 1'b1;
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end
                    end
                    3'b011: begin   // not, move toSR
                        if (opcode[7:6] == 2'b11) begin   // move to SR
                            if (opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                                if (SVmode) begin
                                    ea_build_now   = 1'b1;
                                    datatype       = 2'b01;
                                    source_lowbits = 1'b1;
                                    if ((decodeOPC && opcode[5:4] == 2'b00) || (state == 2'b10 && !addrvalue) || direct_data) begin
                                        set[`to_SR]  = 1'b1;
                                        set[`to_CCR] = 1'b1;
                                    end
                                    if (exec[`to_SR] || (decodeOPC && opcode[5:4] == 2'b00) || (state == 2'b10 && !addrvalue) || direct_data)
                                        setstate = 2'b01;
                                end else begin
                                    trap_priv = 1'b1;
                                    trapmake  = 1'b1;
                                end
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end else begin   // not
                            if (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                                ea_build_now           = 1'b1;
                                write_back             = 1'b1;
                                set_exec[`opcEOR]      = 1'b1;
                                set_exec[`ea_data_OP1] = 1'b1;
                                if (opcode[5:3] == 3'b000) set_exec[`Regwrena] = 1'b1;
                                if (setexecOPC) set[`OP2out_one] = 1'b1;
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end
                    end
                    3'b100, 3'b110: begin
                        if (opcode[7]) begin   // movem, ext
                            if (opcode[5:3] == 3'b000 && !opcode[10]) begin   // ext
                                source_lowbits      = 1'b1;
                                set_exec[`opcEXT]   = 1'b1;
                                set_exec[`opcMOVE]  = 1'b1;
                                set_exec[`Regwrena] = 1'b1;
                                if (!opcode[6]) begin
                                    datatype           = 2'b01;  // WORD
                                    set_exec[`opcEXTB] = 1'b1;
                                end
                            end else begin   // movem
                                if ((opcode[10] || ((opcode[5] || opcode[4:3] == 2'b10) &&
                                     (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00))) &&
                                    (!opcode[10] || (opcode[5:4] != 2'b00 && opcode[5:3] != 3'b100 && opcode[5:2] != 4'b1111))) begin
                                    ea_only        = 1'b1;
                                    set[`no_Flags] = 1'b1;
                                    if (!opcode[6]) datatype = 2'b01;   // Word transfer
                                    if ((opcode[5:3] == 3'b100 || opcode[5:3] == 3'b011) && state == 2'b01) begin   // -(An), (An)+
                                        set_exec[`save_memaddr] = 1'b1;
                                        set_exec[`Regwrena]     = 1'b1;
                                    end
                                    if (opcode[5:3] == 3'b100) begin   // -(An)
                                        movem_presub  = 1'b1;
                                        set[`subidx]  = 1'b1;
                                    end
                                    if (state == 2'b10 && !addrvalue) begin
                                        set[`Regwrena] = 1'b1;
                                        set[`opcMOVE]  = 1'b1;
                                    end
                                    if (decodeOPC) begin
                                        set[`get_2ndOPC] = 1'b1;
                                        if (opcode[5:3] == 3'b010 || opcode[5:3] == 3'b011 || opcode[5:3] == 3'b100)
                                            next_micro_state = `ms_movem1;
                                        else begin
                                            next_micro_state = `ms_nop;
                                            set[`ea_build]   = 1'b1;
                                        end
                                    end
                                    if (set[`get_ea_now]) begin
                                        if (movem_run) begin
                                            set[`movem_action] = 1'b1;
                                            if (!opcode[10]) begin
                                                setstate       = 2'b11;
                                                set[`write_reg]= 1'b1;
                                            end else
                                                setstate = 2'b10;
                                            next_micro_state = `ms_movem2;
                                            set[`mem_addsub] = 1'b1;
                                        end else
                                            setstate = 2'b01;
                                    end
                                end else begin
                                    trap_illegal = 1'b1;
                                    trapmake     = 1'b1;
                                end
                            end
                        end else begin
                            if (opcode[10]) begin   // MUL.L, DIV.L 68020
                                if (opcode[8:7] == 2'b00 && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00) &&
                                    MUL_Hardware == 1 && (!opcode[6] && (MUL_Mode == 1 || (CPU[1] && MUL_Mode == 2)))) begin
                                    // FPGA Multiplier for long
                                    if (decodeOPC) begin
                                        next_micro_state = `ms_nop;
                                        set[`get_2ndOPC] = 1'b1;
                                        set[`ea_build]   = 1'b1;
                                    end
                                    if ((micro_state == `ms_idle && nextpass) || (opcode[5:4] == 2'b00 && exec[`ea_build])) begin
                                        dest_2ndHbits      = 1'b1;
                                        datatype           = 2'b10;
                                        set[`opcMULU]      = 1'b1;
                                        set[`write_lowlong]= 1'b1;
                                        if (sndOPC[10]) begin
                                            setstate         = 2'b01;
                                            next_micro_state = `ms_mul_end2;
                                        end
                                        set[`Regwrena] = 1'b1;
                                    end
                                    source_lowbits = 1'b1;
                                    datatype       = 2'b10;
                                end else if (opcode[8:7] == 2'b00 && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00) &&
                                    ((opcode[6] && (DIV_Mode == 1 || (CPU[1] && DIV_Mode == 2))) ||
                                     (!opcode[6] && (MUL_Mode == 1 || (CPU[1] && MUL_Mode == 2))))) begin
                                    // no FPGA Multiplier
                                    if (decodeOPC) begin
                                        next_micro_state = `ms_nop;
                                        set[`get_2ndOPC] = 1'b1;
                                        set[`ea_build]   = 1'b1;
                                    end
                                    if ((micro_state == `ms_idle && nextpass) || (opcode[5:4] == 2'b00 && exec[`ea_build])) begin
                                        setstate        = 2'b01;
                                        dest_2ndHbits   = 1'b1;
                                        source_2ndLbits = 1'b1;
                                        if (opcode[6]) next_micro_state = `ms_div1;
                                        else begin
                                            next_micro_state = `ms_mul1;
                                            set[`ld_rot_cnt] = 1'b1;
                                        end
                                    end
                                    source_lowbits = 1'b1;
                                    if (nextpass || (opcode[5:4] == 2'b00 && decodeOPC)) dest_hbits = 1'b1;
                                    datatype = 2'b10;
                                end else begin
                                    trap_illegal = 1'b1;
                                    trapmake     = 1'b1;
                                end
                            end else begin   // pea, swap
                                if (opcode[6]) begin
                                    datatype = 2'b10;
                                    if (opcode[5:3] == 3'b000) begin   // swap
                                        set_exec[`opcSWAP]  = 1'b1;
                                        set_exec[`Regwrena] = 1'b1;
                                    end else if (opcode[5:3] == 3'b001) begin   // bkpt
                                        trap_illegal = 1'b1;
                                        trapmake     = 1'b1;
                                    end else begin   // pea
                                        if ((opcode[5] || opcode[4:3] == 2'b10) && opcode[5:3] != 3'b100 && opcode[5:2] != 4'b1111) begin
                                            ea_only      = 1'b1;
                                            ea_build_now = 1'b1;
                                            if (nextpass && micro_state == `ms_idle) begin
                                                set[`presub]     = 1'b1;
                                                setstackaddr     = 1'b1;
                                                setstate         = 2'b11;
                                                next_micro_state = `ms_nop;
                                            end
                                            if (set[`get_ea_now]) setstate = 2'b01;
                                        end else begin
                                            trap_illegal = 1'b1;
                                            trapmake     = 1'b1;
                                        end
                                    end
                                end else begin
                                    if (opcode[5:3] == 3'b001) begin   // link.l
                                        datatype            = 2'b10;
                                        set_exec[`opcADD]   = 1'b1;   // for displacement
                                        set_exec[`Regwrena] = 1'b1;
                                        set[`no_Flags]      = 1'b1;
                                        if (decodeOPC) begin
                                            set[`linksp]        = 1'b1;
                                            set[`longaktion]    = 1'b1;
                                            next_micro_state    = `ms_link1;
                                            set[`presub]        = 1'b1;
                                            setstackaddr        = 1'b1;
                                            set[`mem_addsub]    = 1'b1;
                                            source_lowbits      = 1'b1;
                                            source_areg         = 1'b1;
                                            set[`store_ea_data] = 1'b1;
                                        end
                                    end else begin   // nbcd
                                        if (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                                            ea_build_now          = 1'b1;
                                            set_exec[`use_XZFlag] = 1'b1;
                                            write_back            = 1'b1;
                                            set_exec[`opcADD]     = 1'b1;
                                            set_exec[`opcSBCD]    = 1'b1;
                                            set[`addsub]          = 1'b1;
                                            source_lowbits        = 1'b1;
                                            if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                            if (setexecOPC) set[`OP1out_zero] = 1'b1;
                                        end else begin
                                            trap_illegal = 1'b1;
                                            trapmake     = 1'b1;
                                        end
                                    end
                                end
                            end
                        end
                    end
                    3'b101: begin   // tst, tas  4aFC - illegal
                        if (opcode[7:3] == 5'b11111 && opcode[2:1] != 2'b00) begin   // 0x4AFC illegal, 0x4AFB BKP Sinclair QL
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end else begin
                            if ((opcode[7:6] != 2'b11 || (opcode[5:3] != 3'b001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00))) &&
                                ((opcode[7:6] != 2'b00 || (opcode[5:3] != 3'b001)) && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00))) begin
                                ea_build_now = 1'b1;
                                if (setexecOPC) begin
                                    source_lowbits = 1'b1;
                                    if (opcode[3]) source_areg = 1'b1;   // MC68020...
                                end
                                set_exec[`opcMOVE] = 1'b1;
                                if (opcode[7:6] == 2'b11) begin   // tas
                                    set_exec_tas = 1'b1;
                                    write_back   = 1'b1;
                                    datatype     = 2'b00;  // Byte
                                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                                end
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end
                    end
                    3'b111: begin   // 4EXX
                        if (opcode[7]) begin   // jsr, jmp
                            if ((opcode[5] || opcode[4:3] == 2'b10) && opcode[5:3] != 3'b100 && opcode[5:2] != 4'b1111) begin
                                datatype     = 2'b10;
                                ea_only      = 1'b1;
                                ea_build_now = 1'b1;
                                if (exec[`ea_to_pc]) next_micro_state = `ms_nop;
                                if (nextpass && micro_state == `ms_idle && !opcode[6]) begin
                                    set[`presub]     = 1'b1;
                                    setstackaddr     = 1'b1;
                                    setstate         = 2'b11;
                                    next_micro_state = `ms_nopnop;
                                end
                                if (micro_state == `ms_ld_AnXn1 && !brief[8]) skipFetch = 1'b1;   // JMP/JSR n(Ax,Dn)
                                if (state == 2'b00) writePC = 1'b1;
                                set[`hold_dwr] = 1'b1;
                                if (set[`get_ea_now]) begin   // jsr
                                    if (!exec[`longaktion] || long_done) skipFetch = 1'b1;
                                    setstate      = 2'b01;
                                    set[`ea_to_pc] = 1'b1;
                                end
                            end else begin
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end
                        end else begin
                            casez (opcode[6:0])
                                7'b100????: begin   // trap
                                    trap_trap = 1'b1;
                                    trapmake  = 1'b1;
                                end
                                7'b1010???: begin   // link word
                                    datatype            = 2'b10;
                                    set_exec[`opcADD]   = 1'b1;   // for displacement
                                    set_exec[`Regwrena] = 1'b1;
                                    set[`no_Flags]      = 1'b1;
                                    if (decodeOPC) begin
                                        next_micro_state    = `ms_link1;
                                        set[`presub]        = 1'b1;
                                        setstackaddr        = 1'b1;
                                        set[`mem_addsub]    = 1'b1;
                                        source_lowbits      = 1'b1;
                                        source_areg         = 1'b1;
                                        set[`store_ea_data] = 1'b1;
                                    end
                                end
                                7'b1011???: begin   // unlink
                                    datatype            = 2'b10;
                                    set_exec[`Regwrena] = 1'b1;
                                    set_exec[`opcMOVE]  = 1'b1;
                                    set[`no_Flags]      = 1'b1;
                                    if (decodeOPC) begin
                                        setstate         = 2'b01;
                                        next_micro_state = `ms_unlink1;
                                        set[`opcMOVE]    = 1'b1;
                                        set[`Regwrena]   = 1'b1;
                                        setstackaddr     = 1'b1;
                                        source_lowbits   = 1'b1;
                                        source_areg      = 1'b1;
                                    end
                                end
                                7'b1100???: begin   // move An,USP
                                    if (SVmode) begin
                                        set[`to_USP]   = 1'b1;
                                        source_lowbits = 1'b1;
                                        source_areg    = 1'b1;
                                        datatype       = 2'b10;
                                    end else begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end
                                end
                                7'b1101???: begin   // move USP,An
                                    if (SVmode) begin
                                        set[`from_USP]      = 1'b1;
                                        datatype            = 2'b10;
                                        set_exec[`Regwrena] = 1'b1;
                                    end else begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end
                                end
                                7'b1110000: begin   // reset
                                    if (!SVmode) begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end else begin
                                        set[`opcRESET] = 1'b1;
                                        if (decodeOPC) begin
                                            set[`ld_rot_cnt] = 1'b1;
                                            set_rot_cnt      = 6'b000000;
                                        end
                                    end
                                end
                                7'b1110001: ;   // nop
                                7'b1110010: begin   // stop
                                    if (!SVmode) begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end else begin
                                        if (decodeOPC) begin
                                            setnextpass = 1'b1;
                                            set_stop    = 1'b1;
                                        end
                                        if (stop) skipFetch = 1'b1;
                                    end
                                end
                                7'b1110011, 7'b1110111: begin   // rte/rtr
                                    if (SVmode || opcode[2]) begin
                                        if (decodeOPC) begin
                                            setstate     = 2'b10;
                                            set[`postadd]= 1'b1;
                                            setstackaddr = 1'b1;
                                            if (opcode[2]) set[`directCCR] = 1'b1;
                                            else           set[`directSR]  = 1'b1;
                                            next_micro_state = `ms_rte1;
                                        end
                                    end else begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end
                                end
                                7'b1110100: begin   // rtd
                                    datatype = 2'b10;
                                    if (decodeOPC) begin
                                        setstate          = 2'b10;
                                        set[`postadd]     = 1'b1;
                                        setstackaddr      = 1'b1;
                                        set[`direct_delta]= 1'b1;
                                        set[`directPC]    = 1'b1;
                                        set_direct_data   = 1'b1;
                                        next_micro_state  = `ms_rtd1;
                                    end
                                end
                                7'b1110101: begin   // rts
                                    datatype = 2'b10;
                                    if (decodeOPC) begin
                                        setstate          = 2'b10;
                                        set[`postadd]     = 1'b1;
                                        setstackaddr      = 1'b1;
                                        set[`direct_delta]= 1'b1;
                                        set[`directPC]    = 1'b1;
                                        next_micro_state  = `ms_nopnop;
                                    end
                                end
                                7'b1110110: begin   // trapv
                                    if (decodeOPC) setstate = 2'b01;
                                    if (Flags[1] && state == 2'b01) begin
                                        trap_trapv = 1'b1;
                                        trapmake   = 1'b1;
                                    end
                                end
                                7'b1111010, 7'b1111011: begin   // movec
                                    if (CPU == 2'b00) begin
                                        trap_illegal = 1'b1;
                                        trapmake     = 1'b1;
                                    end else if (!SVmode) begin
                                        trap_priv = 1'b1;
                                        trapmake  = 1'b1;
                                    end else begin
                                        datatype = 2'b10;   // Long
                                        if (last_data_read[11:0] == 12'h800) begin
                                            set[`from_USP] = 1'b1;
                                            if (opcode[0]) set[`to_USP] = 1'b1;
                                        end
                                        if (!opcode[0]) set_exec[`movec_rd] = 1'b1;
                                        else            set_exec[`movec_wr] = 1'b1;
                                        if (decodeOPC) begin
                                            next_micro_state = `ms_movec1;
                                            getbrief         = 1'b1;
                                        end
                                    end
                                end
                                default: begin
                                    trap_illegal = 1'b1;
                                    trapmake     = 1'b1;
                                end
                            endcase
                        end
                    end
                    default: ;
                endcase
            end
        end
        // 0101 -------------------------------------------------------------
        4'b0101: begin   // subq, addq, dbcc, scc, trapcc
            if (opcode[7:6] == 2'b11) begin   // dbcc
                if (opcode[5:3] == 3'b001) begin   // dbcc
                    if (decodeOPC) begin
                        next_micro_state = `ms_dbcc1;
                        set[`OP2out_one] = 1'b1;
                        data_is_source   = 1'b1;
                    end
                end else if (opcode[5:3] == 3'b111 && (opcode[2:1] == 2'b01 || opcode[2:0] == 3'b100)) begin   // trapcc
                    if (CPU[1]) begin   // only 68020+
                        if (opcode[2:1] == 2'b01) begin
                            if (decodeOPC) begin
                                if (opcode[0]) set[`longaktion] = 1'b1;   // long
                                next_micro_state = `ms_nop;
                            end
                        end else begin
                            if (decodeOPC) setstate = 2'b01;
                        end
                        if (exe_condition && !decodeOPC) begin
                            trap_trapv = 1'b1;
                            trapmake   = 1'b1;
                        end
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end else if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00) begin   // Scc
                    datatype          = 2'b00;  // Byte
                    ea_build_now      = 1'b1;
                    write_back        = 1'b1;
                    set_exec[`opcScc] = 1'b1;
                    if (CPU[0] && state == 2'b10 && !addrvalue) skipFetch = 1'b1;
                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end else begin   // addq, subq
                if (opcode[7:3] != 5'b00001 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                    ea_build_now = 1'b1;
                    if (opcode[5:3] == 3'b001) set[`no_Flags] = 1'b1;
                    if (opcode[8]) set[`addsub] = 1'b1;
                    write_back             = 1'b1;
                    set_exec[`opcADDQ]     = 1'b1;
                    set_exec[`opcADD]      = 1'b1;
                    set_exec[`ea_data_OP1] = 1'b1;
                    if (opcode[5:4] == 2'b00) set_exec[`Regwrena] = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end
        end
        // 0110 -------------------------------------------------------------
        4'b0110: begin   // bra, bsr, bcc
            datatype = 2'b10;
            if (micro_state == `ms_idle) begin
                if (opcode[11:8] == 4'b0001) begin   // bsr
                    set[`presub] = 1'b1;
                    setstackaddr = 1'b1;
                    if (opcode[7:0] == 8'b11111111) begin
                        next_micro_state = `ms_bsr2;
                        set[`longaktion] = 1'b1;
                    end else if (opcode[7:0] == 8'b00000000) begin
                        next_micro_state = `ms_bsr2;
                    end else begin
                        next_micro_state = `ms_bsr1;
                        setstate         = 2'b11;
                        writePC          = 1'b1;
                    end
                end else begin   // bra
                    if (opcode[7:0] == 8'b11111111) begin
                        next_micro_state = `ms_bra1;
                        set[`longaktion] = 1'b1;
                    end else if (opcode[7:0] == 8'b00000000) begin
                        next_micro_state = `ms_bra1;
                    end else begin
                        setstate         = 2'b01;
                        next_micro_state = `ms_bra1;
                    end
                end
            end
        end
        // 0111 -------------------------------------------------------------
        4'b0111: begin   // moveq
            if (!opcode[8]) begin
                datatype            = 2'b10;  // Long
                set_exec[`Regwrena] = 1'b1;
                set_exec[`opcMOVEQ] = 1'b1;
                set_exec[`opcMOVE]  = 1'b1;
                dest_hbits          = 1'b1;
            end else begin
                trap_illegal = 1'b1;
                trapmake     = 1'b1;
            end
        end
        // 1000 -------------------------------------------------------------
        4'b1000: begin   // or
            if (opcode[7:6] == 2'b11) begin   // divu, divs
                if (DIV_Mode != 3 && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                    if (opcode[5:4] == 2'b00) regdirectsource = 1'b1;   // Dn, An
                    if ((micro_state == `ms_idle && nextpass) || (opcode[5:4] == 2'b00 && decodeOPC)) begin
                        setstate         = 2'b01;
                        next_micro_state = `ms_div1;
                    end
                    ea_build_now = 1'b1;
                    if (!Z_error && !set_V_Flag) set_exec[`Regwrena] = 1'b1;
                    source_lowbits = 1'b1;
                    if (nextpass || (opcode[5:4] == 2'b00 && decodeOPC)) dest_hbits = 1'b1;
                    datatype = 2'b01;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end else if (opcode[8] && opcode[5:4] == 2'b00) begin   // sbcd, pack, unpack
                if (opcode[7:6] == 2'b00) begin   // sbcd
                    build_bcd          = 1'b1;
                    set_exec[`opcADD]  = 1'b1;
                    set_exec[`opcSBCD] = 1'b1;
                    set[`addsub]       = 1'b1;
                end else if (opcode[7:6] == 2'b01 || opcode[7:6] == 2'b10) begin   // pack, unpack
                    set_exec[`ea_data_OP1] = 1'b1;
                    set[`no_Flags]         = 1'b1;
                    source_lowbits         = 1'b1;
                    if (opcode[7:6] == 2'b01) begin   // pack
                        set_exec[`opcPACK] = 1'b1;
                        datatype           = 2'b01;  // Word
                    end else begin   // unpk
                        set_exec[`opcUNPACK] = 1'b1;
                        datatype             = 2'b00;  // Byte
                    end
                    if (!opcode[3]) begin
                        if (opcode[7:6] == 2'b01) set_datatype = 2'b00;  // pack -> Byte
                        else                      set_datatype = 2'b01;  // unpk -> Word
                        set_exec[`Regwrena] = 1'b1;
                        dest_hbits          = 1'b1;
                        if (decodeOPC) begin
                            next_micro_state         = `ms_nop;
                            set[`store_ea_packdata]  = 1'b1;
                            set[`store_ea_data]      = 1'b1;
                        end
                    end else begin   // pack -(Ax),-(Ay)
                        write_back = 1'b1;
                        if (decodeOPC) begin
                            next_micro_state = `ms_pack1;
                            set_direct_data  = 1'b1;
                        end
                    end
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end else begin   // or
                if (opcode[7:6] != 2'b11 &&
                    ((!opcode[8] && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) ||
                     (opcode[8] && opcode[5:4] != 2'b00 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)))) begin
                    set_exec[`opcOR] = 1'b1;
                    build_logical    = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end
        end
        // 1001, 1101 -------------------------------------------------------
        4'b1001, 4'b1101: begin   // sub, add
            if (opcode[8:3] != 6'b000001 &&
                (((!opcode[8] || opcode[7:6] == 2'b11) && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) ||
                 (opcode[8] && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)))) begin
                set_exec[`opcADD] = 1'b1;
                ea_build_now      = 1'b1;
                if (!opcode[14]) set[`addsub] = 1'b1;
                if (opcode[7:6] == 2'b11) begin   // adda, suba
                    if (!opcode[8]) datatype = 2'b01;   // adda.w, suba.w
                    set_exec[`Regwrena] = 1'b1;
                    source_lowbits      = 1'b1;
                    if (opcode[3]) source_areg = 1'b1;
                    set[`no_Flags] = 1'b1;
                    if (setexecOPC) begin
                        dest_areg  = 1'b1;
                        dest_hbits = 1'b1;
                    end
                end else begin
                    if (opcode[8] && opcode[5:4] == 2'b00) build_bcd = 1'b1;   // addx, subx
                    else                                   build_logical = 1'b1;   // sub, add
                end
            end else begin
                trap_illegal = 1'b1;
                trapmake     = 1'b1;
            end
        end
        // 1010 -------------------------------------------------------------
        4'b1010: begin   // Trap 1010
            trap_1010 = 1'b1;
            trapmake  = 1'b1;
        end
        // 1011 -------------------------------------------------------------
        4'b1011: begin   // eor, cmp
            if (opcode[7:6] == 2'b11) begin   // CMPA
                if (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00) begin
                    ea_build_now = 1'b1;
                    if (!opcode[8]) begin   // cmpa.w
                        datatype            = 2'b01;  // Word
                        set_exec[`opcCPMAW] = 1'b1;
                    end
                    set_exec[`opcCMP] = 1'b1;
                    if (setexecOPC) begin
                        source_lowbits = 1'b1;
                        if (opcode[3]) source_areg = 1'b1;
                        dest_areg  = 1'b1;
                        dest_hbits = 1'b1;
                    end
                    set[`addsub] = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end else begin   // cmpm, eor, cmp
                if (opcode[8]) begin
                    if (opcode[5:3] == 3'b001) begin   // cmpm
                        ea_build_now      = 1'b1;
                        set_exec[`opcCMP] = 1'b1;
                        if (decodeOPC) begin
                            if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                            setstate         = 2'b10;
                            set[`update_ld]  = 1'b1;
                            set[`postadd]    = 1'b1;
                            next_micro_state = `ms_cmpm;
                        end
                        set_exec[`ea_data_OP1] = 1'b1;
                        set[`addsub]           = 1'b1;
                    end else begin   // EOR
                        if (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00) begin
                            ea_build_now      = 1'b1;
                            build_logical     = 1'b1;
                            set_exec[`opcEOR] = 1'b1;
                        end else begin
                            trap_illegal = 1'b1;
                            trapmake     = 1'b1;
                        end
                    end
                end else begin   // CMP
                    if (opcode[8:3] != 6'b000001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                        ea_build_now      = 1'b1;
                        build_logical     = 1'b1;
                        set_exec[`opcCMP] = 1'b1;
                        set[`addsub]      = 1'b1;
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end
            end
        end
        // 1100 -------------------------------------------------------------
        4'b1100: begin   // and, exg
            if (opcode[7:6] == 2'b11) begin   // mulu, muls
                if (MUL_Mode != 3 && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) begin
                    if (opcode[5:4] == 2'b00) regdirectsource = 1'b1;   // Dn, An
                    if ((micro_state == `ms_idle && nextpass) || (opcode[5:4] == 2'b00 && decodeOPC)) begin
                        if (MUL_Hardware == 0) begin
                            setstate         = 2'b01;
                            set[`ld_rot_cnt] = 1'b1;
                            next_micro_state = `ms_mul1;
                        end else begin
                            set_exec[`write_lowlong] = 1'b1;
                            set_exec[`opcMULU]       = 1'b1;
                        end
                    end
                    ea_build_now        = 1'b1;
                    set_exec[`Regwrena] = 1'b1;
                    source_lowbits      = 1'b1;
                    if (nextpass || (opcode[5:4] == 2'b00 && decodeOPC)) dest_hbits = 1'b1;
                    datatype = 2'b01;
                    if (setexecOPC) datatype = 2'b10;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end else if (opcode[8] && opcode[5:4] == 2'b00) begin   // exg, abcd
                if (opcode[7:6] == 2'b00) begin   // abcd
                    build_bcd          = 1'b1;
                    set_exec[`opcADD]  = 1'b1;
                    set_exec[`opcABCD] = 1'b1;
                end else begin   // exg
                    if (opcode[7:4] == 4'b0100 || opcode[7:3] == 5'b10001) begin
                        datatype       = 2'b10;
                        set[`Regwrena] = 1'b1;
                        set[`exg]      = 1'b1;
                        set[`alu_move] = 1'b1;
                        if (opcode[6] && opcode[3]) begin
                            dest_areg   = 1'b1;
                            source_areg = 1'b1;
                        end
                        if (decodeOPC) setstate = 2'b01;
                        else           dest_hbits = 1'b1;
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end
            end else begin   // and
                if (opcode[7:6] != 2'b11 &&
                    ((!opcode[8] && opcode[5:3] != 3'b001 && (opcode[5:2] != 4'b1111 || opcode[1:0] == 2'b00)) ||
                     (opcode[8] && opcode[5:4] != 2'b00 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)))) begin
                    set_exec[`opcAND] = 1'b1;
                    build_logical     = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end
        end
        // 1110 -------------------------------------------------------------
        4'b1110: begin   // rotation / bitfield
            if (opcode[7:6] == 2'b11) begin
                if (!opcode[11]) begin
                    if (opcode[5:4] != 2'b00 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                        if (BarrelShifter == 0) set_exec[`opcROT] = 1'b1;
                        else                    set_exec[`exec_BS] = 1'b1;
                        ea_build_now           = 1'b1;
                        datatype               = 2'b01;
                        set_rot_bits           = opcode[10:9];
                        set_exec[`ea_data_OP1] = 1'b1;
                        write_back             = 1'b1;
                    end else begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end
                end else begin   // bitfield
                    if (BitField == 0 || (!CPU[1] && BitField == 2) ||
                        ((opcode[10:9] == 2'b11 || opcode[10:8] == 3'b010 || opcode[10:8] == 3'b100) &&
                         (opcode[5:3] == 3'b001 || opcode[5:3] == 3'b011 || opcode[5:3] == 3'b100 || (opcode[5:3] == 3'b111 && opcode[2:1] != 2'b00))) ||
                        ((opcode[10:9] == 2'b00 || opcode[10:8] == 3'b011 || opcode[10:8] == 3'b101) &&
                         (opcode[5:3] == 3'b001 || opcode[5:3] == 3'b011 || opcode[5:3] == 3'b100 || opcode[5:2] == 4'b1111))) begin
                        trap_illegal = 1'b1;
                        trapmake     = 1'b1;
                    end else begin
                        if (decodeOPC) begin
                            next_micro_state = `ms_nop;
                            set[`get_2ndOPC] = 1'b1;
                            set[`ea_build]   = 1'b1;
                        end
                        set_exec[`opcBF] = 1'b1;
                        // 000-bftst 001-bfextu 010-bfchg 011-bfexts 100-bfclr 101-bfffo 110-bfset 111-bfins
                        if (opcode[10] || !opcode[8]) set_exec[`opcBFwb] = 1'b1;
                        if (opcode[10:8] == 3'b111) set_exec[`ea_data_OP1] = 1'b1;   // BFINS
                        if (opcode[10:8] == 3'b010 || opcode[10:8] == 3'b100 || opcode[10:8] == 3'b110 || opcode[10:8] == 3'b111)
                            write_back = 1'b1;
                        ea_only = 1'b1;
                        if (opcode[10:8] == 3'b001 || opcode[10:8] == 3'b011 || opcode[10:8] == 3'b101)
                            set_exec[`Regwrena] = 1'b1;
                        if (opcode[4:3] == 2'b00) begin
                            if (opcode[10:8] != 3'b000) set_exec[`Regwrena] = 1'b1;
                            if (exec[`ea_build]) begin
                                dest_2ndHbits     = 1'b1;
                                source_2ndLbits   = 1'b1;
                                set[`get_bfoffset]= 1'b1;
                                setstate          = 2'b01;
                            end
                        end
                        if (set[`get_ea_now]) setstate = 2'b01;
                        if (exec[`get_ea_now]) begin
                            dest_2ndHbits     = 1'b1;
                            source_2ndLbits   = 1'b1;
                            set[`get_bfoffset]= 1'b1;
                            setstate          = 2'b01;
                            set[`mem_addsub]  = 1'b1;
                            next_micro_state  = `ms_bf1;
                        end
                        if (setexecOPC) begin
                            if (opcode[10:8] == 3'b111) source_2ndHbits = 1'b1;   // BFINS
                            else                        source_lowbits  = 1'b1;
                            if (opcode[10:8] == 3'b001 || opcode[10:8] == 3'b011 || opcode[10:8] == 3'b101)   // BFEXT, BFFFO
                                dest_2ndHbits = 1'b1;
                        end
                    end
                end
            end else begin
                data_is_source = 1'b1;
                if (BarrelShifter == 0 || (!CPU[1] && BarrelShifter == 2)) begin
                    set_exec[`opcROT]   = 1'b1;
                    set_rot_bits        = opcode[4:3];
                    set_exec[`Regwrena] = 1'b1;
                    if (decodeOPC) begin
                        if (opcode[5]) begin
                            next_micro_state = `ms_rota1;
                            set[`ld_rot_cnt] = 1'b1;
                            setstate         = 2'b01;
                        end else begin
                            set_rot_cnt[2:0] = opcode[11:9];
                            if (opcode[11:9] == 3'b000) set_rot_cnt[3] = 1'b1;
                            else                        set_rot_cnt[3] = 1'b0;
                        end
                    end
                end else begin
                    set_exec[`exec_BS]  = 1'b1;
                    set_rot_bits        = opcode[4:3];
                    set_exec[`Regwrena] = 1'b1;
                end
            end
        end
        // 1111 -------------------------------------------------------------
        4'b1111: begin
            if (CPU[1] && opcode[8:6] == 3'b100) begin   // cpSAVE
                if (opcode[5:4] != 2'b00 && opcode[5:3] != 3'b011 && (opcode[5:3] != 3'b111 || opcode[2:1] == 2'b00)) begin
                    if (opcode[11:9] != 3'b000) begin
                        if (SVmode) begin
                            if (!opcode[5] && opcode[5:4] != 2'b01) begin
                                // cpSAVE not implemented (never reached per cputest)
                                trap_illegal = 1'b1;
                                trapmake     = 1'b1;
                            end else begin
                                trap_1111 = 1'b1;
                                trapmake  = 1'b1;
                            end
                        end else begin
                            trap_priv = 1'b1;
                            trapmake  = 1'b1;
                        end
                    end else begin
                        if (SVmode) begin
                            trap_1111 = 1'b1;
                            trapmake  = 1'b1;
                        end else begin
                            trap_priv = 1'b1;
                            trapmake  = 1'b1;
                        end
                    end
                end else begin
                    trap_1111 = 1'b1;
                    trapmake  = 1'b1;
                end
            end else if (CPU[1] && opcode[8:6] == 3'b101) begin   // cpRESTORE
                if (opcode[5:4] != 2'b00 && opcode[5:3] != 3'b100 &&
                    (opcode[5:3] != 3'b111 || (opcode[2:1] != 2'b11 && opcode[2:0] != 3'b101))) begin
                    if (opcode[5:1] != 5'b11110) begin
                        if (opcode[11:9] == 3'b001 || opcode[11:9] == 3'b010) begin
                            if (SVmode) begin
                                if (opcode[5:3] == 3'b101) begin
                                    // cpRESTORE not implemented
                                    trap_illegal = 1'b1;
                                    trapmake     = 1'b1;
                                end else begin
                                    trap_1111 = 1'b1;
                                    trapmake  = 1'b1;
                                end
                            end else begin
                                trap_priv = 1'b1;
                                trapmake  = 1'b1;
                            end
                        end else begin
                            if (SVmode) begin
                                trap_1111 = 1'b1;
                                trapmake  = 1'b1;
                            end else begin
                                trap_priv = 1'b1;
                                trapmake  = 1'b1;
                            end
                        end
                    end else begin
                        trap_1111 = 1'b1;
                        trapmake  = 1'b1;
                    end
                end else begin
                    trap_1111 = 1'b1;
                    trapmake  = 1'b1;
                end
            end else begin
                trap_1111 = 1'b1;
                trapmake  = 1'b1;
            end
        end
        default: begin
            trap_illegal = 1'b1;
            trapmake     = 1'b1;
        end
        endcase

        // ---- use for AND, OR, EOR, CMP (VHDL 3184-3201) ----
        if (build_logical) begin
            ea_build_now = 1'b1;
            if (!set_exec[`opcCMP] && (!opcode[8] || opcode[5:4] == 2'b00))
                set_exec[`Regwrena] = 1'b1;
            if (opcode[8]) begin
                write_back             = 1'b1;
                set_exec[`ea_data_OP1] = 1'b1;
            end else begin
                source_lowbits = 1'b1;
                if (opcode[3]) source_areg = 1'b1;   // use for cmp
                if (setexecOPC) dest_hbits = 1'b1;
            end
        end

        // ---- use for ABCD, SBCD (VHDL 3203-3224) ----
        if (build_bcd) begin
            set_exec[`use_XZFlag]  = 1'b1;
            set_exec[`ea_data_OP1] = 1'b1;
            write_back             = 1'b1;
            source_lowbits         = 1'b1;
            if (opcode[3]) begin
                if (decodeOPC) begin
                    if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                    setstate         = 2'b10;
                    set[`update_ld]  = 1'b1;
                    set[`presub]     = 1'b1;
                    next_micro_state = `ms_op_AxAy;
                    dest_areg        = 1'b1;   // ???
                end
            end else begin
                dest_hbits          = 1'b1;
                set_exec[`Regwrena] = 1'b1;
            end
        end

        // ---- divu by zero (VHDL 3229-3234) ----
        if (set_Z_error) begin
            trapmake = 1'b1;   // wichtig for USP
            if (!trapd) writePC = 1'b1;
        end

        // ---- EA build, second evaluation (combinational ea_build_now path) ----
        // The VHDL EA build (1586) runs to convergence with the *final*
        // ea_build_now, which the opcode CASE above assigns. The earlier copy
        // (~line 1256) only sees the registered exec[`ea_build] path, because
        // ea_build_now is still at its reset value there. Re-run the block here,
        // now that ea_build_now is final, for the same-cycle decode path (e.g.
        // MOVE setting up an immediate / memory source operand). NB: this is not
        // a full convergence -- opcode-CASE consumers of get_ea_now still see the
        // earlier copy's value, which is correct for the registered path. See the
        // memory note: a complete fix needs multi-pass convergence.
        if (ea_build_now && decodeOPC) begin
            case (opcode[5:3])
                3'b010, 3'b011, 3'b100: begin   // (An), (An)+, -(An)
                    set[`get_ea_now] = 1'b1;
                    setnextpass      = 1'b1;
                    if (opcode[3]) begin        // (An)+
                        set[`postadd] = 1'b1;
                        if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                    end
                    if (opcode[5]) begin        // -(An)
                        set[`presub] = 1'b1;
                        if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                    end
                end
                3'b101: next_micro_state = `ms_ld_dAn1;     // (d16,An)
                3'b110: begin                               // (d8,An,Xn)
                    next_micro_state = `ms_ld_AnXn1;
                    getbrief         = 1'b1;
                end
                3'b111: begin
                    case (opcode[2:0])
                        3'b000: next_micro_state = `ms_ld_nn;            // (xxxx).w
                        3'b001: begin                                   // (xxxx).l
                            set[`longaktion] = 1'b1;
                            next_micro_state = `ms_ld_nn;
                        end
                        3'b010: begin                                   // (d16,PC)
                            next_micro_state  = `ms_ld_dAn1;
                            set[`dispouter]   = 1'b1;
                            set_Suppress_Base = 1'b1;
                            set_PCbase        = 1'b1;
                        end
                        3'b011: begin                                   // (d8,PC,Xn)
                            next_micro_state  = `ms_ld_AnXn1;
                            getbrief          = 1'b1;
                            set[`dispouter]   = 1'b1;
                            set_Suppress_Base = 1'b1;
                            set_PCbase        = 1'b1;
                        end
                        3'b100: begin                                   // #data
                            setnextpass     = 1'b1;
                            set_direct_data = 1'b1;
                            if (datatype == 2'b10) set[`longaktion] = 1'b1;
                        end
                        default: ;
                    endcase
                end
                default: ;
            endcase
        end

        // ---- micro_state sequencer (VHDL 3248-3999) ----
        case (micro_state)
            `ms_ld_nn: begin   // (nnnn).w/l=>
                set[`get_ea_now] = 1'b1;
                setnextpass      = 1'b1;
                set[`addrlong]   = 1'b1;
            end
            `ms_st_nn: begin   // =>(nnnn).w/l
                setstate         = 2'b11;
                set[`addrlong]   = 1'b1;
                next_micro_state = `ms_nop;
            end
            `ms_ld_dAn1: begin   // d(An)=>, d(PC)=>
                set[`get_ea_now] = 1'b1;
                setdisp          = 1'b1;   // word
                setnextpass      = 1'b1;
            end
            `ms_ld_AnXn1: begin   // d(An,Xn)=>, d(PC,Xn)=>
                if (!brief[8] || extAddr_Mode == 0 || (!CPU[1] && extAddr_Mode == 2)) begin
                    setdisp          = 1'b1;   // byte
                    setdispbyte      = 1'b1;
                    setstate         = 2'b01;
                    set[`briefext]   = 1'b1;
                    next_micro_state = `ms_ld_AnXn2;
                end else begin
                    if (brief[7])                set_Suppress_Base = 1'b1;   // suppress Base
                    else if (exec[`dispouter])   set[`dispouter]   = 1'b1;
                    if (!brief[5]) setstate = 2'b01;   // NULL Base Displacement
                    else begin                         // WORD Base Displacement
                        if (brief[4]) set[`longaktion] = 1'b1;   // LONG Base Displacement
                    end
                    next_micro_state = `ms_ld_229_1;
                end
            end
            `ms_ld_AnXn2: begin
                set[`get_ea_now] = 1'b1;
                setdisp          = 1'b1;   // brief
                setnextpass      = 1'b1;
            end
            `ms_ld_229_1: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                if (brief[5]) setdisp = 1'b1;   // Base Displacement, add last_data_read
                if (!brief[6] && !brief[2]) begin   // Preindex or Index
                    set[`briefext] = 1'b1;
                    setstate       = 2'b01;
                    if (brief[1:0] == 2'b00) next_micro_state = `ms_ld_AnXn2;
                    else                     next_micro_state = `ms_ld_229_2;
                end else begin
                    if (brief[1:0] == 2'b00) begin
                        set[`get_ea_now] = 1'b1;
                        setnextpass      = 1'b1;
                    end else begin
                        setstate         = 2'b10;
                        setaddrvalue     = 1'b1;
                        set[`longaktion] = 1'b1;
                        next_micro_state = `ms_ld_229_3;
                    end
                end
            end
            `ms_ld_229_2: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                setdisp          = 1'b1;   // add Index
                setstate         = 2'b10;
                setaddrvalue     = 1'b1;
                set[`longaktion] = 1'b1;
                next_micro_state = `ms_ld_229_3;
            end
            `ms_ld_229_3: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                set_Suppress_Base = 1'b1;
                set[`dispouter]   = 1'b1;
                if (!brief[1]) setstate = 2'b01;   // NULL Outer Displacement
                else begin                         // WORD Outer Displacement
                    if (brief[0]) set[`longaktion] = 1'b1;   // LONG Outer Displacement
                end
                next_micro_state = `ms_ld_229_4;
            end
            `ms_ld_229_4: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                if (brief[1]) setdisp = 1'b1;   // Outer Displacement, add last_data_read
                if (!brief[6] && brief[2]) begin   // Postindex
                    set[`briefext]   = 1'b1;
                    setstate         = 2'b01;
                    next_micro_state = `ms_ld_AnXn2;
                end else begin
                    set[`get_ea_now] = 1'b1;
                    setnextpass      = 1'b1;
                end
            end
            `ms_st_dAn1: begin   // =>d(An)
                setstate         = 2'b11;
                setdisp          = 1'b1;   // word
                next_micro_state = `ms_nop;
            end
            `ms_st_AnXn1: begin   // =>d(An,Xn)
                if (!brief[8] || extAddr_Mode == 0 || (!CPU[1] && extAddr_Mode == 2)) begin
                    setdisp          = 1'b1;   // byte
                    setdispbyte      = 1'b1;
                    setstate         = 2'b01;
                    set[`briefext]   = 1'b1;
                    next_micro_state = `ms_st_AnXn2;
                end else begin
                    if (brief[7]) set_Suppress_Base = 1'b1;   // suppress Base
                    if (!brief[5]) setstate = 2'b01;   // NULL Base Displacement
                    else begin                         // WORD Base Displacement
                        if (brief[4]) set[`longaktion] = 1'b1;   // LONG Base Displacement
                    end
                    next_micro_state = `ms_st_229_1;
                end
            end
            `ms_st_AnXn2: begin
                setstate         = 2'b11;
                setdisp          = 1'b1;   // brief
                set[`hold_dwr]   = 1'b1;
                next_micro_state = `ms_nop;
            end
            `ms_st_229_1: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                if (brief[5]) setdisp = 1'b1;   // Base Displacement
                if (!brief[6] && !brief[2]) begin   // Preindex or Index
                    set[`briefext] = 1'b1;
                    setstate       = 2'b01;
                    if (brief[1:0] == 2'b00) next_micro_state = `ms_st_AnXn2;
                    else                     next_micro_state = `ms_st_229_2;
                end else begin
                    if (brief[1:0] == 2'b00) begin
                        setstate         = 2'b11;
                        next_micro_state = `ms_nop;
                    end else begin
                        set[`hold_dwr]   = 1'b1;
                        setstate         = 2'b10;
                        set[`longaktion] = 1'b1;
                        next_micro_state = `ms_st_229_3;
                    end
                end
            end
            `ms_st_229_2: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                setdisp          = 1'b1;   // add Index
                set[`hold_dwr]   = 1'b1;
                setstate         = 2'b10;
                set[`longaktion] = 1'b1;
                next_micro_state = `ms_st_229_3;
            end
            `ms_st_229_3: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                set[`hold_dwr]    = 1'b1;
                set_Suppress_Base = 1'b1;
                set[`dispouter]   = 1'b1;
                if (!brief[1]) setstate = 2'b01;   // NULL Outer Displacement
                else begin                         // WORD Outer Displacement
                    if (brief[0]) set[`longaktion] = 1'b1;   // LONG Outer Displacement
                end
                next_micro_state = `ms_st_229_4;
            end
            `ms_st_229_4: begin   // (bd,An,Xn)=>, (bd,PC,Xn)=>
                set[`hold_dwr] = 1'b1;
                if (brief[1]) setdisp = 1'b1;   // Outer Displacement
                if (!brief[6] && brief[2]) begin   // Postindex
                    set[`briefext]   = 1'b1;
                    setstate         = 2'b01;
                    next_micro_state = `ms_st_AnXn2;
                end else begin
                    setstate         = 2'b11;
                    next_micro_state = `ms_nop;
                end
            end
            `ms_bra1: begin   // bra
                if (exe_condition) begin
                    TG68_PC_brw      = 1'b1;   // pc+0000
                    next_micro_state = `ms_nop;
                    skipFetch        = 1'b1;
                end
            end
            `ms_bsr1: begin   // bsr short
                TG68_PC_brw      = 1'b1;
                next_micro_state = `ms_nop;
            end
            `ms_bsr2: begin   // bsr
                if (!long_start) TG68_PC_brw = 1'b1;
                skipFetch        = 1'b1;
                set[`longaktion] = 1'b1;
                writePC          = 1'b1;
                setstate         = 2'b11;
                next_micro_state = `ms_nopnop;
                setstackaddr     = 1'b1;
            end
            `ms_nopnop: begin   // bsr
                next_micro_state = `ms_nop;
            end
            `ms_dbcc1: begin   // dbcc
                if (!exe_condition) begin
                    Regwrena_now = 1'b1;
                    if (c_out[1]) begin
                        skipFetch        = 1'b1;
                        next_micro_state = `ms_nop;
                        TG68_PC_brw      = 1'b1;
                    end
                end
            end
            `ms_chk20: begin   // if C is set -> signed compare
                set[`ea_data_OP1] = 1'b1;
                set[`addsub]      = 1'b1;
                set[`alu_exec]    = 1'b1;
                set[`alu_setFlags]= 1'b1;
                setstate          = 2'b01;
                next_micro_state  = `ms_chk21;
            end
            `ms_chk21: begin   // check lower bound
                dest_2ndHbits = 1'b1;
                if (sndOPC[15]) begin
                    set_datatype = 2'b10;   // long
                    dest_LDRareg = 1'b1;
                    if (opcode[10:9] == 2'b00) set[`opcEXTB] = 1'b1;
                end
                set[`addsub]      = 1'b1;
                set[`alu_exec]    = 1'b1;
                set[`alu_setFlags]= 1'b1;
                setstate          = 2'b01;
                next_micro_state  = `ms_chk22;
            end
            `ms_chk22: begin   // check upper bound
                dest_2ndHbits     = 1'b1;
                set[`ea_data_OP2] = 1'b1;
                if (sndOPC[15]) begin
                    set_datatype = 2'b10;   // long
                    dest_LDRareg = 1'b1;
                end
                set[`addsub]   = 1'b1;
                set[`alu_exec] = 1'b1;
                set[`opcCHK2]  = 1'b1;
                set[`opcEXTB]  = exec[`opcEXTB];
                if (sndOPC[11]) begin
                    setstate         = 2'b01;
                    next_micro_state = `ms_chk23;
                end
            end
            `ms_chk23: begin
                setstate         = 2'b01;
                next_micro_state = `ms_chk24;
            end
            `ms_chk24: begin
                if (Flags[0]) trapmake = 1'b1;
            end
            `ms_cas1: begin
                setstate         = 2'b01;
                next_micro_state = `ms_cas2;
            end
            `ms_cas2: begin
                source_2ndMbits = 1'b1;
                if (Flags[2]) begin
                    setstate            = 2'b11;
                    set[`write_reg]     = 1'b1;
                    set[`restore_ADDR]  = 1'b1;
                    next_micro_state    = `ms_nop;
                end else begin
                    set[`Regwrena]    = 1'b1;
                    set[`ea_data_OP2] = 1'b1;
                    dest_2ndLbits     = 1'b1;
                    set[`alu_move]    = 1'b1;
                end
            end
            `ms_cas21: begin
                dest_2ndHbits    = 1'b1;
                dest_LDRareg     = sndOPC[15];
                set[`get_ea_now] = 1'b1;
                next_micro_state = `ms_cas22;
            end
            `ms_cas22: begin
                setstate          = 2'b01;
                source_2ndLbits   = 1'b1;
                set[`ea_data_OP1] = 1'b1;
                set[`addsub]      = 1'b1;
                set[`alu_exec]    = 1'b1;
                set[`alu_setFlags]= 1'b1;
                next_micro_state  = `ms_cas23;
            end
            `ms_cas23: begin
                dest_LDRHbits    = 1'b1;
                set[`get_ea_now] = 1'b1;
                next_micro_state = `ms_cas24;
            end
            `ms_cas24: begin
                if (Flags[2]) set[`alu_setFlags] = 1'b1;
                setstate          = 2'b01;
                set[`hold_dwr]    = 1'b1;
                source_LDRLbits   = 1'b1;
                set[`ea_data_OP1] = 1'b1;
                set[`addsub]      = 1'b1;
                set[`alu_exec]    = 1'b1;
                next_micro_state  = `ms_cas25;
            end
            `ms_cas25: begin
                setstate         = 2'b01;
                set[`hold_dwr]   = 1'b1;
                next_micro_state = `ms_cas26;
            end
            `ms_cas26: begin
                if (Flags[2]) begin   // write Update 1 to Destination 1
                    source_2ndMbits  = 1'b1;
                    set[`write_reg]  = 1'b1;
                    dest_2ndHbits    = 1'b1;
                    dest_LDRareg     = sndOPC[15];
                    setstate         = 2'b11;
                    set[`get_ea_now] = 1'b1;
                    next_micro_state = `ms_cas27;
                end else begin   // write Destination 2 to Compare 2 first
                    set[`hold_dwr]   = 1'b1;
                    set[`hold_OP2]   = 1'b1;
                    dest_LDRLbits    = 1'b1;
                    set[`alu_move]   = 1'b1;
                    set[`Regwrena]   = 1'b1;
                    set[`ea_data_OP2]= 1'b1;
                    next_micro_state = `ms_cas28;
                end
            end
            `ms_cas27: begin   // write Update 2 to Destination 2
                source_LDRMbits  = 1'b1;
                set[`write_reg]  = 1'b1;
                dest_LDRHbits    = 1'b1;
                setstate         = 2'b11;
                set[`get_ea_now] = 1'b1;
                next_micro_state = `ms_nopnop;
            end
            `ms_cas28: begin   // write Destination 1 to Compare 1 second
                dest_2ndLbits  = 1'b1;
                set[`alu_move] = 1'b1;
                set[`Regwrena] = 1'b1;
            end
            `ms_movem1: begin   // movem
                if (last_data_read[15:0] != 16'h0000) begin
                    setstate = 2'b01;
                    if (opcode[5:3] == 3'b100) begin
                        set[`mem_addsub] = 1'b1;
                        if (CPU[1]) set[`Regwrena] = 1'b1;
                    end
                    next_micro_state = `ms_movem2;
                end
            end
            `ms_movem2: begin   // movem
                if (!movem_run) setstate = 2'b01;
                else begin
                    set[`movem_action] = 1'b1;
                    set[`mem_addsub]   = 1'b1;
                    next_micro_state   = `ms_movem2;
                    if (!opcode[10]) begin
                        setstate        = 2'b11;
                        set[`write_reg] = 1'b1;
                    end else
                        setstate = 2'b10;
                end
            end
            `ms_andi: begin   // andi
                if (opcode[5:4] != 2'b00) setnextpass = 1'b1;
            end
            `ms_pack1: begin   // pack -(Ax),-(Ay)
                if (opcode[2:0] == 3'b111) set[`use_SP] = 1'b1;
                set[`hold_ea_data] = 1'b1;
                set[`update_ld]    = 1'b1;
                setstate           = 2'b10;
                set[`presub]       = 1'b1;
                next_micro_state   = `ms_pack2;
                dest_areg          = 1'b1;
            end
            `ms_pack2: begin
                if (opcode[11:9] == 3'b111) set[`use_SP] = 1'b1;
                set[`hold_ea_data] = 1'b1;
                set_direct_data    = 1'b1;
                if (opcode[7:6] == 2'b01) datatype = 2'b00;   // pack -> Byte
                else                      datatype = 2'b01;   // unpk -> Word
                set[`presub]     = 1'b1;
                dest_hbits       = 1'b1;
                dest_areg        = 1'b1;
                setstate         = 2'b10;
                next_micro_state = `ms_pack3;
            end
            `ms_pack3: begin
                skipFetch = 1'b1;
            end
            `ms_op_AxAy: begin   // op -(Ax),-(Ay)
                if (opcode[11:9] == 3'b111) set[`use_SP] = 1'b1;
                set_direct_data = 1'b1;
                set[`presub]    = 1'b1;
                dest_hbits      = 1'b1;
                dest_areg       = 1'b1;
                setstate        = 2'b10;
            end
            `ms_cmpm: begin   // cmpm (Ay)+,(Ax)+
                if (opcode[11:9] == 3'b111) set[`use_SP] = 1'b1;
                set_direct_data = 1'b1;
                set[`postadd]   = 1'b1;
                dest_hbits      = 1'b1;
                dest_areg       = 1'b1;
                setstate        = 2'b10;
            end
            `ms_link1: begin   // link
                setstate         = 2'b11;
                source_areg      = 1'b1;
                set[`opcMOVE]    = 1'b1;
                set[`Regwrena]   = 1'b1;
                next_micro_state = `ms_link2;
            end
            `ms_link2: begin   // link
                setstackaddr      = 1'b1;
                set[`ea_data_OP2] = 1'b1;
            end
            `ms_unlink1: begin   // unlink
                setstate         = 2'b10;
                setstackaddr     = 1'b1;
                set[`postadd]    = 1'b1;
                next_micro_state = `ms_unlink2;
            end
            `ms_unlink2: begin   // unlink
                set[`ea_data_OP2] = 1'b1;
            end
            `ms_trap00: begin   // TRAP format #2
                next_micro_state = `ms_trap0;
                set[`presub]     = 1'b1;
                setstackaddr     = 1'b1;
                setstate         = 2'b11;
                datatype         = 2'b10;
            end
            `ms_trap0: begin   // TRAP
                set[`presub] = 1'b1;
                setstackaddr = 1'b1;
                setstate     = 2'b11;
                if (use_VBR_Stackframe) begin   // 68010
                    set[`writePC_add] = 1'b1;
                    datatype          = 2'b01;
                    next_micro_state  = `ms_trap1;
                end else begin
                    if (trap_interrupt || trap_trace || trap_berr) writePC = 1'b1;
                    datatype         = 2'b10;
                    next_micro_state = `ms_trap2;
                end
            end
            `ms_trap1: begin   // TRAP
                if (trap_interrupt || trap_trace) writePC = 1'b1;
                set[`presub]     = 1'b1;
                setstackaddr     = 1'b1;
                setstate         = 2'b11;
                datatype         = 2'b10;
                next_micro_state = `ms_trap2;
            end
            `ms_trap2: begin   // TRAP
                set[`presub] = 1'b1;
                setstackaddr = 1'b1;
                setstate     = 2'b11;
                datatype     = 2'b01;
                writeSR      = 1'b1;
                if (trap_berr) next_micro_state = `ms_trap4;
                else           next_micro_state = `ms_trap3;
            end
            `ms_trap3: begin   // TRAP
                set_vectoraddr    = 1'b1;
                datatype          = 2'b10;
                set[`direct_delta]= 1'b1;
                set[`directPC]    = 1'b1;
                setstate          = 2'b10;
                next_micro_state  = `ms_nopnop;
            end
            `ms_trap4: begin   // TRAP
                set[`presub]     = 1'b1;
                setstackaddr     = 1'b1;
                setstate         = 2'b11;
                datatype         = 2'b01;
                writeSR          = 1'b1;
                next_micro_state = `ms_trap5;
            end
            `ms_trap5: begin   // TRAP
                set[`presub]     = 1'b1;
                setstackaddr     = 1'b1;
                setstate         = 2'b11;
                datatype         = 2'b10;
                writeSR          = 1'b1;
                next_micro_state = `ms_trap6;
            end
            `ms_trap6: begin   // TRAP
                set[`presub]     = 1'b1;
                setstackaddr     = 1'b1;
                setstate         = 2'b11;
                datatype         = 2'b01;
                writeSR          = 1'b1;
                next_micro_state = `ms_trap3;
            end
            `ms_rte1: begin   // RTE
                datatype      = 2'b10;
                setstate      = 2'b10;
                set[`postadd] = 1'b1;
                setstackaddr  = 1'b1;
                set[`directPC]= 1'b1;
                if (!use_VBR_Stackframe || opcode[2]) begin   // opcode(2)=1 => RTR
                    set[`update_FC]   = 1'b1;
                    set[`direct_delta]= 1'b1;
                end
                next_micro_state = `ms_rte2;
            end
            `ms_rte2: begin   // RTE
                datatype        = 2'b01;
                set[`update_FC] = 1'b1;
                if (use_VBR_Stackframe && !opcode[2]) begin   // 010+ reads another word
                    setstate         = 2'b10;
                    set[`postadd]    = 1'b1;
                    setstackaddr     = 1'b1;
                    next_micro_state = `ms_rte3;
                end else
                    next_micro_state = `ms_nop;
            end
            `ms_rte3: begin   // RTE
                setstate         = 2'b01;   // idle to wait for input data
                next_micro_state = `ms_rte4;
            end
            `ms_rte4: begin   // RTE - check for stack frame format #2
                if (last_data_in[15:12] == 4'b0010) begin   // read another 32 bits
                    setstate         = 2'b10;   // read
                    datatype         = 2'b10;   // long word
                    set[`postadd]    = 1'b1;
                    setstackaddr     = 1'b1;
                    next_micro_state = `ms_rte5;
                end else begin
                    datatype         = 2'b01;
                    next_micro_state = `ms_nop;
                end
            end
            `ms_rte5: begin   // RTE
                next_micro_state = `ms_nop;
            end
            `ms_rtd1: begin   // RTD
                next_micro_state = `ms_rtd2;
            end
            `ms_rtd2: begin   // RTD
                setstackaddr   = 1'b1;
                set[`Regwrena] = 1'b1;
            end
            `ms_movec1: begin   // MOVEC
                set[`briefext]  = 1'b1;
                set_writePCbig  = 1'b1;
                if ((brief[11:0] == 12'h000 || brief[11:0] == 12'h001 || brief[11:0] == 12'h800 || brief[11:0] == 12'h801) ||
                    (CPU[1] && (brief[11:0] == 12'h002 || brief[11:0] == 12'h802 || brief[11:0] == 12'h803 || brief[11:0] == 12'h804))) begin
                    if (!opcode[0]) set[`Regwrena] = 1'b1;
                end else begin
                    trap_illegal = 1'b1;
                    trapmake     = 1'b1;
                end
            end
            `ms_movep1: begin   // MOVEP d(An)
                setdisp        = 1'b1;
                set[`mem_addsub] = 1'b1;
                set[`mem_byte] = 1'b1;
                set[`OP1addr]  = 1'b1;
                if (opcode[6]) set[`movepl] = 1'b1;
                if (!opcode[7]) setstate = 2'b10;
                else            setstate = 2'b11;
                next_micro_state = `ms_movep2;
            end
            `ms_movep2: begin
                if (opcode[6]) begin
                    set[`mem_addsub] = 1'b1;
                    set[`OP1addr]    = 1'b1;
                end
                if (!opcode[7]) setstate = 2'b10;
                else            setstate = 2'b11;
                next_micro_state = `ms_movep3;
            end
            `ms_movep3: begin
                if (opcode[6]) begin
                    set[`mem_addsub] = 1'b1;
                    set[`OP1addr]    = 1'b1;
                    set[`mem_byte]   = 1'b1;
                    if (!opcode[7]) setstate = 2'b10;
                    else            setstate = 2'b11;
                    next_micro_state = `ms_movep4;
                end else
                    datatype = 2'b01;   // Word
            end
            `ms_movep4: begin
                if (!opcode[7]) setstate = 2'b10;
                else            setstate = 2'b11;
                next_micro_state = `ms_movep5;
            end
            `ms_movep5: begin
                datatype = 2'b10;   // Long
            end
            `ms_mul1: begin   // mulu
                if (opcode[15] || MUL_Mode == 0) set_rot_cnt = 6'b001110;
                else                             set_rot_cnt = 6'b011110;
                setstate         = 2'b01;
                next_micro_state = `ms_mul2;
            end
            `ms_mul2: begin   // mulu
                setstate = 2'b01;
                if (rot_cnt == 6'b000001) next_micro_state = `ms_mul_end1;
                else                      next_micro_state = `ms_mul2;
            end
            `ms_mul_end1: begin   // mulu
                if (!opcode[15]) set[`hold_OP2] = 1'b1;
                datatype      = 2'b10;
                set[`opcMULU] = 1'b1;
                if (!opcode[15] && (MUL_Mode == 1 || MUL_Mode == 2)) begin
                    dest_2ndHbits       = 1'b1;
                    set[`write_lowlong] = 1'b1;
                    if (sndOPC[10]) begin
                        setstate         = 2'b01;
                        next_micro_state = `ms_mul_end2;
                    end
                    set[`Regwrena] = 1'b1;
                end
                datatype = 2'b10;
            end
            `ms_mul_end2: begin   // divu
                dest_2ndLbits       = 1'b1;
                set[`write_reminder]= 1'b1;
                set[`Regwrena]      = 1'b1;
                set[`opcMULU]       = 1'b1;
            end
            `ms_div1: begin   // divu
                setstate         = 2'b01;
                next_micro_state = `ms_div2;
            end
            `ms_div2: begin   // divu
                if ((OP2out[31:16] == 16'h0000 || opcode[15] || DIV_Mode == 0) && OP2out[15:0] == 16'h0000)   // div zero
                    set_Z_error = 1'b1;
                else
                    next_micro_state = `ms_div3;
                set[`ld_rot_cnt] = 1'b1;
                setstate         = 2'b01;
            end
            `ms_div3: begin   // divu
                if (opcode[15] || DIV_Mode == 0) set_rot_cnt = 6'b001101;
                else                             set_rot_cnt = 6'b011101;
                setstate         = 2'b01;
                next_micro_state = `ms_div4;
            end
            `ms_div4: begin   // divu
                setstate = 2'b01;
                if (rot_cnt == 6'b000001) next_micro_state = `ms_div_end1;
                else                      next_micro_state = `ms_div4;
            end
            `ms_div_end1: begin   // divu
                if (!Z_error && !set_V_Flag) set[`Regwrena] = 1'b1;
                if (!opcode[15] && (DIV_Mode == 1 || DIV_Mode == 2)) begin
                    dest_2ndLbits       = 1'b1;
                    set[`write_reminder]= 1'b1;
                    next_micro_state    = `ms_div_end2;
                    setstate            = 2'b01;
                end
                set[`opcDIVU] = 1'b1;
                datatype      = 2'b10;
            end
            `ms_div_end2: begin   // divu
                if (exec[`Regwrena]) set[`Regwrena] = 1'b1;
                else                 set[`no_Flags] = 1'b1;
                dest_2ndHbits = 1'b1;
                set[`opcDIVU] = 1'b1;
            end
            `ms_rota1: begin
                if (OP2out[5:0] != 6'b000000) set_rot_cnt = OP2out[5:0];
                else                          set_exec[`rot_nop] = 1'b1;
            end
            `ms_bf1: begin
                setstate = 2'b10;
            end
            default: ;
        endcase

        // generic "get_ea_now => setstate=10" default (VHDL 1576), evaluated here
        // so set[`get_ea_now] reflects its final value. In the VHDL this is an
        // early default that later opcode code can override to "01"; those
        // overrides leave setstate non-zero, so we only apply the default when no
        // override has changed setstate from its 2'b00 reset value.
        if (!ea_only && set[`get_ea_now] && setstate == 2'b00)
            setstate = 2'b10;

        // generic longaktion (VHDL 1582): evaluated here, after the micro_state
        // CASE and the get_ea_now default, so setstate reflects its final value
        // (matches the VHDL signal that settles to the CASE-assigned value).
        if (setstate[1] && set_datatype[1])
            set[`longaktion] = 1'b1;
    end

    // -------------------------------------------------------------------------
    // micro_state / trapd register (VHDL 3239-3246, split from decode process)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (Reset)
            micro_state <= `ms_ld_nn;
        else if (clkena_lw) begin
            trapd       <= trapmake;
            micro_state <= next_micro_state;
        end
    end

    // -------------------------------------------------------------------------
    // MOVEC (VHDL 4005-4041)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (Reset) begin
            VBR  <= 32'b0;
            CACR <= 4'b0;
        end else if (clkena_lw && exec[`movec_wr]) begin
            case (brief[11:0])
                12'h000: SFC  <= reg_QA[2:0];   // SFC  68010+
                12'h001: DFC  <= reg_QA[2:0];   // DFC  68010+
                12'h002: CACR <= reg_QA[3:0];   // 68020+
                12'h800: ;                       // USP  68010+
                12'h801: VBR  <= reg_QA;        // 68010+
                12'h802: ;                       // CAAR 68020+
                12'h803: ;                       // MSP  68020+
                12'h804: ;                       // ISP  68020+
                default: ;
            endcase
        end
    end

    always_comb begin
        movec_data = 32'b0;
        case (brief[11:0])
            12'h000: movec_data = {29'b0, SFC};
            12'h001: movec_data = {29'b0, DFC};
            12'h002: movec_data = {28'b0, (CACR & 4'b0011)};
            12'h801: movec_data = VBR;
            default: ;
        endcase
    end

    assign CACR_out = CACR;
    assign VBR_out  = VBR;

    // -------------------------------------------------------------------------
    // Conditions (VHDL 4045-4066)
    // -------------------------------------------------------------------------
    always_comb begin
        case (exe_opcode[11:8])
            4'h0: exe_condition = 1'b1;
            4'h1: exe_condition = 1'b0;
            4'h2: exe_condition = ~Flags[0] & ~Flags[2];
            4'h3: exe_condition = Flags[0] | Flags[2];
            4'h4: exe_condition = ~Flags[0];
            4'h5: exe_condition = Flags[0];
            4'h6: exe_condition = ~Flags[2];
            4'h7: exe_condition = Flags[2];
            4'h8: exe_condition = ~Flags[1];
            4'h9: exe_condition = Flags[1];
            4'ha: exe_condition = ~Flags[3];
            4'hb: exe_condition = Flags[3];
            4'hc: exe_condition = (Flags[3] & Flags[1]) | (~Flags[3] & ~Flags[1]);
            4'hd: exe_condition = (Flags[3] & ~Flags[1]) | (~Flags[3] & Flags[1]);
            4'he: exe_condition = (Flags[3] & Flags[1] & ~Flags[2]) | (~Flags[3] & ~Flags[1] & ~Flags[2]);
            4'hf: exe_condition = (Flags[3] & ~Flags[1]) | (~Flags[3] & Flags[1]) | Flags[2];
            default: exe_condition = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Movem (VHDL 4071-4101)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (clkena_lw) begin
            movem_actiond <= exec[`movem_action];
            if (decodeOPC)
                sndOPC <= data_read[15:0];
            else if (exec[`movem_action] || set[`movem_action]) begin
                case (movem_regaddr)
                    4'b0000: sndOPC[0]  <= 1'b0;
                    4'b0001: sndOPC[1]  <= 1'b0;
                    4'b0010: sndOPC[2]  <= 1'b0;
                    4'b0011: sndOPC[3]  <= 1'b0;
                    4'b0100: sndOPC[4]  <= 1'b0;
                    4'b0101: sndOPC[5]  <= 1'b0;
                    4'b0110: sndOPC[6]  <= 1'b0;
                    4'b0111: sndOPC[7]  <= 1'b0;
                    4'b1000: sndOPC[8]  <= 1'b0;
                    4'b1001: sndOPC[9]  <= 1'b0;
                    4'b1010: sndOPC[10] <= 1'b0;
                    4'b1011: sndOPC[11] <= 1'b0;
                    4'b1100: sndOPC[12] <= 1'b0;
                    4'b1101: sndOPC[13] <= 1'b0;
                    4'b1110: sndOPC[14] <= 1'b0;
                    4'b1111: sndOPC[15] <= 1'b0;
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Movem mux (VHDL 4103-4136)
    // -------------------------------------------------------------------------
    always_comb begin
        movem_regaddr = 4'b0000;
        movem_run     = 1'b1;
        movem_mux     = sndOPC[3:0];
        if (sndOPC[3:0] == 4'b0000) begin
            if (sndOPC[7:4] == 4'b0000) begin
                movem_regaddr[3] = 1'b1;
                if (sndOPC[11:8] == 4'b0000) begin
                    if (sndOPC[15:12] == 4'b0000) movem_run = 1'b0;
                    movem_regaddr[2] = 1'b1;
                    movem_mux        = sndOPC[15:12];
                end else
                    movem_mux = sndOPC[11:8];
            end else begin
                movem_mux        = sndOPC[7:4];
                movem_regaddr[2] = 1'b1;
            end
        end else
            movem_mux = sndOPC[3:0];

        if (movem_mux[1:0] == 2'b00) begin
            movem_regaddr[1] = 1'b1;
            if (!movem_mux[2]) movem_regaddr[0] = 1'b1;
        end else begin
            if (!movem_mux[0]) movem_regaddr[0] = 1'b1;
        end
    end

endmodule
