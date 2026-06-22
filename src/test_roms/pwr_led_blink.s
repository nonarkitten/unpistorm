	;; power_led_blink.s
	;; basic cpu test, doesn't need any ram to work

	ORG $f80000
	
        bra.s   start-1   	; -1? wtf ...
        dc.w    $4ef9           ; jmp ...

        dc.l    $f80030
        dc.l    $f80008 

        ORG $f80030	
start:

	;; wait >80ms for minimig-aga syctrl reset to be gone
	move 	#60000,d0
iwlp0:	dbra	d0,iwlp0
	
	move.b	#3,$bfe201	; LED and OVL are outputs

mainlp:	bclr.b	#1,$bfe001	; LED on

	move 	#5,d1
owlp0:	move 	#50000,d0
wlp0:	dbra	d0,wlp0
	dbra	d1,owlp0
	
	bset.b	#1,$bfe001	; LED off
	
	move 	#5,d1
owlp1:	move 	#50000,d0
wlp1:	dbra	d0,wlp1
	dbra	d1,owlp1
	
	bra.s 	mainlp

