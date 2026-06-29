// buptest.cpp - Verilator harness mirroring Emu68's startup CHIP-RAM bus test
// against the Un-PiStorm chipset-facing bridge. Writes pseudo-random patterns,
// reads them back in word + byte widths, and checks integrity. PASS == the
// bridge bus-master FSM and data path are correct against the model.
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Vtb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static Vtb_top* dut;
static vluint64_t tick=0;
static void step(){ dut->clk=0; dut->eval(); tick++; dut->clk=1; dut->eval(); tick++; }

// One full access via the abstract request interface; returns read data (word).
static uint16_t access(bool we,bool uds_n,bool lds_n,uint32_t word_addr,uint16_t wdata){
    dut->req=1; dut->we=we; dut->uds_n=uds_n; dut->lds_n=lds_n;
    dut->addr=word_addr & 0x7FFFFF; dut->wdata=wdata;
    int guard=0;
    do{ step(); if(++guard>64){fprintf(stderr,"TIMEOUT on access\n");break;} }while(!dut->ack);
    dut->req=0; uint16_t r=dut->rdata; step(); // settle, deassert
    return r;
}
static inline uint16_t wr(uint32_t a,uint16_t d){ return access(true ,0,0,a,d); }
static inline uint16_t rd(uint32_t a){ return access(false,0,0,a,0); }

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vtb_top;
    dut->clk=0; dut->rst_n=0; dut->req=0; dut->we=0; dut->uds_n=1; dut->lds_n=1;
    dut->addr=0; dut->wdata=0;
    for(int i=0;i<8;i++) step();
    dut->rst_n=1; for(int i=0;i<4;i++) step();

    const uint32_t WORDS=4096;          // 8 KB CHIP test region (like buptest=8)
    std::vector<uint16_t> ref(WORDS);
    uint32_t seed=0xC0FFEEu, errors=0, checks=0;
    auto nxt=[&](){ seed=seed*1664525u+1013904223u; return (uint16_t)(seed>>11); };

    // Pass 1: word write then verify all.
    for(uint32_t a=0;a<WORDS;a++){ uint16_t d=nxt(); ref[a]=d; wr(a,d); }
    for(uint32_t a=0;a<WORDS;a++){ uint16_t got=rd(a); checks++; if(got!=ref[a]){ if(errors<8) printf("  word  @%05X exp=%04X got=%04X\n",a,ref[a],got); errors++; } }

    // Pass 2: byte writes (UDS/LDS masking) on a sub-range, then word read-back.
    for(uint32_t a=0;a<256;a++){
        uint16_t hi=nxt(), lo=nxt();
        access(true,/*uds*/0,/*lds*/1,a,(uint16_t)(hi<<8));   // write high byte only
        access(true,/*uds*/1,/*lds*/0,a,(uint16_t)(lo&0xFF)); // write low byte only
        ref[a]=(uint16_t)((hi<<8)|(lo&0xFF));
    }
    for(uint32_t a=0;a<256;a++){ uint16_t got=rd(a); checks++; if(got!=ref[a]){ if(errors<8) printf("  byte  @%05X exp=%04X got=%04X\n",a,ref[a],got); errors++; } }

    printf("buptest: %u checks, %u errors  ->  %s\n",checks,errors,errors?"FAIL":"PASS");
    dut->final(); delete dut;
    return errors?1:0;
}
