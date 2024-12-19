PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
 
  ;; LCD instructions
E  = %10000000
RW = %01000000
RS = %00100000
DDRAM = %11000000

  ;; Buttons
BUTTON_P2_UP =     %00001000
BUTTON_P2_DOWN =   %00000100
BUTTON_P1_DOWN =   %00000010
BUTTON_P1_UP =     %00000001
BUTTON_MASK = %00001111

  ;; Paddle positions
TOP_LEFT = %10000000       ; top: xor with 01000000
BOT_LEFT = %11000000
TOP_RIGHT = %10001111       ; bot: xor with 01000000
BOT_RIGHT = %11001111
PADDLE_TOGGLE = %01000000

BALL_DELAY = 2
SHOW_SCORE_DELAY = 400 ; this is in a tight loop, so this needs to be much higher than ball delay  
SCORE_LIMIT = 2 

  ;; Global variables
p1DispPos = $0200
p2DispPos = $0201
ballDispPos = $0202
ballDir = $0203
ballIconIndex = $0204
ballDelayCounter = $0205
tmp = $0206                     ; need to emulate register-register comparison
p1Score = $0207
p2Score = $0208 

  .org $8000
ballArray:
  .ascii "_.-^^-._^-.__.-^"     ; first 8 upper, second 8 lower
gameOver:
  .asciiz "Game Over!"
reset:
  ldx #$FF                      ; Set stack pointer
  txs

;; LCD init
  lda #%11111111                ; Set all pins on port B to output
  sta DDRB
  lda #%11100000                ; Set top 3 pins and last on port A to output
  sta DDRA
  lda #%00111000                ; Set 8-bit mode; 2-line display; 5x8 font
  jsr lcd_instruction
  lda #%00001100                ; Display on; cursor off; blink off
  jsr lcd_instruction
  lda #%00000100                ; Don't shift cursor; don't shift display
  jsr lcd_instruction
  lda #%00000001                ; Clear display
  jsr lcd_instruction

;; Global state init
  lda #TOP_LEFT
  sta p1DispPos
  lda #TOP_RIGHT
  sta p2DispPos
  lda #TOP_LEFT   ; will be incremented before showing
  sta ballDispPos
  lda #1
  sta ballDir                   ; 1 = right, -1 = left
  lda #-1                       ; will be incremented before showing
  sta ballIconIndex
  lda #BALL_DELAY
  sta ballDelayCounter
  lda #0
  sta p1Score
  lda #0
  sta p2Score

game_loop:
  jsr check_buttons
  jsr redraw_paddles
  lda ballDelayCounter
  dec
  sta ballDelayCounter ; doesn't work with just dec, requires reload (why?)
  lda ballDelayCounter
  cmp #0
  bne game_loop                 ; if != 0 (if we have waited long enough)
  lda #BALL_DELAY               ; reset ball delay counter
  sta ballDelayCounter
  ;;   update ball
  jsr erase_ball
  jsr update_ball_icon
  lda ballDispPos
  clc                           ; IDK why the carry bit is set here, but it is...
  adc ballDir
  sta ballDispPos
  jsr update_ball_row
  jsr check_collision
  jsr redraw_ball
  jmp game_loop

check_buttons:
  lda PORTA
  and #BUTTON_MASK
  tax                           ; save, might clobber and then need later
p1_check:
  cmp #BUTTON_P1_UP
  beq p1_up
  cmp #BUTTON_P1_DOWN
  beq p1_down
  jmp p2_check
p1_up:
  lda #TOP_LEFT
  sta p1DispPos
  jmp p2_check
p1_down:
  lda #BOT_LEFT
  sta p1DispPos
p2_check:
  txa                           ; reload, p1_check might have clobbered
  cmp #BUTTON_P2_UP
  beq p2_up
  cmp #BUTTON_P2_DOWN
  beq p2_down
  jmp finish_check
p2_up:
  lda #TOP_RIGHT
  sta p2DispPos
  jmp finish_check
p2_down:
  lda #BOT_RIGHT
  sta p2DispPos
finish_check:
  rts

update_ball_row:                        ; check icon index, set row
  lda ballIconIndex                     ; should be in range
  and #%1000
  beq set_upper                         ; 0 = first 8 chars = upper row
set_lower:
  lda ballDispPos
  ora #%01000000
  jmp end_update_ball_row
set_upper:
  lda ballDispPos
  and #%00001111
end_update_ball_row:
  sta ballDispPos
  rts

erase_ball:
  lda ballDispPos
  ldx #' '
  jsr print_char                ; a = pos, x = char
  rts

redraw_ball:
  ldx ballIconIndex
  lda ballArray,x
  tax
  lda ballDispPos
  jsr print_char                    ; a = pos, x = char
  rts

update_ball_icon:
  lda ballIconIndex
  clc                             ; necessary?
  adc ballDir
  bmi goto_icon_end               ; if we went negative, loop around
  cmp #16                         ; if got up to 16, loop around
  beq goto_icon_start
  jmp end_update_ball_icon
goto_icon_end:
  lda #15
  jmp end_update_ball_icon
goto_icon_start:
  lda #0
end_update_ball_icon:
  sta ballIconIndex             ; save result
  rts

check_collision:                  
  lda ballDispPos                 ; new potential ballDispPos
  and #%00001111                  ; only care about last 4 bits for now
  cmp #0 ; necessary?
  beq check_collision_left        ; all zeros: left collsion
  lda ballDispPos ; necessary? or still there from above?
  and #%00001111
  cmp #%00001111 ; necessary?
  beq check_collision_right
  rts
check_collision_left:
  lda ballDispPos
  and #%01000000                ; this bit determines top/bot
  sta tmp
  lda p1DispPos
  and #%01000000
  cmp tmp
  beq handle_collision
  jmp p2_score
check_collision_right:
  lda ballDispPos
  and #%01000000                ; this bit determintes top/bot
  sta tmp
  lda p2DispPos
  and #%01000000
  cmp tmp
  beq handle_collision
  jmp p1_score

p1_score:
  inc p1Score
  jsr show_score
  lda #%10001110                ; next to top-right p2
  sta ballDispPos
  lda #-1
  sta ballDir
  lda #15
  sta ballIconIndex
  lda #BALL_DELAY
  sta ballDelayCounter
  jmp game_loop

p2_score:
  inc p2Score
  jsr show_score
  lda #%10000001                ; next to top-left p1
  sta ballDispPos
  lda #1
  sta ballDir                   ; 1 = right, -1 = left
  lda #0
  sta ballIconIndex
  lda #BALL_DELAY
  sta ballDelayCounter
  jmp game_loop

handle_collision:
  jsr flip_dir
  adc ballDispPos               ; now a has real ball position
  sta ballDispPos
  jsr update_ball_icon                  ; update AGAIN
  jsr update_ball_row                   ; set row AGAIN
  rts
 
flip_dir:
  lda ballDir
  eor #$FF
  inc
  sta ballDir
  rts

redraw_paddles:
  lda p1DispPos
  jsr draw_one_paddle
  lda p2DispPos
  jsr draw_one_paddle
  rts                           ; return

  ;; redraw a paddle: load |, print to Pos, load ' ', print to OTHER (Pos ^ PADDLE_TOGGLE)  
draw_one_paddle:                ; a is paddle position
  pha                           ; save b/c print_char clobbers a (I think?)
  ldx #'|'
  jsr print_char
  pla                           ; reload paddle position
  eor #PADDLE_TOGGLE             ; flip to other position
  ldx #' '
  jsr print_char
  rts

show_score:
  lda p1Score
  clc
  adc #'0'                       ; forms score digit char
  tax
  lda #$04
  jsr print_char
  lda p2Score
  clc
  adc #'0'
  tax
  lda #$0c
  jsr print_char
  lda p1Score
  cmp #SCORE_LIMIT
  beq game_over
  lda p2Score
  cmp #SCORE_LIMIT
  beq game_over
  ;; game not over, so delay before returning
  lda #SHOW_SCORE_DELAY
show_score_loop:
  dec
  bne show_score_loop
  ;; clear
  ldx #' '
  lda #$04
  jsr print_char
  lda #$0c
  jsr print_char
  rts

game_over: ;;  show game over, then just loop
  ldy #0
  lda #$44
game_over_msg_loop:
  ldx gameOver,y
  beq end_game_loop
  jsr print_char
  inc                           ; next position
  jmp game_over_msg_loop

end_game_loop:                  ; final state
  jmp end_game_loop

lcd_wait:
  pha
  lda #%00000000  ; Port B is input
  sta DDRB
lcdbusy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000
  bne lcdbusy

  lda #RW
  sta PORTA
  lda #%11111111  ; Port B is output
  sta DDRB
  pla
  rts

lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  rts

print_char:                     ; a = position, x = character
  ora #%10000000                 ; make sure to set high bit
  sta DDRAM
  jsr lcd_instruction
  jsr lcd_wait                  ; make sure it's done
  stx PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA
  rts

  .org $fffc
  .word reset
  .word $0000
