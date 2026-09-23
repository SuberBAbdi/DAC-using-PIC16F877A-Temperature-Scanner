LIST P=16F877A
    INCLUDE "P16F877A.INC"

    ; --- Configuration Bits ---
    __CONFIG _HS_OSC & _WDT_OFF & _LVP_OFF & _PWRTE_ON

    ; --- Register Variable RAM Allocations (Bank 0) ---
    CBLOCK 0x20
        T1_RES_LOW      ; Raw ADC low byte (Thermistor 1)
        T1_RES_HIGH     ; Raw ADC high byte 
        T2_RES_LOW      ; Raw ADC low byte (Thermistor 2)
        T2_RES_HIGH     ; Raw ADC high byte
        AVG_RESULT      ; Combined 8-bit result for the DAC
        LCD_TEMP        ; Temporary data holder for LCD routines
        DELAY_1         ; For time delay loops
        DELAY_2
    ENDC

    ORG 0x0000          ; Reset Vector
    GOTO INITIALIZE

; -------------------------------------------------------------
; INITIALIZATION SUBROUTINE
; -------------------------------------------------------------
INITIALIZE:
    ; 1. Port Directions Setup
    BANKSEL TRISA       ; Switch to Bank 1
    MOVLW   B'00000011' ; RA0 and RA1 are inputs (Thermistors)
    MOVWF   TRISA
    CLRF    TRISD       ; PORTD is entirely Output (LCD Pins)
    BCF     TRISC, 2    ; RC2/CCP1 is output for our "Internal DAC" (PWM)

    ; 2. Configure ADC Peripheral Pins
    MOVLW   B'00000100' ; AN0, AN1 analog inputs. VREF = VDD/VSS
    MOVWF   ADCON1

    ; 3. Setup Internal DAC Module (PWM Mode)
    ; Set PWM Period Register (PR2) for ~20kHz at 20MHz clock
    MOVLW   D'255'      
    MOVWF   PR2         

    BANKSEL PORTA       ; Return to Bank 0
    ; Configure CCP1 for PWM Mode
    MOVLW   B'00001100' ; Bits 5-4 are LSBs of Duty Cycle, Bits 3-0 set PWM mode
    MOVWF   CCP1CON
    ; Turn Timer 2 ON with 1:1 Prescaler to establish PWM timing
    MOVLW   B'00000100' 
    MOVWF   T2CON       

    ; 4. Turn On ADC Module
    MOVLW   B'10000001' ; Fosc/32 clock conversion rate, select AN0, module ON
    MOVWF   ADCON0

    ; 5. Bring up LCD Hardware
    CALL    LCD_INIT
    GOTO    MAIN_LOOP

; -------------------------------------------------------------
; MAIN EXECUTION LOOP
; -------------------------------------------------------------
MAIN_LOOP:
    ; --- Read Thermistor 1 (AN0) ---
    BANKSEL ADCON0
    BCF     ADCON0, 5   ; Clear Channel select bits to target AN0
    BCF     ADCON0, 4
    BCF     ADCON0, 3
    CALL    TAKE_READING
    MOVWF   T1_RES_HIGH ; Keep the high bits of the reading

    ; --- Read Thermistor 2 (AN1) ---
    BSF     ADCON0, 3   ; Move channel selection to AN1
    CALL    TAKE_READING
    MOVWF   T2_RES_HIGH ; Keep the high bits of the reading

    ; --- "DAC" Processing (Average the two results) ---
    MOVF    T1_RES_HIGH, W
    ADDWF   T2_RES_HIGH, W
    MOVWF   AVG_RESULT
    RCF     AVG_RESULT, F ; Bitwise shift right divides the sum by 2
    
    ; Output the averaged result directly to the DAC (PWM Duty Cycle Register)
    MOVF    AVG_RESULT, W
    MOVWF   CCPR1L      

    ; --- Update the LCD Text ---
    CALL    LCD_CLEAR
    
    ; Display Header
    MOVLW   'T'
    CALL    LCD_DATA
    MOVLW   'E'
    CALL    LCD_DATA
    MOVLW   'M'
    CALL    LCD_DATA
    MOVLW   'P'
    CALL    LCD_DATA
    MOVLW   ':'
    CALL    LCD_DATA

    ; Long delay before sampling again
    CALL    LONG_DELAY
    GOTO    MAIN_LOOP

; -------------------------------------------------------------
; HARDWARE SUBROUTINES
; -------------------------------------------------------------
TAKE_READING:
    CALL    SHORT_DELAY ; Channel acquisition lag
    BSF     ADCON0, GO  ; Fire the ADC conversion process
WAIT_ADC:
    BTFSC   ADCON0, GO  ; Watch the status flag drop
    GOTO    WAIT_ADC
    MOVF    ADRESH, W   ; Grab the converted 8-bit MSB byte
    RETURN

; --- Character LCD Drivers (Mapped to PORTD) ---
LCD_INIT:
    MOVLW   D'40'
    CALL    SHORT_DELAY
    MOVLW   0x38        ; 8-bit mode initialization command
    CALL    LCD_CMD
    MOVLW   0x0C        ; Screen ON, Cursor Hidden command
    CALL    LCD_CMD
    RETURN

LCD_CMD:
    MOVWF   PORTD       ; Put command on pins
    BCF     PORTD, 0    ; Pull Register Select (RS = RD0) LOW for Command Mode
    BSF     PORTD, 1    ; Pulse Enable (EN = RD1) High
    NOP
    BCF     PORTD, 1    ; Pull Enable Low
    CALL    SHORT_DELAY
    RETURN

LCD_DATA:
    MOVWF   PORTD       ; Put character byte on pins
    BSF     PORTD, 0    ; Pull Register Select (RS = RD0) HIGH for Character Data Mode
    BSF     PORTD, 1    ; Pulse Enable High
    NOP
    BCF     PORTD, 1    ; Pull Enable Low
    CALL    SHORT_DELAY
    RETURN

LCD_CLEAR:
    MOVLW   0x01        ; Clear Screen instructions
    CALL    LCD_CMD
    RETURN

; --- Timing Utility Delays ---
SHORT_DELAY:
    MOVLW   D'250'
    MOVWF   DELAY_1
SD_LOOP:
    DECFSZ  DELAY_1, F
    GOTO    SD_LOOP
    RETURN

LONG_DELAY:
    MOVLW   D'255'
    MOVWF   DELAY_1
LD_LOOP_1:
    MOVLW   D'255'
    MOVWF   DELAY_2
LD_LOOP_2:
    DECFSZ  DELAY_2, F
    GOTO    LD_LOOP_2
    DECFSZ  DELAY_1, F
    GOTO    LD_LOOP_1
    RETURN

    END                 ; End of Source File Assembly Instruction
