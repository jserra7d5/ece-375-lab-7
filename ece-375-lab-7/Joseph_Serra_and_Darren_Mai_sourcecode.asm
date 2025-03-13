
;***********************************************************
;*
;*	This is the TRANSMIT skeleton file for Lab 7 of ECE 375
;*
;*  	Rock Paper Scissors
;* 	Requirement:
;* 	1. USART1 communication
;* 	2. Timer/counter1 Normal mode to create a 1.5-sec delay
;***********************************************************
;*
;*	 Author: Joseph Serra and Darren Mai
;*	   Date: 3/12/2025
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16               ; Multi-Purpose Register
.def	buffer = r17
.def	led_state = r18
.def	game_state = r19
.def	mpr2 = r23

; Use this signal code between two boards for their game ready
.equ    SendReady = 0b11111111

.equ	DELAY_PRELOAD = 53817 ; 65536 - 11719
.equ	DEBOUNCE_PRELOAD = 64364   ; Preload value for ~150ms debounce delay

.equ	Button_4 = 0 ; jump PD4 to PD0
.equ    Button_7 = 1 ; jump PD7 to PD3

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
	    rjmp    INIT            	; Reset interrupt

.org	$0002
		rcall PD4_ISR
		reti

.org	$0004
		rcall PD7_ISR
		reti

.org	$0028 ; T/C interrupt 1
		rcall Timer1_OVF_ISR
		reti

.org	$0032
		rcall USART_Recieve
		reti

.org	$0046
		rcall Timer3_OVF_ISR
		reti

.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
	; initialize stack pointer
	ldi	mpr, low(RAMEND)
	out	SPL, mpr
	ldi	mpr, high(RAMEND)
	out SPH, mpr

	; set game state readying up
	clr game_state

	; Initialize Port B for output
	ldi	mpr, $FF		; Set Port B Data Direction Register
	out	DDRB, mpr		; for output
	ldi	mpr, $00		; Initialize Port B Data Register
	out	PORTB, mpr		; so all Port B outputs are low

	; initialize port D for input
	ldi	mpr, $00
	out DDRD, mpr
	ldi mpr, $FF
	out	PORTD, mpr

	; initialize button interrupts
	ldi mpr, 0b00001010
	sts EICRA, mpr

	ldi mpr, (1<<Button_4 | 1<<Button_7)
	out EIMSK, mpr

	; USART1 Init

	; Set baudrate at 2400
	ldi mpr, high(207)
	sts UBRR1H, mpr
	ldi mpr, low(207)
	sts UBRR1L, mpr

	; Enable both transmitter and receiver, and receive interrupt
	ldi mpr, (1<<RXEN1 | 1<<TXEN1 | 1<<RXCIE1)
	sts UCSR1B, mpr

	; Set frame format: 8 data, 2 stop bits, asynchronous
	ldi mpr, (1<<USBS1 | 1<<UCSZ11 | 1<<UCSZ10)
	sts UCSR1C, mpr

	; initialize timer/counter 1

	; Clear our flag variables
    rcall GAME_RESET

	; copy all of our strings over and point Y at our LCD writes
	rcall COPY_ALL_STRINGS
	rcall LCDInit
	rcall LCDClr
	sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
	cpi game_state, 0
	breq State_0
	

	cpi game_state, 1
	breq State_1

	cpi game_state, 2
	breq State_2

	State_0:
		ldi XL, low(welcome_string)
		ldi XH, high(welcome_string)
		ldi YL, low(press_pd7_string)
		ldi YH, high(press_pd7_string)

		lds mpr, ready_flag
		tst mpr ; are we ready?
		breq MAIN_END ; no? jump to main

		ldi XL, low(ready_string_one)
		ldi XH, high(ready_string_one)
		ldi YL, low(ready_string_two)
		ldi YH, high(ready_string_two)

		lds mpr, partner_ready_flag
		tst mpr ; is our partner ready?
		breq MAIN_END ; no? jump to main

		; at this point both players are ready
		inc game_state

	State_1:
		ldi XL, low(main_string)
		ldi XH, high(main_string)
		ldi YL, low(main_string)
		ldi YH, high(main_string)

		lds mpr, sixsec_flag ; is our 6s timer already running?
		sbrs mpr, 0
		rcall Timer_1_Setup
		rjmp MAIN_END

	State_2:
		;lds mpr, third_stage_first_run
		;tst mpr
		;brne State_2_Skip
		;ldi mpr, 1
		;sts third_stage_first_run, mpr
		;rcall Timer_1_Setup

		;State_2_Skip:
		ldi XL, low(result_string)
		ldi XH, high(result_string)
		ldi YL, low(result_string)
		ldi YH, high(result_string)



	MAIN_END:
		rcall COPY_TO_LCD
	rjmp	MAIN

;***********************************************************
;*	Functions and Subroutines
;***********************************************************

USART_Transmit:
	push mpr
	lds	mpr, UCSR1A
	sbrs mpr, UDRE1
	rjmp USART_Transmit
	sts UDR1, buffer
	pop mpr
	ret

USART_Recieve:
	push mpr
	lds buffer, UDR1

	cpi buffer, SendReady ; did our opponent send a ready signal?
	breq Partner_Ready


	Partner_Ready:
		ldi mpr, 1
		sts partner_ready_flag, mpr


	pop mpr
	ret


Timer_1_Setup:
; --- Stop Timer1 first (in case it's already running) ---
	ldi mpr, 1
	sts sixsec_flag, mpr

    sbi PORTB, 7
    sbi PORTB, 6
    sbi PORTB, 5
    sbi PORTB, 4

    clr led_state   ; led_state = 0

    ; Preload Timer1 for a 1.5s delay
    ; (If needed, clear TOV1 by writing 1 to it in TIFR1)
    ldi   mpr, low(DELAY_PRELOAD)
    sts   TCNT1L, mpr
    ldi   mpr, high(DELAY_PRELOAD)
    sts   TCNT1H, mpr

    ; Normal mode, prescaler 1024, enable Timer1 Overflow Interrupt
    clr   mpr
    sts   TCCR1A, mpr
    ldi   mpr, (1<<CS12) | (1<<CS10)
    sts   TCCR1B, mpr
    ldi   mpr, (1<<TOIE1)
    sts   TIMSK1, mpr

    ret
;------------------------------------------------------------------
; Timer/Counter1 Overflow ISR (LED Countdown Timer)
;------------------------------------------------------------------
Timer1_OVF_ISR:
    inc led_state
    cpi led_state, 1
    brne L1
    cbi PORTB, 7
    rjmp Reload

L1:
    cpi led_state, 2
    brne L2
    cbi PORTB, 6
    rjmp Reload

L2:
    cpi led_state, 3
    brne L3
    cbi PORTB, 5
    rjmp Reload

L3:
    cpi led_state, 4
    brne Reload
    cbi PORTB, 4
    ; Countdown finished, do whatever else you want here
    ; e.g. disable Timer1 or move to next game state
    ; clr TCCR1B / TIMSK1 if you want to stop repeats
	clr   mpr
    sts   TCCR1B, mpr
	sts   TIMSK1, mpr
	ldi r16, (1<<TOV1)
    out TIFR1, r16
	inc game_state
    ret

Reload:
    ; Clear TOV1 if needed
    ldi r16, (1<<TOV1)
    sts TIFR1, r16

    ; Reload Timer1
    ldi   r16, low(DELAY_PRELOAD)
    sts   TCNT1L, r16
    ldi   r16, high(DELAY_PRELOAD)
    sts   TCNT1H, r16
    ret



GAME_RESET:
	clr game_state
	clr buffer
	clr mpr
    sts debounce_flag, mpr
    sts sixsec_flag, mpr
	sts ready_flag, mpr
	sts partner_ready_flag, mpr
	sts third_stage_first_run, mpr
	ret

PD4_ISR:
	push mpr
	lds   mpr, debounce_flag
    tst   mpr
    brne  PD4_exit


    ldi   mpr, 1
    sts   debounce_flag, mpr

    ; --- Start debounce using Timer3 ---
    ldi   mpr, low(DEBOUNCE_PRELOAD)
    sts   TCNT3L, mpr
    ldi   r16, high(DEBOUNCE_PRELOAD)
    sts   TCNT3H, r16

    clr   mpr
    sts   TCCR3A, mpr

    ldi   mpr, (1<<CS32) | (1<<CS30)
    sts   TCCR3B, mpr

    ldi   mpr, (1<<TOIE3)
    sts   TIMSK3, mpr

    

PD4_exit:
	pop   mpr
    ret

PD7_ISR:
	push mpr

	lds mpr, ready_flag
	tst mpr ; have we readied up yet?
	brne PD7_exit ; we have, end ISR

	ldi mpr, 1
	sts ready_flag, mpr ; ready us up

	ldi buffer, SendReady
	rcall USART_Transmit ; send ready signal

PD7_exit:
	pop mpr
	ret

Timer3_OVF_ISR:
	push mpr
    ; Clear debounce flag so a new button press can be processed
    ldi   mpr, 0
    sts   debounce_flag, mpr

    ; Stop Timer/Counter3 by clearing its clock source (TCCR3B)
    clr   mpr
    sts   TCCR3B, mpr

    ; Disable Timer/Counter3 Overflow Interrupt by clearing TIMSK3
    clr   mpr
    sts   TIMSK3, mpr

	pop mpr

    ret          

COPY_TO_LCD:
	push mpr

	rcall LCDClr
	ldi ZL, low(0x0100)
	ldi ZH, high(0x0100)

	ldi mpr2, 16
	TOP_LOOP:
	ld mpr, X+
	st Z+, mpr
	dec mpr2
	brne TOP_LOOP


	ldi ZL, low(0x0110)
	ldi ZH, high(0x0110)

	ldi mpr2, 16
	BOTTOM_LOOP:
	ld mpr, Y+
	st Z+, mpr
	dec mpr2
	brne BOTTOM_LOOP

	pop mpr
	rcall LCDWrite
	ret



COPY_ALL_STRINGS:
	; Copy welcome_string (16 bytes)
    ldi   ZL, low(WELCOME_START * 2)
    ldi   ZH, high(WELCOME_START * 2)
    ldi   YL, low(welcome_string)
    ldi   YH, high(welcome_string)
    rcall Copy16BytesFromProgmem

    ; Copy press_pd7_string (16 bytes)
    ldi   ZL, low(PRESS_PD7_START * 2)
    ldi   ZH, high(PRESS_PD7_START * 2)
    ldi   YL, low(press_pd7_string)
    ldi   YH, high(press_pd7_string)
    rcall Copy16BytesFromProgmem

    ; Copy ready_string_one (16 bytes)
    ldi   ZL, low(READY_LINE_ONE_START * 2)
    ldi   ZH, high(READY_LINE_ONE_START * 2)
    ldi   YL, low(ready_string_one)
    ldi   YH, high(ready_string_one)
    rcall Copy16BytesFromProgmem

    ; Copy ready_string_two (16 bytes)
    ldi   ZL, low(READY_LINE_TWO_START * 2)
    ldi   ZH, high(READY_LINE_TWO_START * 2)
    ldi   YL, low(ready_string_two)
    ldi   YH, high(ready_string_two)
    rcall Copy16BytesFromProgmem

    ; Copy main_string (16 bytes)
    ldi   ZL, low(MAIN_PHASE_START * 2)
    ldi   ZH, high(MAIN_PHASE_START * 2)
    ldi   YL, low(main_string)
    ldi   YH, high(main_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(RESULTS_START * 2)
    ldi   ZH, high(RESULTS_START * 2)
    ldi   YL, low(result_string)
    ldi   YH, high(result_string)
    rcall Copy16BytesFromProgmem

    ret

Copy16BytesFromProgmem:
    ldi   mpr, 16        ; Set loop counter to 16 bytes
Copy16Loop:
    lpm   r0, Z+         ; Load a byte from program memory using Z, then increment Z.
    st    Y+, r0         ; Store the byte into data memory at Y, then increment Y.
    dec   mpr           ; Decrement the loop counter.
    brne  Copy16Loop     ; Repeat loop until counter reaches zero.
    ret                  ; Return from subroutine.

;***********************************************************
;*	Stored Program Data
;***********************************************************
.dseg
.org 0x0200           
debounce_flag: .byte 1
sixsec_flag: .byte 1
ready_flag: .byte 1
partner_ready_flag: .byte 1
third_stage_first_run: .byte 1
welcome_string: .byte 16
press_pd7_string: .byte 16
ready_string_one: .byte 16
ready_string_two: .byte 16
main_string: .byte 16
result_string: .byte 16
;-----------------------------------------------------------
; An example of storing a string. Note the labels before and
; after the .DB directive; these can help to access the data
;-----------------------------------------------------------
.cseg
WELCOME_START:
    .DB		"Welcome!        "		; Declaring data in ProgMem

PRESS_PD7_START:
	.DB		"Please press PD7"

READY_LINE_ONE_START:
	.DB		"READY. Waiting  "

READY_LINE_TWO_START:
	.DB		"for the opponent"

MAIN_PHASE_START:
	.DB		"MAIN PHASE      "

RESULTS_START:
	.DB		"Result Stage    "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"		; Include the LCD Driver

