// ps_buptest.cpp - drives the REAL classic PiStorm register protocol against the
// full Un-PiStorm path (slave -> bridge -> chip-RAM), exactly as Emu68 would.
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Vtb_ps_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

#define REG_DATA 0
#define REG_ADDR_LO 1
#define REG_ADDR_HI 2
#define T_WW 0x00
#define T_BW 0x01
#define T_WR 0x02
#define T_BR 0x03

static Vtb_ps_top* d;
static void step(int n=1){ while(n--){ d->clk=0; d->eval(); d->clk=1; d->eval(); } }

static void wr_reg(int reg,uint16_t val){
    d->ps_a0 = reg&1; d->ps_a1 = (reg>>1)&1; d->ps_d_in = val; step(2);
    d->ps_wr = 1; step(4);
    d->ps_wr = 0; step(4);
}
static void poll_txn(){ int g=0; while(d->ps_txn){ step(); if(++g>200){fprintf(stderr,"TXN timeout\n");break;} } }

static void pi_write16(uint32_t a,uint16_t v){
    wr_reg(REG_DATA, v);
    wr_reg(REG_ADDR_LO, a & 0xffff);
    wr_reg(REG_ADDR_HI, (T_WW<<8) | ((a>>16)&0xff));   // triggers
    poll_txn();
}
static void pi_write8(uint32_t a,uint8_t b){
    uint16_t dup = (uint16_t)b | ((uint16_t)b<<8);
    wr_reg(REG_DATA, dup);
    wr_reg(REG_ADDR_LO, a & 0xffff);
    wr_reg(REG_ADDR_HI, (T_BW<<8) | ((a>>16)&0xff));
    poll_txn();
}
static uint16_t pi_read16(uint32_t a){
    wr_reg(REG_ADDR_LO, a & 0xffff);
    wr_reg(REG_ADDR_HI, (T_WR<<8) | ((a>>16)&0xff));    // triggers read
    d->ps_a0=0; d->ps_a1=0; d->ps_rd=1; step(3);        // select DATA, assert RD
    poll_txn();
    step(2); uint16_t v = d->ps_d_out;
    d->ps_rd=0; step(2);
    return v;
}
static uint8_t pi_read8(uint32_t a){
    wr_reg(REG_ADDR_LO, a & 0xffff);
    wr_reg(REG_ADDR_HI, (T_BR<<8) | ((a>>16)&0xff));
    d->ps_a0=0; d->ps_a1=0; d->ps_rd=1; step(3);
    poll_txn();
    step(2); uint16_t v = d->ps_d_out;
    d->ps_rd=0; step(2);
    return (a&1) ? (v&0xff) : (v>>8);
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    d=new Vtb_ps_top;
    d->clk=0; d->rst_n=0; d->ps_a0=0; d->ps_a1=0; d->ps_rd=0; d->ps_wr=0;
    d->ps_reset=0; d->ps_d_in=0;
    step(8); d->rst_n=1; step(4);

    const uint32_t WORDS=4096; uint32_t seed=0xC0FFEE, errs=0, checks=0;
    std::vector<uint16_t> ref(WORDS);
    auto nxt=[&](){ seed=seed*1664525u+1013904223u; return (uint16_t)(seed>>11); };

    // Pass 1: word write/read round-trip via the protocol
    for(uint32_t i=0;i<WORDS;i++){ uint16_t v=nxt(); ref[i]=v; pi_write16(i*2,v); }
    for(uint32_t i=0;i<WORDS;i++){ uint16_t g=pi_read16(i*2); checks++;
        if(g!=ref[i]){ if(errs<8)printf("  word @%06X exp=%04X got=%04X\n",i*2,ref[i],g); errs++; } }

    // Pass 2: byte writes (UDS/LDS masking) then word + byte read-back
    for(uint32_t i=0;i<256;i++){
        uint8_t hi=nxt()&0xff, lo=nxt()&0xff;
        pi_write8(i*2,   hi);   // even address -> high byte (UDS)
        pi_write8(i*2+1, lo);   // odd address  -> low byte  (LDS)
        ref[i]=(uint16_t)((hi<<8)|lo);
    }
    for(uint32_t i=0;i<256;i++){ uint16_t g=pi_read16(i*2); checks++;
        if(g!=ref[i]){ if(errs<8)printf("  byte @%06X exp=%04X got=%04X\n",i*2,ref[i],g); errs++; } }
    for(uint32_t i=0;i<64;i++){ // a few byte reads too
        uint8_t g=pi_read8(i*2); checks++; uint8_t e=ref[i]>>8;
        if(g!=e){ if(errs<8)printf("  bhi  @%06X exp=%02X got=%02X\n",i*2,e,g); errs++; } }

    printf("ps_buptest: %u checks, %u errors  ->  %s\n",checks,errs,errs?"FAIL":"PASS");
    d->final(); delete d; return errs?1:0;
}
