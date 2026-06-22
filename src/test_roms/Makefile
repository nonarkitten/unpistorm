all: ram_test.hex pwr_led_blink.hex video_init.hex

%.bin: %.s
	vasmm68k_mot -Fbin $< -o $@
	m68kdis -pc 0xf80000 $@

%.hex: %.bin
	xxd -c2 -p $< > $@

clean:
	rm -f *.bin.s *.hex *.bin
