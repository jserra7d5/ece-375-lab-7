
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
.def	game_state = r19
.def	mpr2 = r23

; Use this signal code between two boards for their game ready
.equ    SendReady = 0b11111111
.equ    SendRock = 0b00000000
.equ    SendPaper = 0b00000001
.equ    SendScissors = 0b00000010

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

;.org	$0028 ; T/C interrupt 1
		;rjmp TIMER1_OVF

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
	;clr game_state
	clr mpr2

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
	ldi mpr, high(416)
	sts UBRR1H, mpr
	ldi mpr, low(416)
	sts UBRR1L, mpr

	ldi		mpr, (1<<U2X1)
	sts		UCSR1A, mpr

	; Enable both transmitter and receiver, and receive interrupt
	ldi mpr, (1<<RXEN1 | 1<<TXEN1 | 1<<RXCIE1)
	sts UCSR1B, mpr

	; Set frame format: 8 data, 2 stop bits, asynchronous
	ldi mpr, (1<<USBS1 | 1<<UCSZ11 | 1<<UCSZ10)
	sts UCSR1C, mpr

	; Clear our flag variables
    
	;ldi game_state, 1

	ldi		mpr, 0
	out		TCCR0A, mpr
	ldi		mpr, 0b00000101
	out		TCCR0B, mpr

	; copy all of our strings over and point Y at our LCD writes
	rcall COPY_ALL_STRINGS
	rcall LCDInit
	rcall LCDClr
	rcall GAME_RESET
	sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
	State_0:
		ldi XL, low(welcome_string)
		ldi XH, high(welcome_string)
		ldi YL, low(press_pd7_string)
		ldi YH, high(press_pd7_string)

		lds mpr, ready_flag
		tst mpr ; are we ready?
		breq State_0_LED_COPY ; no? jump

		ldi XL, low(ready_string_one)
		ldi XH, high(ready_string_one)
		ldi YL, low(ready_string_two)
		ldi YH, high(ready_string_two)

		lds mpr, partner_ready_flag
		tst mpr ; is our partner ready?
		brne State_1 ; yes? jump to state 1
		State_0_LED_COPY:
		rcall COPY_TO_LCD
		rjmp MAIN

		; at this point both players are ready
		;inc game_state

	State_1:
		ldi game_state, 1
		rcall USART_Transmit
		ldi XL, low(game_start_string)
		ldi XH, high(game_start_string)
		ldi YL, low(blank_string)
		ldi YH, high(blank_string)
		rcall COPY_TO_LCD
		sbi PORTB, 7
		sbi PORTB, 6
		sbi PORTB, 5
		sbi PORTB, 4
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 7
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 6
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 5
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 4
		rcall WAIT_ONE_AND_HALF ; so both boards can recieve data

	State_2:
		clr game_state
		ldi XL, low(partner_string)
		ldi XH, high(partner_string)
		ldi YL, low(hand_string)
		ldi YH, high(hand_string)
		rcall COPY_TO_LCD
		sbi PORTB, 7
		sbi PORTB, 6
		sbi PORTB, 5
		sbi PORTB, 4
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 7
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 6
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 5
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 4
		rcall WAIT_ONE_AND_HALF

	State_3:
		ldi YL, low(hand_string)
		ldi YH, high(hand_string)

		lds mpr, hand_state_byte
		lds mpr2, partner_result
		cp mpr, mpr2
		brne Not_Draw

		ldi XL, low(draw_string)
		ldi XH, high(draw_string)
		rjmp State_3_End

		Not_Draw:
		cpi mpr, 0 ; did we select rock?
		breq ROCK_SELECT
		cpi mpr, 1 ; did we select paper?
		breq PAPER_SELECT
		cpi mpr, 2 ; did we select scissors?
		breq SCISSORS_SELECT

		ROCK_SELECT:
		cpi mpr2, 2 ; did our opponent select scissors?
		breq WIN_jmp ; yes? we won
		rjmp LOSS_jmp ; no; we lost.

		PAPER_SELECT:
		cpi mpr2, 0 ; did our opponent select rock?
		breq WIN_jmp
		rjmp LOSS_jmp

		SCISSORS_SELECT:
		cpi mpr2, 1 ; did our opponent select paper?
		breq WIN_jmp
		rjmp LOSS_jmp


		WIN_jmp:
		ldi XL, low(win_string)
		ldi XH, high(win_string)
		rjmp State_3_End

		LOSS_jmp:
		ldi XL, low(loss_string)
		ldi XH, high(loss_string)
		rjmp State_3_End

		State_3_End:
		rcall COPY_TO_LCD
		sbi PORTB, 7
		sbi PORTB, 6
		sbi PORTB, 5
		sbi PORTB, 4
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 7
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 6
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 5
		rcall WAIT_ONE_AND_HALF
		cbi PORTB, 4
		rcall WAIT_ONE_AND_HALF

		rcall GAME_RESET

	rjmp	MAIN

;***********************************************************
;*	Functions and Subroutines
;***********************************************************


WAIT_ONE_AND_HALF:
	ldi	mpr2, 150	; wait half a second
WAIT_10ms:
	ldi	mpr, 178
	out	TCNT0, mpr
WAIT_LOOP:
	in r18, TIFR0
	andi r18, 0b00000001
	breq WAIT_LOOP
	ldi	r18, 0b00000001
	out TIFR0, r18
	dec mpr2
	brne WAIT_10ms
	ret

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
	push XL
	push XH

	cpi buffer, SendReady ; did our opponent send a ready signal?
	breq Partner_Ready

	cpi buffer, SendRock ; did our opponent send a rock signal?
	breq Rock_Sent

	cpi buffer, SendPaper
	breq Paper_Sent

	cpi buffer, SendScissors
	breq Scissors_Sent

	Partner_Ready:
		ldi mpr, 1
		sts partner_ready_flag, mpr
		rjmp Rx_End

	Rock_Sent:
		ldi mpr, SendRock
		sts partner_result, mpr
		ldi XL, low(rock_string)
		ldi XH, high(rock_string)
		rcall PARTNER_COPY_HAND
		rjmp Rx_End
	Paper_Sent:
		ldi mpr, SendPaper
		sts partner_result, mpr
		ldi XL, low(paper_string)
		ldi XH, high(paper_string)
		rcall PARTNER_COPY_HAND
		rjmp Rx_End
	Scissors_Sent:
		ldi mpr, SendScissors
		sts partner_result, mpr
		ldi XL, low(scissors_string)
		ldi XH, high(scissors_string)
		rcall PARTNER_COPY_HAND
		rjmp Rx_End
		

	Rx_End:
	pop XH
	pop XL
	pop mpr
	ret

PARTNER_COPY_HAND:
	push mpr
	push mpr2
	push ZL
	push ZH

	ldi ZL, low(partner_string)
	ldi ZH, high(partner_string)

	ldi mpr2, 16
	PARTNER_COPY_HAND_LOOP:
	ld mpr, X+
	st Z+, mpr
	dec mpr2
	brne PARTNER_COPY_HAND_LOOP

	pop ZH
	pop ZL
	pop mpr2
	pop mpr
	ret


GAME_RESET:
	ldi mpr, 2
	sts hand_state_byte, mpr
	clr game_state
	clr buffer
	clr mpr
	clr mpr2
    sts debounce_flag, mpr
	sts ready_flag, mpr
	sts partner_ready_flag, mpr
	sts TCCR1B, mpr
	sts TIMSK1, mpr
	sts partner_result, mpr
	
	rcall COPY_ALL_STRINGS

	ret

PD4_ISR:
	push mpr
	push mpr2
	push ZL
	push ZH
	push XL
	push XH
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

	cpi game_state, 1 ; are we in the main  phase
	brne PD4_exit ; if not, skip

	lds mpr , hand_state_byte
	inc mpr ; if 2, goes to 3~ invalid option
	
	lds     mpr, hand_state_byte  
    inc     mpr                  
    cpi     mpr, 3              ;
    brlo    ContinueCycle       ;
    clr     mpr                 ; i
	ContinueCycle:
    sts     hand_state_byte, mpr  ; store updated value back

    ; --- Branch based on new value ---
    cpi     mpr, 0              ; 
    breq    choose_rock
    cpi     mpr, 1              ; 
    breq    choose_paper
    cpi     mpr, 2              ; 
    breq    choose_scissors
    rjmp    choose_scissors    ; fallback

	choose_rock:
	ldi YL, low(rock_string)
	ldi YH, high(rock_string)
	rjmp PD4_Pre_Copy

	choose_paper:
	ldi YL, low(paper_string)
	ldi YH, high(paper_string)
	rjmp PD4_Pre_Copy

	choose_scissors:
	ldi YL, low(scissors_string)
	ldi YH, high(scissors_string)

	PD4_Pre_Copy:
	sts hand_state_byte, mpr
	ldi ZL, low(0x0110)
	ldi ZH, high(0x0110)
	ldi XL, low(hand_string)
	ldi XH, high(hand_string)
	ldi mpr2, 16
	PD4_Copy:
	ld mpr, Y+
	st Z+, mpr
	st X+, mpr
	dec mpr2
	brne PD4_Copy
	rcall LCDWrLn2
	lds buffer, hand_state_byte
	rcall USART_Transmit
	

PD4_exit:
	pop XH
	pop XL
	pop ZH
	pop ZL
	pop mpr2
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
	push mpr2

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

	pop mpr2
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
    ldi   ZL, low(GAME_START * 2)
    ldi   ZH, high(GAME_START * 2)
    ldi   YL, low(game_start_string)
    ldi   YH, high(game_start_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(ROCK * 2)
    ldi   ZH, high(ROCK * 2)
    ldi   YL, low(rock_string)
    ldi   YH, high(rock_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(BLANK * 2)
    ldi   ZH, high(BLANK * 2)
    ldi   YL, low(hand_string)
    ldi   YH, high(hand_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(PAPER * 2)
    ldi   ZH, high(PAPER * 2)
    ldi   YL, low(paper_string)
    ldi   YH, high(paper_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(SCISSORS * 2)
    ldi   ZH, high(SCISSORS * 2)
    ldi   YL, low(scissors_string)
    ldi   YH, high(scissors_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(BLANK * 2)
    ldi   ZH, high(BLANK * 2)
    ldi   YL, low(partner_string)
    ldi   YH, high(partner_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(BLANK * 2)
    ldi   ZH, high(BLANK * 2)
    ldi   YL, low(blank_string)
    ldi   YH, high(blank_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(DRAW * 2)
    ldi   ZH, high(DRAW * 2)
    ldi   YL, low(draw_string)
    ldi   YH, high(draw_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(WIN * 2)
    ldi   ZH, high(WIN * 2)
    ldi   YL, low(win_string)
    ldi   YH, high(win_string)
    rcall Copy16BytesFromProgmem

	ldi   ZL, low(LOSS * 2)
    ldi   ZH, high(LOSS * 2)
    ldi   YL, low(loss_string)
    ldi   YH, high(loss_string)
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
ready_flag: .byte 1
partner_ready_flag: .byte 1
hand_state_byte: .byte 1
welcome_string: .byte 16
press_pd7_string: .byte 16
ready_string_one: .byte 16
ready_string_two: .byte 16
game_start_string: .byte 16
rock_string: .byte 16
paper_string: .byte 16
scissors_string: .byte 16
hand_string: .byte 16
partner_string: .byte 16
partner_result: .byte 1
draw_string: .byte 16
win_string: .byte 16
loss_string: .byte 16
blank_string: .byte 16

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

GAME_START:
	.DB		"GAME START      "

ROCK:
	.DB		"ROCK            "

PAPER:
	.DB		"PAPER           "

SCISSORS:
	.DB		"SCISSORS        "


BLANK:
	.DB		"                "

DRAW:
	.DB		"Draw.           "

WIN:
	.DB		"You Won!        "

LOSS:
	.DB		"You lost        "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"		; Include the LCD Driver

