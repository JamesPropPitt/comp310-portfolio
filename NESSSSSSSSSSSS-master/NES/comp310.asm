    .inesprg 1
    .ineschr 1
    .inesmap 0
    .inesmir 1

; ---------------------------------------------------------------------------

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
OAMDATA   = $2004
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOYPAD1   = $4016
JOYPAD2   = $4017

BUTTON_A      = %10000000
BUTTON_B      = %01000000
BUTTON_SELECT = %00100000
BUTTON_START  = %00010000
BUTTON_UP     = %00001000
BUTTON_DOWN   = %00000100
BUTTON_LEFT   = %00000010
BUTTON_RIGHT  = %00000001

ENEMY_SQUAD_WIDTH    = 6
ENEMY_SQUAD_HEIGHT   = 4
NUM_ENEMIES          = ENEMY_SQUAD_WIDTH * ENEMY_SQUAD_HEIGHT
ENEMY_SPACING        = 16
ENEMY_DESCENT_SPEED  = 4

ENEMY_HITBOX_WIDTH   = 8
ENEMY_HITBOX_HEIGHT  = 8
BULLET_HITBOX_X      = 3 ; Relative to sprite top left corner
BULLET_HITBOX_Y      = 1
BULLET_HITBOX_WIDTH  = 2
BULLET_HITBOX_HEIGHT = 6

    .rsset $0010
player_speed        .rs 1
player_position_sub .rs 1

    .rsset $0000
joypad1_state      .rs 1
bullet_active      .rs 1
temp_x             .rs 1
temp_y             .rs 1
enemy_info         .rs 4 * NUM_ENEMIES

    .rsset $0200
sprite_player      .rs 4
sprite_bullet      .rs 4
sprite_enemy       .rs 4 * NUM_ENEMIES
sprite_ai          .rs 4


    .rsset $0000
SPRITE_Y           .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X           .rs 1

    .rsset $0000
SPRITE2_Y          .rs 1
SPRITE2_TILE       .rs 1
SPRITE2_ATTRIB     .rs 1
SPRITE2_X          .rs 1

    .rsset $0000
ENEMY_SPEED        .rs 1
ENEMY_ALIVE        .rs 1

GRAVITY                = 1
FLAP_SPEED             = -1 * 100   ; in subpixels/frame
SCREEN_BOTTOM_Y        = 224
    .bank 0
    .org $C000

; Initialisation code based on https://wiki.nesdev.com/w/index.php/Init_code
RESET:
    SEI        ; ignore IRQs
    CLD        ; disable decimal mode
    LDX #$40
    STX $4017  ; disable APU frame IRQ
    LDX #$ff
    TXS        ; Set up stack
    INX        ; now X = 0
    STX PPUCTRL  ; disable NMI
    STX PPUMASK  ; disable rendering
    STX $4010  ; disable DMC IRQs

    ; Optional (omitted):
    ; Set up mapper and jmp to further init code here.

    ; If the user presses Reset during vblank, the PPU may reset
    ; with the vblank flag still true.  This has about a 1 in 13
    ; chance of happening on NTSC or 2 in 9 on PAL.  Clear the
    ; flag now so the vblankwait1 loop sees an actual vblank.
    BIT PPUSTATUS

    ; First of two waits for vertical blank to make sure that the
    ; PPU has stabilized
vblankwait1:  
    BIT PPUSTATUS
    BPL vblankwait1

    ; We now have about 30,000 cycles to burn before the PPU stabilizes.
    ; One thing we can do with this time is put RAM in a known state.
    ; Here we fill it with $00, which matches what (say) a C compiler
    ; expects for BSS.  Conveniently, X is still 0.
    TXA
clrmem:
    LDA #0
    STA $000,x
    STA $100,x
    STA $300,x
    STA $400,x
    STA $500,x
    STA $600,x
    STA $700,x  ; Remove this if you're storing reset-persistent data

    ; We skipped $200,x on purpose.  Usually, RAM page 2 is used for the
    ; display list to be copied to OAM.  OAM needs to be initialized to
    ; $EF-$FF, not 0, or you'll get a bunch of garbage sprites at (0, 0).

    LDA #$FF
    STA $200,x

    INX
    BNE clrmem

    ; Other things you can do between vblank waits are set up audio
    ; or set up other mapper registers.
   
vblankwait2:
    BIT PPUSTATUS
    BPL vblankwait2

    ; End of initialisation code

    JSR InitialiseGame

    LDA #%10000000 ; Enable NMI
    STA PPUCTRL

    LDA #%00010000 ; Enable sprites
    STA PPUMASK

    ; Enter an infinite loop
forever:
    JMP forever

; ---------------------------------------------------------------------------

InitialiseGame: ; Begin subroutine
    ; Reset the PPU high/low latch
    LDA PPUSTATUS

    ; Write address $3F10 (background colour) to the PPU
    LDA #$3F
    STA PPUADDR
    LDA #$10
    STA PPUADDR

    ; Write the background colour
    LDA #$1
    STA PPUDATA

    ; Write the palette colours
    LDA #$17
    STA PPUDATA
    LDA #$0F
    STA PPUDATA
    LDA #$27
    STA PPUDATA

    ; Write sprite data for sprite 0
    LDA #200    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #0      ; Tile number
    STA sprite_player + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_player + SPRITE_ATTRIB
    LDA #128    ; X position
    STA sprite_player + SPRITE_X
    
    ; Write sprite data for sprite 4
    LDA #20     ; Y Position
    STA sprite_ai + SPRITE2_Y 
    LDA #3      ; Tile Number
    STA sprite_ai + SPRITE2_TILE
    LDA #0      ; Attributes
    STA sprite_ai + SPRITE2_ATTRIB
    LDA #128    ; X Position
    STA sprite_ai + SPRITE2_X 

    ; Initialise enemies
    LDX #0
    LDA #ENEMY_SQUAD_HEIGHT * ENEMY_SPACING
    STA temp_y
InitEnemies_LoopY:
    LDA #ENEMY_SQUAD_WIDTH * ENEMY_SPACING
    STA temp_x
InitEnemies_LoopX:
    ; Accumulator = temp_x here
    STA sprite_enemy+SPRITE_X, x
    LDA temp_y
    STA sprite_enemy+SPRITE_Y, x
    LDA #0
    STA sprite_enemy+SPRITE_ATTRIB, x
    LDA #2
    STA sprite_enemy+SPRITE_TILE, x
    STA enemy_info+ENEMY_SPEED, x
    STA enemy_info+ENEMY_ALIVE, x
    ; Increment X register by 4
    TXA
    CLC
    ADC #4
    TAX
    ; Loop check for x value
    LDA temp_x
    SEC
    SBC #ENEMY_SPACING
    STA temp_x
    BNE InitEnemies_LoopX
    ; Loop check for y value
    LDA temp_y
    SEC
    SBC #ENEMY_SPACING
    STA temp_y
    BNE InitEnemies_LoopY

    RTS ; End subroutine

; ---------------------------------------------------------------------------

; NMI is called on every frame
NMI:
    ; Initialise controller 1
    LDA #1
    STA JOYPAD1
    LDA #0
    STA JOYPAD1
    ; LDA sprite_player + SPRITE_Y
    ; SEC
    ; SBC #-1
    ; STA sprite_player + SPRITE_Y
    ; Read joypad state
    LDX #0
    STX joypad1_state
ReadController:
    LDA JOYPAD1
    LSR A
    ROL joypad1_state
    INX
    CPX #8
    BNE ReadController

    ; React to Right button
    LDA joypad1_state
    AND #BUTTON_RIGHT
    BEQ ReadRight_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_X
    CLC
    ADC #1
    STA sprite_player + SPRITE_X
    STA sprite_ai + SPRITE2_X
ReadRight_Done:         ; }

    ; React to Down button
    LDA joypad1_state
    AND #BUTTON_DOWN
    BEQ ReadDown_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_Y
    CLC
    ADC #1
    STA sprite_player + SPRITE_Y
    STA sprite_ai + SPRITE2_Y
ReadDown_Done:         ; }

    ; React to Left button
    LDA joypad1_state
    AND #BUTTON_LEFT
    BEQ ReadLeft_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_X
    SEC
    SBC #1
    STA sprite_player + SPRITE_X
    STA sprite_ai + SPRITE2_X
ReadLeft_Done:         ; }

    ; React to Up button
    LDA joypad1_state
    AND #BUTTON_UP
    BEQ ReadUp_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_Y
    SEC
    SBC #1
    STA sprite_player + SPRITE_Y
ReadUp_Done:         ; }

    ; Update player sprite
	; First, update speed
	LDA player_speed     ; Low 8 bits
	CLC
	ADC #LOW(GRAVITY)
	STA player_speed
	LDA player_speed+1   ; High 8 bits
	ADC #HIGH(GRAVITY)   ; NB: don't clear the carry flag!
	STA player_speed+1
	
	; Second, update position
	LDA player_position_sub     ; Low 8 bits
	CLC
	ADC player_speed
	STA player_position_sub
	LDA sprite_player+SPRITE_Y  ; High 8 bits
	ADC player_speed+1			; NB: don't clear the carry flag!
	STA sprite_player+SPRITE_Y
	
	; Check for top or bottom of screen
	CMP #SCREEN_BOTTOM_Y       ; Accumulator already contains y position
	BCC UpdatePlayer_NoClamp
	; Check sign of speed
	LDA player_speed+1
	BMI UpdatePlayer_ClampToTop
	LDA #SCREEN_BOTTOM_Y-1     ; Clamp to bottom
	JMP UpdatePlayer_DoClamping
UpdatePlayer_ClampToTop:
	LDA #0					   ; Clamp to top
UpdatePlayer_DoClamping:
	STA sprite_player+SPRITE_Y
	LDA #0                     ; Set player speed to zero
	STA player_speed           ; (both bytes)  
	STA player_speed+1
	
UpdatePlayer_NoClamp:

    ; React to A button
    LDA joypad1_state
    AND #BUTTON_A
    BEQ ReadA_Done
    ; Spawn a bullet if one is not active
    LDA bullet_active
    BNE ReadA_Done
    ; No bullet active, so spawn one
    LDA #1
    STA bullet_active
    LDA sprite_player + SPRITE_Y    ; Y position
    STA sprite_bullet + SPRITE_Y
    LDA #1      ; Tile number
    STA sprite_bullet + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_bullet + SPRITE_ATTRIB
    LDA sprite_player + SPRITE_X    ; X position
    LDA sprite_bullet + SPRITE_X
ReadA_Done:

    ; Update the bullet
    LDA bullet_active
    BEQ UpdateBullet_Done
    LDA sprite_bullet + SPRITE_Y
    SEC
    SBC #5
    STA sprite_bullet + SPRITE_Y
    BCS UpdateBullet_Done
    ; If carry flag is clear, bullet has left the top of the screen -- destroy it
    LDA #0
    STA bullet_active
UpdateBullet_Done:

    ; Update enemies
    LDX #(NUM_ENEMIES-1)*4
UpdateEnemies_Loop:
    ; Check if enemy is alive
    LDA enemy_info+ENEMY_ALIVE, x
    BNE UpdateEnemies_Start
    JMP UpdateEnemies_Next
UpdateEnemies_Start:
    LDA sprite_enemy+SPRITE_X, x
    CLC
    ADC enemy_info+ENEMY_SPEED, x
    STA sprite_enemy+SPRITE_X, x
    CMP #256 - ENEMY_SPACING
    BCS UpdateEnemies_Reverse
    CMP #ENEMY_SPACING
    BCC UpdateEnemies_Reverse
    JMP UpdateEnemies_NoReverse
UpdateEnemies_Reverse:
    ; Reverse direction and descend
    LDA #0
    SEC
    SBC enemy_info+ENEMY_SPEED, x
    STA enemy_info+ENEMY_SPEED, x
    LDA sprite_enemy+SPRITE_Y, x
    CLC
    ADC #ENEMY_DESCENT_SPEED
    STA sprite_enemy+SPRITE_Y, x
    LDA sprite_enemy+SPRITE_ATTRIB, x
    EOR #%01000000
    STA sprite_enemy+SPRITE_ATTRIB, x
UpdateEnemies_NoReverse:

                               ;             \1        \2        \3            \4            \5            \6            \7
CheckCollisionWithEnemy .macro ; parameters: object_x, object_y, object_hit_x, object_hit_y, object_hit_w, object_hit_h, no_collision_label
    ; If there is a collision, execution continues immediately after this macro
    ; Else, jump to no_collision_label
    LDA sprite_enemy+SPRITE_X, x  ; Calculate x_enemy - w_bullet - 1 (x1-w2-1)
    .if \3 > 0
    SEC
    SBC \3
    .endif
    SEC
    SBC \5+1
    CMP \1                        ; Compare with x_bullet (x2)
    BCS \7                        ; Branch if x1-w2-1-BULLET_HITBOX_X >= x2 i.e. x1-w2 > x2
    CLC
    ADC \5+1+ENEMY_HITBOX_WIDTH   ; Calculate x_enemy + w_enemy (x1+w1), assuming w1 = 8
    CMP \1                        ; Compare with x_bullet (x2)
    BCC \7                        ; Branching if x1+w1-BULLET_HITBOX_X < x2

    LDA sprite_enemy+SPRITE_Y, x  ; Calculate y_enemy - h_bullet (y1-h2)
    .if \3 > 0
    SEC
    SBC \4
    .endif
    SEC
    SBC \6+1                
    CMP \2                        ; Compare with y_bullet (y2)
    BCS \7                        ; Branch if y1-h2 > y2
    CLC
    ADC \6+1+ENEMY_HITBOX_HEIGHT  ; Calculate y_enemy + h_enemy (y1+h1), assuming h1 = 8
    CMP \2                        ; Compare with y_bullet (y2)
    BCC \7                        ; Branching if y1+h1 < y2
    .endm

    ; Check collision with bullet
    CheckCollisionWithEnemy sprite_bullet+SPRITE_X, sprite_bullet+SPRITE_Y, #BULLET_HITBOX_X, #BULLET_HITBOX_Y, #BULLET_HITBOX_WIDTH, #BULLET_HITBOX_HEIGHT, UpdateEnemies_NoCollision
    ; Handle collision
    LDA #0                        ; Destroy the bullet and the enemy
    STA bullet_active
    STA enemy_info+ENEMY_ALIVE, x
    LDA #$FF
    STA sprite_bullet+SPRITE_Y
    STA sprite_enemy+SPRITE_Y, x
UpdateEnemies_NoCollision:

    ; Check collision with player
    CheckCollisionWithEnemy sprite_player+SPRITE_X, sprite_player+SPRITE_Y, #0, #0, #8, #8, UpdateEnemies_NoCollisionWithPlayer
    ; Handle collision
    JSR InitialiseGame
    JMP UpdateEnemies_End
UpdateEnemies_NoCollisionWithPlayer:

UpdateEnemies_Next:
    DEX
    DEX
    DEX
    DEX
    BMI UpdateEnemies_End
    JMP UpdateEnemies_Loop
UpdateEnemies_End:

    ; Copy sprite data to the PPU
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    RTI         ; Return from interrupt

; ---------------------------------------------------------------------------

    .bank 1
    .org $FFFA
    .dw NMI
    .dw RESET
    .dw 0

; ---------------------------------------------------------------------------

    .bank 2
    .org $0000
    .incbin "comp310.chr"