; ==== Constants ====
COLS equ 80
ROWS equ 25
THREAD_GAP equ 8
NEW_THREAD_RATE equ 100
MIN_THREAD_LENGTH equ 4
MAX_THREAD_LENGTH equ 16
MAX_GROW_RATE equ 3
MIN_GROW_RATE equ 1
HEAD_COLOR equ 00001111b  ; white on black
COLOR equ 00000010b  ; green on black


; ==== Types ====
struc THREAD {
  ; X position of thread.
  .x db ?
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
}
virtual at 0
  THREAD THREAD
end virtual
SIZEOF_THREAD equ 6

struc COLUMN {
  ; Bitmap of which threads are active.
  .active_threads db 0
  .padding_1 db ?
  .threads rb 4*SIZEOF_THREAD
}
virtual at 0
  COLUMN COLUMN
end virtual
SIZEOF_COLUMN equ 26

; ==== Code ====
format mz

entry _code:start
stack 400h

segment _code

start:
      mov ax, _data
      mov ds, ax

      call rand_init
      call threads_init
      call set_video_mode
      call next_tick

  start_1:
      call next_frame
      inc word [frame_count]

      call next_tick

      call check_keyboard
      jz start_1

  start_ret:
      call set_video_mode  ; Clear screen
      call exit

; Render next frame.
next_frame:
      push create_thread
      call for_each_column
      push next_frame_for_column
      call for_each_column
      push destroy_thread
      call for_each_column
      add sp, 6
      ret

next_frame_for_column:
      enter 0, 0
      push bx
      push si

      mov bx, [bp+4]  ; pointer to COLUMN struct
      mov cx, 4  ; thread loop counter
      mov ah, 1  ; thread bitmask
      mov si, COLUMN.threads
    next_frame_for_column_loop:
      mov al, [bx+COLUMN.active_threads]
      and al, ah
      jz next_frame_for_column_end_loop

      push ax
      push cx
      lea dx, [bx+si]
      push dx
      call update_thread
      add sp, 2
      pop cx
      pop ax
    next_frame_for_column_end_loop:
      shl ah, 1
      add si, SIZEOF_THREAD
      loop next_frame_for_column_loop

      pop si
      pop bx
      leave
      ret


; Iterates over the the columns in threads_by_column.
; Argument is a function to be invoked with
;    - Address of COLUMN struct
;    - x position of column
for_each_column:
      enter 0, 0
      push bx

      mov dx, [bp+4]  ; function to call
      mov cx, 0  ; loop counter
      mov bx, threads_by_column
  for_each_column_loop:
      push dx
      push cx
      push bx
      call dx
      pop bx
      pop cx
      pop dx
      inc cx
      add bx, SIZEOF_COLUMN
      cmp cx, COLS
      jne for_each_column_loop

      pop bx
      leave
      ret


threads_init:
      push bx
      mov cx, (SIZEOF_COLUMN * COLS / 2)
      mov bx, threads_by_column
  threads_init_loop:
      mov word [bx], 0
      add bx, 2
      loop threads_init_loop
      pop bx
      ret


; Create threads in a particular column as needed.
; Arguments:
;    - X position of column.
;    - Address of COLUMN struct for that column.
create_thread:
      enter 0, 0
      push bx
      push si
      mov bx, [bp+4]  ; pointer to COLUMN struct

      ; Check if this column is eligible
      push bx
      call can_create_thread
      add sp, 2
      cmp al, 0
      je create_thread_ret
      ; Randomize
      mov al, 1
      mov ah, NEW_THREAD_RATE
      push ax
      call rand_in_range
      add sp, 2
      cmp al, 1
      jne create_thread_ret

      ; Find empty thread
      mov dl, [bx+COLUMN.active_threads]
      mov ah, 1  ; bitmask
      mov si, COLUMN.threads  ; pointer to thread
  create_thread_loop:
      mov al, dl
      and al, ah
      cmp al, 0
      je create_thread_1
      shl ah, 1
      add si, SIZEOF_THREAD
      jmp create_thread_loop

  create_thread_1:
      ; ah = bitmask for the THREAD struct to update
      or [bx+COLUMN.active_threads], ah

      ; bx+si point to the THREAD struct to update
      mov cx, [bp+6]
      mov [bx+si+THREAD.x], cl

      mov byte [bx+si+THREAD.head_y], -1

      mov al, MIN_THREAD_LENGTH
      mov ah, MAX_THREAD_LENGTH
      push ax
      call rand_in_range
      add sp, 2
      neg al
      mov [bx+si+THREAD.tail_y], al

      mov al, MIN_GROW_RATE
      mov ah, MAX_GROW_RATE
      push ax
      call rand_in_range
      add sp, 2
      mov [bx+si+THREAD.grow_rate], al

      ; al (min) is grow_rate
      mov ah, MAX_GROW_RATE
      push ax
      call rand_in_range
      add sp, 2
      mov [bx+si+THREAD.shrink_rate], al

      mov byte [bx+si+THREAD.head_char], 0

  create_thread_ret:
      pop si
      pop bx
      leave
      ret

; Check whether we can create a new thread in a given column.
; Argument is address of COLUMN struct.
; Returns result as boolean in al.
can_create_thread:
      enter 0, 0
      push bx
      push si
      mov bx, [bp+4]

      ; If all 4 threads are active, there's no space to create another one.
      mov dl, [bx+COLUMN.active_threads]
      cmp dl, 1111b
      jge can_create_thread_ret_false

      mov cx, 0  ; loop counter
      mov ah, 1  ; bitmask
      mov si, COLUMN.threads  ; pointer to thread
  can_create_thread_loop:
      ; If thread isn't active, continue
      mov al, dl
      and al, ah
      cmp al, 0
      je can_create_thread_end_loop

      ; If thread's tail_y < THREAD_GAP, return false
      cmp byte [bx+si+THREAD.tail_y], THREAD_GAP
      jl can_create_thread_ret_false
  can_create_thread_end_loop:
      ; If we're done and no threads had tail_y < THREAD_GAP, return true
      inc cx
      cmp cx, 4
      je can_create_thread_ret_true

      shl ah, 1
      add si, SIZEOF_THREAD
      jmp can_create_thread_loop
  can_create_thread_ret_true:
      mov al, 1
      jmp can_create_thread_ret
  can_create_thread_ret_false:
      mov al, 0
  can_create_thread_ret:
      mov ah, 0
      pop si
      pop bx
      leave 
      ret


; Destroy threads in a particular column as needed.
; Argument is address of COLUMN struct for that column.
destroy_thread:
      enter 0, 0
      push bx
      push si
      mov bx, [bp+4]  ; pointer to COLUMN struct

      mov dl, [bx+COLUMN.active_threads]
      mov cx, 0  ; counter
      mov ah, 1  ; bitmask
      mov si, COLUMN.threads  ; pointer to thread
  destroy_thread_loop:
      mov al, dl
      and al, ah
      cmp al, 0
      je destroy_thread_end_loop

      cmp byte [bx+si+THREAD.tail_y], ROWS
      jl destroy_thread_end_loop

      ; ah = bitmask for the THREAD struct to update
      xor [bx+COLUMN.active_threads], ah

  destroy_thread_end_loop:
      inc cx
      shl ah, 1
      add si, SIZEOF_THREAD
      cmp cx, 4
      jne destroy_thread_loop

  destroy_thread_ret:
      pop si
      pop bx
      leave
      ret


; Grow and shrink a thread for a given frame number.
; Arguments is pointer to THREAD struct
update_thread:
      enter 0, 0
      push bx
      mov bx, [bp+4]

  update_thread_grow:
      ; Check if we should grow
      mov cl, [bx+THREAD.grow_rate]
      call should_update_for_frame
      jne update_thread_shrink

      mov ch, [bx+THREAD.head_y]
      cmp ch, ROWS
      jge update_thread_shrink

      mov cl, [bx+THREAD.x]
      push cx
      mov al, [bx+THREAD.head_char]
      mov ah, COLOR
      push ax
      call print_char_at
      add sp, 2
      pop cx

      inc ch
      mov [bx+THREAD.head_y], ch
      cmp ch, ROWS
      jge update_thread_shrink

      push cx
      call rand_char
      mov [bx+THREAD.head_char], al
      mov ah, HEAD_COLOR
      push ax
      call print_char_at
      add sp, 4

  update_thread_shrink:
      ; Check if we should shrink
      mov cl, [bx+THREAD.shrink_rate]
      call should_update_for_frame
      jne update_thread_ret

      mov ch, [bx+THREAD.tail_y]
      inc ch
      mov [bx+THREAD.tail_y], ch
      cmp ch, ROWS
      jge update_thread_ret
      cmp ch, 0
      jl update_thread_ret
      mov cl, [bx+THREAD.x]
      push cx
      mov al, 20h  ; ' '
      mov ah, COLOR
      push ax
      call print_char_at
      add sp, 4

  update_thread_ret:
      pop bx
      leave
      ret

should_update_for_frame:
      mov dx, 0
      mov ax, [frame_count]
      mov ch, 0
      div cx
      cmp dx, 0
      ret


; Set video mode to 80x25
set_video_mode:
      pusha
      mov al, 03h
      mov ah, 0h
      int 10h
      popa
      ret

; Print character at location.
; Arguments:
;     - Character to print in lower 8 bits, color in upper 8 bits
;     - (x, y) in lower and upper 8 bits
; Example:
;    mov al, <x>
;    mov ah, <y>
;    push ax
;    mov al, <char>
;    mov ah, <color>
;    push ax
;    call print_char_at
;    add sp, 4
print_char_at:
      enter 0, 0
      pusha

      mov dl, [bp+6]
      mov dh, [bp+7]
      mov bx, 0
      mov ah, 02h
      int 10h

      mov al, [bp+4]
      mov bh, 0
      mov bl, [bp+5]
      mov cx, 1
      mov ah, 09h
      int 10h

      popa
      leave
      ret


; Sleep until the next tick.
next_tick:
      pusha
  next_tick_loop:
      mov ah, 0h
      int 1ah
      cmp dx, [last_tick]
      jne next_tick_ret
      cmp cx, [last_tick+2]
      jne next_tick_ret
      hlt
      jmp next_tick_loop
  next_tick_ret:
      mov [last_tick], dx
      mov [last_tick+2], cx
      popa
      ret

; Check for key press (non-blocking).
; Result:
;    - Zero flag if no key pressed
;    - Non-zero flag if key pressed, ASCII value stored in al
check_keyboard:
      pusha
      mov ah, 01h
      int 16h
      jz check_keyboard_ret
      mov ah, 0h
      int 16h
      xor ah, ah
      cmp al, 0
  check_keyboard_ret:
      popa
      ret

; Initializes our Fibonacci PRNG.
rand_init:
      pusha
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
      mov bx, rand_seeds
      mov [bx], cx
      mov [bx+2], dx
      popa
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

; Generates a random character for display.
; Result is stored in al.
rand_char:
      push bx

      mov al, 0
      mov ah, SIZEOF_CHARS
      dec ah
      push ax
      call rand_in_range
      add sp, 2
      mov ah, 0

      mov bx, CHARS
      add bx, ax
      mov al, [bx]

      pop bx
      ret

; Print a 16-bit unsigned integer for debugging.
; print_number:
;       ; 16 bit values have a max of 5 decimal digits (65535). We also reserve
;       ; space for newline and terminating '$'.
;       enter 8, 0
;       ; ax = remainder to print
;       ; bx = char* pointing to start of string on stack
;       ; di = 10
;       push bx
;       push di
;       mov ax, [bp+4]
;       mov bx, bp
;       sub bx, 3
;       mov byte [ss:bx], 0dh  ; '\r'
;       mov byte [ss:bx+1], 0ah  ; '\n'
;       mov byte [ss:bx+2], 24h  ; '$'
;       mov di, 10
;   print_number_1:
;       mov dx, 0
;       div di
;       add dx, 30h  ; '0'
;       dec bx
;       mov [ss:bx], dl
;       cmp ax, 0
;       jne print_number_1
;       push ds
;       mov ax, ss
;       mov ds, ax
;       mov dx, bx
;       mov ah, 09h
;       int 21h
;       pop ds
;       pop di
;       pop bx
;       leave
;       ret

; Exits the program.
exit:
      mov ax, 4c00h
      int 21h

; ==== Data ====
segment _data

; Characters.
CHARS: db 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*<>?:-=+|'
SIZEOF_CHARS = $-CHARS

; Current frame number.
frame_count: dw 0

; Most recent tick count.
last_tick: dd 0

; Fibonacci PRNG seeds
rand_seeds: rb 4

; Threads.
threads_by_column: rb (SIZEOF_COLUMN * COLS)

