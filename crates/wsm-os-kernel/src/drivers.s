.section .data
.align 8
.global wsm_mouse_x
.global wsm_mouse_y
.global wsm_mouse_buttons
wsm_mouse_x:        .long 512
wsm_mouse_y:        .long 384
wsm_mouse_buttons:  .long 0
wsm_mouse_phase:    .byte 0
wsm_mouse_buf:      .byte 0, 0, 0

.section .text

# ---------------------------------------------------------------------------
# Helper: wait until 8042 input buffer is empty (status bit 1 == 0)
# Returns: RAX = 1 on success, 0 on timeout
# ---------------------------------------------------------------------------
.global wsm_asm_i8042_wait_in_empty
wsm_asm_i8042_wait_in_empty:
    mov ecx, 100000
1:
    in al, 0x64
    test al, 0x02
    jz 2f
    pause
    dec ecx
    jnz 1b
    xor eax, eax
    ret
2:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# Helper: wait until 8042 output buffer is full (status bit 0 == 1)
# Returns: RAX = 1 on success, 0 on timeout
# ---------------------------------------------------------------------------
.global wsm_asm_i8042_wait_out_full
wsm_asm_i8042_wait_out_full:
    mov ecx, 100000
1:
    in al, 0x64
    test al, 0x01
    jnz 2f
    pause
    dec ecx
    jnz 1b
    xor eax, eax
    ret
2:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# Send a byte to the mouse (via 0xD4 command)
# Input:  DIL = byte to send
# Returns: RAX = 1 if ACK (0xFA), 0 otherwise
# ---------------------------------------------------------------------------
.global wsm_asm_mouse_write
wsm_asm_mouse_write:
    push rbx
    mov bl, dil

    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f

    mov al, 0xD4        # tell 8042 next byte is for aux device (mouse)
    out 0x64, al

    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f

    mov al, bl          # send actual mouse command/data byte
    out 0x60, al

    call wsm_asm_i8042_wait_out_full
    test eax, eax
    jz 9f

    in al, 0x60         # read ACK byte
    cmp al, 0xFA        # 0xFA = MOUSE_ACK
    sete al
    movzx eax, al
    pop rbx
    ret
9:
    xor eax, eax
    pop rbx
    ret

# ---------------------------------------------------------------------------
# Initialize PS/2 mouse on 8042 controller
# Returns: RAX = 1 on success, 0 on failure
# ---------------------------------------------------------------------------
.global wsm_asm_mouse_init
wsm_asm_mouse_init:
    push rbx

    # 1. Drain output buffer
1:
    in al, 0x64
    test al, 0x01
    jz 2f
    in al, 0x60
    jmp 1b
2:
    # 2. Enable auxiliary port (command 0xA8)
    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f
    mov al, 0xA8
    out 0x64, al

    # 3. Read Controller Configuration Byte (command 0x20)
    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f
    mov al, 0x20
    out 0x64, al

    call wsm_asm_i8042_wait_out_full
    test eax, eax
    jz 9f
    in al, 0x60
    mov bl, al          # save config byte

    # 4. Modify and write back config byte (command 0x60)
    # Clear bit 5 (enable mouse clock), set bit 1 (enable mouse interrupt)
    and bl, 0xDF        # ~0x20
    or bl, 0x02

    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f
    mov al, 0x60
    out 0x64, al

    call wsm_asm_i8042_wait_in_empty
    test eax, eax
    jz 9f
    mov al, bl
    out 0x60, al

    # 5. Set defaults (0xF6)
    mov dil, 0xF6
    call wsm_asm_mouse_write
    test eax, eax
    jz 9f

    # 6. Enable data reporting (0xF4)
    mov dil, 0xF4
    call wsm_asm_mouse_write
    test eax, eax
    jz 9f

    mov eax, 1
    pop rbx
    ret
9:
    xor eax, eax
    pop rbx
    ret

# ---------------------------------------------------------------------------
# Poll PS/2 8042 controller for raw events
# Returns:
#   EAX = -1 (no data available)
#   EAX = 0x0000 | byte (keyboard byte)
#   EAX = 0x0100 | byte (mouse byte)
# ---------------------------------------------------------------------------
.global wsm_asm_ps2_poll
wsm_asm_ps2_poll:
    in al, 0x64
    test al, 0x01       # OUTPUT_FULL?
    jz 1f
    test al, 0x20       # MOUSE_DATA?
    jnz 2f
    # Keyboard data
    in al, 0x60
    movzx eax, al
    ret
2:  # Mouse data
    in al, 0x60
    movzx eax, al
    or eax, 0x0100      # tag bit 8 = mouse
    ret
1:
    mov eax, -1
    ret

# ---------------------------------------------------------------------------
# Process raw mouse byte into coordinates and button state
# Inputs:
#   DIL = raw byte
#   ESI = max_x
#   EDX = max_y
# Returns:
#   EAX = 1 if complete 3-byte packet decoded, 0 if in-progress / dropped
# ---------------------------------------------------------------------------
.global wsm_asm_mouse_update
wsm_asm_mouse_update:
    lea r8, [rip + wsm_mouse_phase]
    lea r9, [rip + wsm_mouse_buf]
    movzx ecx, byte ptr [r8]

    cmp ecx, 0
    je .Lphase0
    cmp ecx, 1
    je .Lphase1
    cmp ecx, 2
    je .Lphase2
    # Invalid phase, reset
    mov byte ptr [r8], 0
    xor eax, eax
    ret

.Lphase0:
    # Sanity bit: bit 3 must be 1 in PS/2 mouse byte 0
    test dil, 0x08
    jz .Ldrop
    mov byte ptr [r9], dil
    mov byte ptr [r8], 1
    xor eax, eax
    ret

.Lphase1:
    mov byte ptr [r9 + 1], dil
    mov byte ptr [r8], 2
    xor eax, eax
    ret

.Lphase2:
    mov byte ptr [r9 + 2], dil
    mov byte ptr [r8], 0       # reset phase for next packet

    # Load 3 bytes
    movzx eax, byte ptr [r9]       # flags
    movzx ecx, byte ptr [r9 + 1]   # raw dx
    movzx r10d, byte ptr [r9 + 2]  # raw dy

    # Sign extend dx (if bit 4 of flags set)
    test al, 0x10
    jz 3f
    movsx ecx, cl
3:

    # Sign extend dy (if bit 5 of flags set)
    test al, 0x20
    jz 4f
    movsx r10d, r10b
4:

    # Extract buttons: bit 0 = Left, bit 1 = Right, bit 2 = Middle
    mov r11d, eax
    and r11d, 0x07
    lea rax, [rip + wsm_mouse_buttons]
    mov dword ptr [rax], r11d

    # Update X: x = clamp(x + dx, 0, max_x)
    lea rax, [rip + wsm_mouse_x]
    mov r11d, dword ptr [rax]
    add r11d, ecx
    test r11d, r11d
    jns 5f
    xor r11d, r11d
5:
    cmp r11d, esi
    jle 6f
    mov r11d, esi
6:
    mov dword ptr [rax], r11d

    # Update Y: y = clamp(y - dy, 0, max_y) (dy positive is UP in PS/2)
    lea rax, [rip + wsm_mouse_y]
    mov r11d, dword ptr [rax]
    sub r11d, r10d
    test r11d, r11d
    jns 7f
    xor r11d, r11d
7:
    cmp r11d, edx
    jle 8f
    mov r11d, edx
8:
    mov dword ptr [rax], r11d

    mov eax, 1
    ret

.Ldrop:
    mov byte ptr [r8], 0
    xor eax, eax
    ret

# ---------------------------------------------------------------------------
# Draw / Erase XOR cursor on framebuffer
# C signature:
# void wsm_asm_draw_xor_cursor(
#   uint8_t* fb_ptr,        // RDI
#   uint64_t width,         // RSI
#   uint64_t height,        // RDX
#   uint64_t stride,        // RCX
#   uint64_t bpp,           // R8
#   uint64_t cx,            // R9
#   uint64_t cy             // [RSP + 16] (stack)
# );
# ---------------------------------------------------------------------------
.global wsm_asm_draw_xor_cursor
wsm_asm_draw_xor_cursor:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r10, qword ptr [rbp + 16]   # cy

    # Arrow bitmap: 8 rows of 8 bits
    # 0b10000000, 0b11000000, 0b11100000, 0b11110000,
    # 0b11111000, 0b11100000, 0b10110000, 0b00011000
    mov r11, 0x18B0E0F8F0E0C080

    xor ebx, ebx            # row = 0
.Lcursor_row_loop:
    cmp ebx, 8
    jge .Lcursor_done

    mov r12, r10
    add r12, rbx            # py = cy + row
    cmp r12, rdx            # py >= height?
    jae .Lnext_row

    # Extract row byte from r11
    mov cl, bl
    shl cl, 3               # cl = row * 8
    mov rax, r11
    shr rax, cl
    movzx r13d, al          # r13d = row mask

    xor r14d, r14d          # col = 0
.Lcursor_col_loop:
    cmp r14d, 8
    jge .Lnext_row

    # Check bit (0x80 >> col)
    mov cl, 7
    sub cl, r14b
    bt r13d, ecx
    jnc .Lnext_col

    mov r15, r9
    add r15, r14            # px = cx + col
    cmp r15, rsi            # px >= width?
    jae .Lnext_col

    # Base address: fb_ptr + (py * stride + px) * bpp
    mov rax, r12
    imul rax, rcx           # py * stride
    add rax, r15            # + px
    imul rax, r8            # * bpp
    lea rax, [rdi + rax]    # target pixel

    # Invert B, G, R (XOR 0xFF)
    xor byte ptr [rax], 0xFF
    xor byte ptr [rax + 1], 0xFF
    xor byte ptr [rax + 2], 0xFF

.Lnext_col:
    inc r14d
    jmp .Lcursor_col_loop

.Lnext_row:
    inc ebx
    jmp .Lcursor_row_loop

.Lcursor_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# ---------------------------------------------------------------------------
# PCI configuration space I/O in assembly
# uint32_t wsm_asm_pci_read32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset);
# Arguments: EDI = bus, ESI = dev, EDX = func, ECX = offset
# ---------------------------------------------------------------------------
.global wsm_asm_pci_read32
wsm_asm_pci_read32:
    mov eax, 1
    shl eax, 31             # Enable bit
    and edi, 0xFF
    shl edi, 16
    or eax, edi             # bus
    and esi, 0x1F
    shl esi, 11
    or eax, esi             # dev
    and edx, 0x07
    shl edx, 8
    or eax, edx             # func
    and ecx, 0xFC
    or eax, ecx             # offset & 0xFC

    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    ret

# ---------------------------------------------------------------------------
# uint64_t wsm_asm_rdtsc(void);
# ---------------------------------------------------------------------------
.global wsm_asm_rdtsc
wsm_asm_rdtsc:
    rdtsc
    shl rdx, 32
    or rax, rdx
    ret
