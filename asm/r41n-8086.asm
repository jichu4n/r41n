; ========================================
; Digital rain demo
; 16-bit FASM version for MS-DOS on 8086
; ========================================

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

; ==== Macros ====
macro _pusha {
  push ax
  push cx
  push dx
  push bx
  push bp
  push si
  push di
}

macro _popa {
  pop di
  pop si
  pop bp
  pop bx
  pop dx
  pop cx
  pop ax
}

macro _loop l {
  dec cx
  jnz l
}

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
      mov ax, create_thread
      call for_each_column
      mov ax, next_frame_for_column
      call for_each_column
      mov ax, destroy_threads_in_column
      call for_each_column
      ret

; Arguments:
;    - bx: Address of COLUMN struct for that column.
;    - cx: X position of column.
next_frame_for_column:
      mov ax, update_thread
      call for_each_thread
      ret


; Iterates over the the columns in threads_by_column.
; Argument in ax is a function to be invoked with
;    - bx: Address of COLUMN struct
;    - cx: x position of column
for_each_column:
      mov cx, (COLS-1)  ; loop counter
      mov bx, threads_by_column
  for_each_column_loop:
      _pusha
      call ax
      _popa
      add bx, SIZEOF_COLUMN
      _loop for_each_column_loop
      ret


; Iterates over the active threads in a column.
; Arguments:
;     - ax: Function to be invoked with
;         - si: Address of THREAD struct
;         - bx: Address of COLUMN struct
;         - ax: active_threads bitmask corresponding to this thread
;     - bx: Address of COLUMN struct
for_each_thread:
      mov di, ax  ; Function to call
      mov cx, 4  ; loop counter
      mov ax, 1  ; bitmask
      lea si, [bx+COLUMN.threads]  ; pointer to thread
  for_each_thread_loop:
      ; If thread isn't active, continue
      mov dl, [bx+COLUMN.active_threads]
      and dl, al
      jz for_each_thread_end_loop

      _pusha
      call di
      _popa
  for_each_thread_end_loop:
      shl al, 1
      add si, SIZEOF_THREAD
      _loop for_each_thread_loop
      ret


threads_init:
      push bx
      mov cx, (SIZEOF_COLUMN * COLS / 2)
      mov bx, threads_by_column
  threads_init_loop:
      mov word [bx], 0
      add bx, 2
      _loop threads_init_loop
      pop bx
      ret


; Create threads in a particular column as needed.
; Arguments:
;    - bx: Address of COLUMN struct for that column.
;    - cx: X position of column.
create_thread:
      _pusha
      mov di, cx

      ; Check if this column is eligible
      call can_create_thread
      cmp al, 0
      je create_thread_ret
      ; Randomize
      mov al, 1
      mov ah, NEW_THREAD_RATE
      call rand_in_range
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
      mov cx, di
      mov [bx+si+THREAD.x], cl

      mov byte [bx+si+THREAD.head_y], -1

      mov al, MIN_THREAD_LENGTH
      mov ah, MAX_THREAD_LENGTH
      call rand_in_range
      neg al
      mov [bx+si+THREAD.tail_y], al

      mov al, MIN_GROW_RATE
      mov ah, MAX_GROW_RATE
      call rand_in_range
      mov [bx+si+THREAD.grow_rate], al

      ; al (min) is grow_rate
      mov ah, MAX_GROW_RATE
      call rand_in_range
      mov [bx+si+THREAD.shrink_rate], al

      mov byte [bx+si+THREAD.head_char], 0

  create_thread_ret:
      _popa
      ret

; Check whether we can create a new thread in a given column.
; Assumes bx is address of COLUMN struct.
; Returns result as boolean in al.
can_create_thread:
      push si

      ; If all 4 threads are active, there's no space to create another one.
      mov dl, [bx+COLUMN.active_threads]
      cmp dl, 1111b
      jge can_create_thread_ret_false

      mov cx, 4  ; loop counter
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
      shl ah, 1
      add si, SIZEOF_THREAD
      _loop can_create_thread_loop
      ; If we're done and no threads had tail_y < THREAD_GAP, return true
      mov ax, 1
      jmp can_create_thread_ret
  can_create_thread_ret_false:
      mov ax, 0
  can_create_thread_ret:
      pop si
      ret


; Destroy threads in a particular column as needed.
; Arguments:
;    - bx: Address of COLUMN struct for that column.
;    - cx: X position of column.
destroy_threads_in_column:
      mov ax, destroy_thread_in_column
      call for_each_thread
      ret

; Arguments:
;    - si: Address of THREAD struct
;    - bx: Address of COLUMN struct
;    - ax: active_threads bitmask corresponding to this thread
destroy_thread_in_column:
      cmp byte [si+THREAD.tail_y], ROWS
      jl destroy_thread_in_column_ret
      xor [bx+COLUMN.active_threads], al
  destroy_thread_in_column_ret:
      ret


; Grow and shrink a thread for a given frame number.
; Arguments:
;    - si: Address of THREAD struct
;    - bx: Address of COLUMN struct
;    - ax: active_threads bitmask corresponding to this thread
update_thread:

  update_thread_grow:
      ; Check if we should grow
      mov cl, [si+THREAD.grow_rate]
      call should_update_for_frame
      jne update_thread_shrink

      mov dh, [si+THREAD.head_y]
      cmp dh, ROWS
      jge update_thread_shrink

      mov dl, [si+THREAD.x]
      mov al, [si+THREAD.head_char]
      mov ah, COLOR
      call print_char_at

      inc dh
      mov [si+THREAD.head_y], dh
      cmp dh, ROWS
      jge update_thread_shrink

      push dx
      call rand_char
      pop dx
      mov [si+THREAD.head_char], al
      mov ah, HEAD_COLOR
      call print_char_at

  update_thread_shrink:
      ; Check if we should shrink
      mov cl, [si+THREAD.shrink_rate]
      call should_update_for_frame
      jne update_thread_ret

      mov dh, [si+THREAD.tail_y]
      inc dh
      mov [si+THREAD.tail_y], dh
      cmp dh, ROWS
      jge update_thread_ret
      cmp dh, 0
      jl update_thread_ret
      mov dl, [si+THREAD.x]
      mov al, 20h  ; ' '
      mov ah, COLOR
      call print_char_at

  update_thread_ret:
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
      _pusha
      mov al, 03h
      mov ah, 0h
      int 10h
      _popa
      ret

; Print character at location.
; Arguments:
;     - al: Character to print
;     - ah: Color
;     - dl: x
;     - dh: y
; Example:
print_char_at:
      _pusha
      mov bx, 0
      mov ah, 02h
      int 10h
      _popa

      _pusha
      mov bh, 0
      mov bl, ah
      mov cx, 1
      mov ah, 09h
      int 10h
      _popa

      ret


; Sleep until the next tick.
next_tick:
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
      mov bx, rand_seeds
      mov [bx], cx
      mov [bx+2], dx
      ret

; Fibonacci PRNG.
; Returns a pseudo-random 8-bit integer in al.
rand:
      push bx
      mov bx, rand_seeds
      mov cx, 4
      mov al, [bx]
  rand_loop:
      mov ah, [bx+1]
      add al, ah
      mov [bx], ah
      inc bx
      _loop rand_loop
      mov [bx-1], al
      mov ah, 0
      pop bx
      ret

; Generates a pseudo-random 8-bit integer between [min, max] inclusive. 
; Example:
;    mov al, <min>
;    mov ah, <max>
;    call rand_in_range
; Result is stored in al.
rand_in_range:
      push bx
      mov bx, ax
      call rand
      mov cl, bh
      sub cl, bl
      inc cl
      mov ch, 0
      mov dx, 0
      div cx
      mov al, dl
      add al, bl
      mov ah, 0
      pop bx
      ret

; Generates a random character for display.
; Result is stored in al.
rand_char:
      push bx

      mov al, 0
      mov ah, (SIZEOF_CHARS - 1)
      call rand_in_range

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

