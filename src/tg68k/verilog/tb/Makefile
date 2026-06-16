# Build + run the TG68K kernel testbench under Verilator.
#
#   make        - build and run
#   make build  - build only
#   make clean  - remove generated files

TOP      := TG68KdotC_Kernel
RTL_DIR  := ..
RTL      := $(RTL_DIR)/TG68KdotC_Kernel.v $(RTL_DIR)/TG68K_ALU.v
VINC     := -I$(RTL_DIR)
VFLAGS   := -sv -Wno-WIDTH -Wno-UNOPTFLAT -Wno-ALWCOMBORDER -Wno-CASEINCOMPLETE \
            -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-fatal --public-flat-rw

.PHONY: all build run clean
all: run

build:
	verilator --cc --exe --build -j 0 \
	    $(VFLAGS) $(VINC) \
	    --top-module $(TOP) $(RTL) sim_main.cpp

run: build
	@echo "==== running ===="
	@./obj_dir/V$(TOP)

clean:
	rm -rf obj_dir
