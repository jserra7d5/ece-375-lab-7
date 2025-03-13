; Timer/Counter 1 countdown for 6 seconds with 1.5s LED intervals
; For ATmega32u4 running at 8MHz
; Uses Timer/Counter 1 in normal mode with 1024 prescaler
; LEDs on PB7-PB4 turn off sequentially every 1.5 seconds

.include "m32u4def.inc"

; Constants
.equ DELAY_PRELOAD = 53817 ; 65536 - 11719

.org 0x0000
    rjmp RESET           ; Reset Handler
.org 0x0028              ; Timer1 Overflow vector for ATmega32u4
    rjmp TIMER1_OVF      ; Timer1 Overflow Handler

.def temp = r16          ; Temporary register
.def counter = r17       ; Counter for tracking 1.5s intervals
.def led_state = r18     ; Store LED state

RESET:
    ; Initialize stack pointer
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp
    
    ; Configure PORTB (PB7-PB4) as outputs
    ldi temp, 0xF0       ; Set PB7-PB4 as outputs
    out DDRB, temp
    
    ; Initialize LED state (all LEDs on)
    ldi led_state, 0xF0  ; PB7-PB4 all on
    out PORTB, led_state
    
    ; Initialize counter to start at 0
    ldi counter, 0
    
    ; Configure Timer/Counter 1
    ; Using normal mode, prescaler = 1024
    ldi temp, 0x00       ; Normal mode (WGM13:0 = 0000)
    sts TCCR1A, temp
    
    ; Preload timer to almost overflow immediately 
    ; Using 65535 instead of DELAY_PRELOAD for first overflow
    ldi temp, 0xFF       ; 65535 (one count before overflow)
    sts TCNT1L, temp
    ldi temp, 0xFF
    sts TCNT1H, temp
    
    ; Enable Timer/Counter 1 overflow interrupt
    ldi temp, (1<<TOIE1)
    sts TIMSK1, temp
    
    ; Start the timer with prescaler = 1024
    ldi temp, (1<<CS12) | (1<<CS10)  ; Prescaler = 1024
    sts TCCR1B, temp
    
    ; Enable global interrupts
    sei
    
    ; Enter infinite loop
MAIN_LOOP:
    rjmp MAIN_LOOP

; Timer1 Overflow Interrupt Service Routine
TIMER1_OVF:
    ; Preload timer for next 1.5s interval
    ldi temp, low(DELAY_PRELOAD)
    sts TCNT1L, temp
    ldi temp, high(DELAY_PRELOAD)
    sts TCNT1H, temp
    
    ; Increment counter and check which LED to turn off next
    inc counter
    
    cpi counter, 1
    breq TURN_OFF_PB7
    cpi counter, 2
    breq TURN_OFF_PB6
    cpi counter, 3
    breq TURN_OFF_PB5
    cpi counter, 4
    breq TURN_OFF_PB4
    
    ; Check if it's time to reset
    cpi counter, 5       ; After 6 seconds (4 LEDs off)
    brsh RESET_SEQUENCE  ; Reset if counter >= 5
    reti
    
RESET_SEQUENCE:
    ; Reset the sequence - turn all LEDs back on
    ldi led_state, 0xF0  ; All LEDs on
    out PORTB, led_state
    ldi counter, 0       ; Reset counter
    reti
    
TURN_OFF_PB7:
    andi led_state, ~(1<<7)  ; Turn off PB7
    out PORTB, led_state
    reti
    
TURN_OFF_PB6:
    andi led_state, ~(1<<6)  ; Turn off PB6
    out PORTB, led_state
    reti
    
TURN_OFF_PB5:
    andi led_state, ~(1<<5)  ; Turn off PB5
    out PORTB, led_state
    reti
    
TURN_OFF_PB4:
    andi led_state, ~(1<<4)  ; Turn off PB4
    out PORTB, led_state
    reti