; ==== Constants ====
COLS equ 80
ROWS equ 25

; ==== Types ====
struc THREAD {
  ; Y position of head character. May be larger than physical number of rows if offscreen.
  .head_y db ?
  ; Y position of tail character. May be negative if offscreen.
  .tail_y db ?
  ; Rate of growth (moving the head downwards by 1) in # of frames.
  .grow_rate db ?
  ; Rate of shrinkage (moving the tail downwards by 1) in # of frames.
  .shrink_rate db ?
  ; Current head character.
  .head_char db ?
  .padding_1 db ?
}
SIZEOF_THREAD equ 6

struc COLUMN {
  ; Bitmap of which threads are active.
  .active_threads db 0
  .padding_1 db ?
  .threads 4 dup Thread
}
SIZEOF_COLUMN equ 26

; ==== Code ====
format mz

entry _code:start
stack 100h

segment _code

start:
      mov ax, _data
      mov ds, ax

      call rand_init
      call set_video_mode

      mov si, 20
  start_1:
      mov al, 1
      mov ah, 10
      push ax
      call rand_in_range
      add sp, 2
      push ax
      call print_number
      add sp, 2
      dec si
      jnz start_1

  start_2:
      push 1
      call sleep_ticks
      add sp, 2

      call check_keyboard
      jz start_2

      call exit


; Set video mode to 80x25
set_video_mode:
      mov al, 03h
      mov ah, 0h
      int 10h
      ret

; Set cursor position to (x, y)
; Example:
;    mov al, <x>
;    mov ah, <y>
;    push ax
;    call move_cursor
;    add sp, 2
move_cursor:
      enter 0, 0
      push bx
      mov dl, [bp+4]
      mov dh, [bp+5]
      mov bx, 0
      mov ah, 02h
      int 10h
      pop bx
      leave
      ret

; Sleep a given number of CPU ticks (~55ms).
; Example:
;    push 10
;    call sleep_ticks
;    add sp, 2
sleep_ticks:
      enter 0, 0
      ; bx = remaining ticks to wait
      ; si = higher 16 bits of current tick count
      ; di = lower 16 bits of current tick count
      push bx
      push si
      push di
      mov bx, [bp+4]
  sleep_ticks_1:
      cmp bx, 0
      je sleep_ticks_ret
      mov ah, 0h
      int 1ah
      mov di, dx
      mov si, cx
  sleep_ticks_2:
      hlt
      mov ah, 0h
      int 1ah
      cmp dx, di
      jne sleep_ticks_3
      cmp cx, si
      jne sleep_ticks_3
      jmp sleep_ticks_2
  sleep_ticks_3:
      dec bx
      jmp sleep_ticks_1
  sleep_ticks_ret:
      pop di
      pop si
      pop bx
      leave
      ret

; Check for key press (non-blocking).
; Result:
;    - Zero flag if no key pressed
;    - Non-zero flag if key pressed, ASCII value stored in al
check_keyboard:
      mov ah, 01h
      int 16h
      jz check_keyboard_ret
      mov ah, 0h
      int 16h
      xor ah, ah
      cmp al, 0
  check_keyboard_ret:
      ret

; Initializes our Fibonacci PRNG.
rand_init:
      mov ah, 0h
      int 1ah
      cmp cx, 0
      jne rand_init_1
      mov cx, dx
  rand_init_1:
      cmp dx, 0
      jne rand_init_2
      hlt
      jmp rand_init
  rand_init_2:
      push bx
      mov bx, rand_seeds
      mov [bx], cx
      mov [bx+2], dx
      pop bx
      ret

; Fibonacci PRNG.
; Returns a pseudo-random 8-bit integer in al.
rand:
      push bx
      mov bx, rand_seeds
      mov al, [bx]
      mov ah, [bx+1]
      add al, ah
      mov [bx], ah
      mov ah, [bx+2]
      add al, ah
      mov [bx+1], ah
      mov ah, [bx+3]
      add al, ah
      mov [bx+2], ah
      mov [bx+3], al
      mov ah, 0
      pop bx
      ret

; Generates a pseudo-random 8-bit integer between [min, max] inclusive. 
; Example:
;    mov al, <min>
;    mov ah, <max>
;    push ax
;    call rand_in_range
; Result is stored in al.
rand_in_range:
      enter 0, 0
      call rand
      mov dx, 0
      mov cl, [bp+5]
      sub cl, [bp+4]
      inc cl
      mov ch, 0
      div cx
      mov al, dl
      add al, [bp+4]
      mov ah, 0
      leave
      ret

; Print a 16-bit unsigned integer for debugging.
print_number:
      ; 16 bit values have a max of 5 decimal digits (65535). We also reserve
      ; space for newline and terminating '$'.
      enter 8, 0
      ; ax = remainder to print
      ; bx = char* pointing to start of string on stack
      ; di = 10
      push bx
      push di
      mov ax, [bp+4]
      mov bx, bp
      sub bx, 3
      mov byte [ss:bx], 0dh  ; '\r'
      mov byte [ss:bx+1], 0ah  ; '\n'
      mov byte [ss:bx+2], 24h  ; '$'
      mov di, 10
  print_number_1:
      mov dx, 0
      div di
      add dx, 30h  ; '0'
      dec bx
      mov [ss:bx], dl
      cmp ax, 0
      jne print_number_1
      push ds
      mov ax, ss
      mov ds, ax
      mov dx, bx
      mov ah, 09h
      int 21h
      pop ds
      pop di
      pop bx
      leave
      ret

; Exits the program.
exit:
      mov ax, 4c00h
      int 21h

; ==== Data ====
segment _data

; Fibonacci PRNG seeds
rand_seeds: db 4 dup 0

; Threads.
threads_by_column: rb SIZEOF_COLUMN * COLS

; Current frame number.
frame: dw 0

