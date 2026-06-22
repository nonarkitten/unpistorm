all: pwr_led_blink.hex

%.bin: %.s
	vasmm68k_mot -Fbin $< -o $@

%.hex: %.bin
	xxd -c2 -p $< > $@

clean:
	rm -f *.hex *.bin
