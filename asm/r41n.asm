; ==== Constants ====
COLS equ 80
ROWS equ 25
THREAD_GAP equ 8
NEW_THREAD_RATE equ 100
MIN_THREAD_LENGTH equ 4
MAX_THREAD_LENGTH equ 16
MAX_GROW_RATE equ 4
MIN_GROW_RATE equ 1

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
      call set_video_mode

      mov cx, 0  ; Frame number
  start_1:
      push cx
      call next_frame
      pop cx
      inc cx

      push 1
      call sleep_ticks
      add sp, 2

      call check_keyboard
      jz start_1

  start_ret:
      call set_video_mode  ; Clear screen
      call exit

; Render next frame.
; Argument is frame number.
next_frame:
      enter 0, 0
      pusha

      call create_threads

      mov cx, 0  ; column loop counter
      mov bx, threads_by_column
  next_frame_column_loop:
      mov dx, 0  ; thread loop counter
      mov ah, 1  ; thread bitmask
      mov si, COLUMN.threads
    next_frame_thread_loop:
      mov al, [bx+COLUMN.active_threads]
      and al, ah
      cmp al, 0
      je next_frame_thread_end_loop

      pusha
      push word [bp+4]
      add bx, si
      push bx
      call update_thread
      add sp, 4
      popa
    next_frame_thread_end_loop:
      shl ah, 1
      add si, SIZEOF_THREAD
      inc dx
      cmp dx, 4
      jne next_frame_thread_loop

  next_frame_column_end_loop:
      inc cx
      add bx, SIZEOF_COLUMN
      cmp cx, COLS
      jne next_frame_column_loop

      call destroy_threads

  next_frame_ret:
      popa
      leave
      ret


; Create new threads in each column as needed.
create_threads:
      enter 0, 0
      push bx

      mov cx, 0  ; loop counter
      mov bx, threads_by_column
  create_threads_loop:
      push cx
      push bx
      call create_thread
      add sp, 2
      pop cx
      inc cx
      add bx, SIZEOF_COLUMN
      cmp cx, COLS
      jne create_threads_loop

      pop bx
      leave
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
      mov byte [bx+si+THREAD.tail_y], al

      mov al, MIN_GROW_RATE
      mov ah, MAX_GROW_RATE
      push ax
      call rand_in_range
      add sp, 2
      mov byte [bx+si+THREAD.grow_rate], al

      ; al (min) is grow_rate
      mov ah, MAX_GROW_RATE
      push ax
      call rand_in_range
      add sp, 2
      mov byte [bx+si+THREAD.shrink_rate], al

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


; Destroy off screen threads in each column as needed.
destroy_threads:
      enter 0, 0
      push bx

      mov cx, 0  ; loop counter
      mov bx, threads_by_column
  destroy_threads_loop:
      push cx
      push bx
      call destroy_thread
      add sp, 2
      pop cx
      inc cx
      add bx, SIZEOF_COLUMN
      cmp cx, COLS
      jne destroy_threads_loop

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
; Arguments:
;     - Frame number
;     - Pointer to THREAD struct
update_thread:
      enter 0, 0
      pusha
      mov bx, [bp+4]

  update_thread_grow:
      ; Check if we should grow
      mov dx, 0
      mov ax, [bp+6]
      mov ch, 0
      mov cl, [bx+THREAD.grow_rate]
      div cx
      cmp dx, 0
      jne update_thread_shrink

      mov ch, [bx+THREAD.head_y]
      cmp ch, ROWS-1
      jge update_thread_shrink

      inc ch
      mov [bx+THREAD.head_y], ch
      mov cl, [bx+THREAD.x]
      push cx
      call move_cursor
      add sp, 2

      call rand_char
      mov [bx+THREAD.head_char], al
      push ax
      call print_char
      add sp, 2

  update_thread_shrink:
      ; Check if we should shrink
      mov dx, 0
      mov ax, [bp+6]
      mov ch, 0
      mov cl, [bx+THREAD.shrink_rate]
      div cx
      cmp dx, 0
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
      call move_cursor
      add sp, 2
      mov ax, 20h  ; ' '
      push ax
      call print_char
      add sp, 2

  update_thread_ret:
      popa
      leave
      ret

; Set video mode to 80x25
set_video_mode:
      pusha
      mov al, 03h
      mov ah, 0h
      int 10h
      popa
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
      pusha
      mov dl, [bp+4]
      mov dh, [bp+5]
      mov bx, 0
      mov ah, 02h
      int 10h
      popa
      leave
      ret

; Sleep a given number of CPU ticks (~55ms).
; Example:
;    push 10
;    call sleep_ticks
;    add sp, 2
sleep_ticks:
      enter 0, 0
      pusha
      ; bx = remaining ticks to wait
      ; si = higher 16 bits of current tick count
      ; di = lower 16 bits of current tick count
      mov bx, [bp+4]
  sleep_ticks_1:
      cmp bx, 0
      je sleep_ticks_ret
      push bx
      mov ah, 0h
      int 1ah
      pop bx
      mov di, dx
      mov si, cx
  sleep_ticks_2:
      push bx
      push si
      push di
      hlt
      mov ah, 0h
      int 1ah
      pop di
      pop si
      pop bx
      cmp dx, di
      jne sleep_ticks_3
      cmp cx, si
      jne sleep_ticks_3
      jmp sleep_ticks_2
  sleep_ticks_3:
      dec bx
      jmp sleep_ticks_1
  sleep_ticks_ret:
      popa
      leave
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

; Print a single character
; Argument is character to print in lower 8 bits.
print_char:
      enter 0, 0
      pusha
      mov ax, [bp+4]
      mov bx, 0
      mov cx, 1
      mov ah, 0ah
      int 10h
      popa
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

; Characters.
CHARS: db 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*<>?:-=+|'
SIZEOF_CHARS = $-CHARS

