# ===========================================================================
# wsm-os-lisp: Pure Freestanding Machine Entry (Zero Rust, ADR-004)
# ===========================================================================

.section .rodata
msg_boot:
    .ascii "WSM-OS BOOT schema=1 arch=x86_64 status=ok\n"
msg_boot_end:
.set msg_boot_len, msg_boot_end - msg_boot

# Structured condition line, matching the pre-ADR-004 substrate format:
#   WSM-OS CONDITION schema=1 kind=<NAME> source=<code> value=<word>
msg_cond_pre:
    .ascii "WSM-OS CONDITION schema=1 kind="
msg_cond_pre_end:
.set msg_cond_pre_len, msg_cond_pre_end - msg_cond_pre

msg_cond_source:
    .ascii " source="
msg_cond_source_end:
.set msg_cond_source_len, msg_cond_source_end - msg_cond_source

msg_cond_value:
    .ascii " value="
msg_cond_value_end:
.set msg_cond_value_len, msg_cond_value_end - msg_cond_value

msg_newline:
    .ascii "\n"
msg_newline_end:
.set msg_newline_len, msg_newline_end - msg_newline

msg_kind_oom:
    .ascii "OOM"
msg_kind_oom_end:
.set msg_kind_oom_len, msg_kind_oom_end - msg_kind_oom

msg_kind_type:
    .ascii "TYPE"
msg_kind_type_end:
.set msg_kind_type_len, msg_kind_type_end - msg_kind_type

msg_kind_symbol:
    .ascii "SYMBOL"
msg_kind_symbol_end:
.set msg_kind_symbol_len, msg_kind_symbol_end - msg_kind_symbol

msg_kind_abi:
    .ascii "ABI"
msg_kind_abi_end:
.set msg_kind_abi_len, msg_kind_abi_end - msg_kind_abi

msg_kind_overflow:
    .ascii "OVERFLOW"
msg_kind_overflow_end:
.set msg_kind_overflow_len, msg_kind_overflow_end - msg_kind_overflow

msg_kind_unknown:
    .ascii "UNKNOWN"
msg_kind_unknown_end:
.set msg_kind_unknown_len, msg_kind_unknown_end - msg_kind_unknown

.section .bss
.align 16
stack_bottom:
    .skip 65536                     # 64 KB kernel stack
stack_top:

.align 16
heap_arena:
    .skip 65536                     # 64 KB cons heap
heap_arena_end:

.align 16
closure_arena:
    .skip 16384                     # 16 KB closure arena
closure_arena_end:

.align 16
boxed_arena:
    .skip 24576                     # 1024 * 24-byte runtime-private boxed entries
boxed_arena_end:

.section .data
.align 16
# Boot handoff state: raw pointer captured from RDI on entry. The actual
# physical-memory offset is parsed into a plain u64 (see wsm_boot_handoff).
.globl saved_boot_info
saved_boot_info:
    .quad 0

.align 16
runtime_context:
    .quad heap_arena                # offset 0: heap_base
    .quad 4096                      # offset 8: heap_capacity (4096 * 16 bytes = 64KB)
    .quad 0                         # offset 16: heap_len
    .quad closure_arena             # offset 24: closure_base
    .quad 1024                      # offset 32: closure_capacity
    .quad 0                         # offset 40: closure_len
    .long 0                         # offset 48: condition_kind
    .long 0                         # offset 52: condition_source
    .quad 0                         # offset 56: condition_value
    .quad kernel_failure            # offset 64: failure_handler
    .quad boxed_arena               # offset 72: boxed_base
    .quad 1024                      # offset 80: boxed_capacity
    .quad 0                         # offset 88: boxed_len

.section .rodata
msg_res_pre:
    .ascii "WSM-OS RESULT schema=1 value="
.set msg_res_pre_len, . - msg_res_pre

msg_res_post:
    .ascii " status=ok\n"
.set msg_res_post_len, . - msg_res_post

msg_nil:
    .ascii "nil"
.set msg_nil_len, . - msg_nil

msg_t:
    .ascii "t"
.set msg_t_len, . - msg_t

msg_sym_prefix:
    .ascii "sym"
.set msg_sym_prefix_len, . - msg_sym_prefix

msg_open_paren:
    .ascii "("
.set msg_open_paren_len, . - msg_open_paren

msg_dot:
    .ascii " . "
.set msg_dot_len, . - msg_dot

msg_close_paren:
    .ascii ")"
.set msg_close_paren_len, . - msg_close_paren

.section .text
.globl _start
.type _start, @function
_start:
    # Disable interrupts
    cli

    # Save BootInfo pointer. Per the pinned bootloader 0.11.17 the entry
    # handoff places &BootInfo in RDI before jumping here (see
    # docs/TARGET-BOOT-HANDOFF-ABI.md, section 1). We only capture the
    # pointer now; semantic extraction happens in wsm_boot_handoff.
    # If the pointer is null we still proceed fail-closed (MMIO will not
    # provision without a physical-memory mapping).
    movq %rdi, saved_boot_info(%rip)

    # Setup stack
    leaq stack_top(%rip), %rsp

    # Initialize COM1 serial port
    call serial_init

    # Print boot message
    leaq msg_boot(%rip), %rsi
    movl $msg_boot_len, %edx
    call serial_write

    # Parse BootInfo handed off in RDI: extract physical_memory_offset into
    # target memory state. Missing/None stays fail-closed (offset stays 0 and
    # no MMIO region will be provisioned).
    call wsm_boot_handoff

    # Call Lisp entry: wsm_entry(&runtime_context)
    leaq runtime_context(%rip), %rdi
    call wsm_entry

    # Result is in RAX. Print canonical prefix: "WSM-OS RESULT schema=1 value="
    pushq %rax
    leaq msg_res_pre(%rip), %rsi
    movl $msg_res_pre_len, %edx
    call serial_write

    popq %rax
    movq %rax, %rdi
    call print_value

    # Print suffix: " status=ok\n"
    leaq msg_res_post(%rip), %rsi
    movl $msg_res_post_len, %edx
    call serial_write

    # QEMU clean exit: port 0xF4 with code 0x10 -> exit code 33
    movw $0xF4, %dx
    movl $0x10, %eax
    outl %eax, %dx

.Lhalt:
    hlt
    jmp .Lhalt

# ---------------------------------------------------------------------------
# print_value: prints canonical WSM representation of Word in RDI
# ---------------------------------------------------------------------------
print_value:
    pushq %rbx
    pushq %r12
    movq %rdi, %rbx

    # Check NIL (1)
    cmpq $1, %rbx
    je .Lp_nil

    # Check Canonical T
    movabsq $0xFFFFFFFFFFFFFFFC, %rax
    cmpq %rax, %rbx
    je .Lp_t

    # Check tag (low 3 bits)
    movq %rbx, %rax
    andq $7, %rax

    cmpq $0, %rax                   # Cons
    je .Lp_cons
    cmpq $3, %rax                   # Fixnum
    je .Lp_fixnum
    cmpq $4, %rax                   # Symbol
    je .Lp_symbol

    # Default fallback
    movl $'?', %eax
    call serial_putc
    jmp .Lp_done

.Lp_nil:
    leaq msg_nil(%rip), %rsi
    movl $msg_nil_len, %edx
    call serial_write
    jmp .Lp_done

.Lp_t:
    leaq msg_t(%rip), %rsi
    movl $msg_t_len, %edx
    call serial_write
    jmp .Lp_done

.Lp_cons:
    leaq msg_open_paren(%rip), %rsi
    movl $msg_open_paren_len, %edx
    call serial_write

    movq 0(%rbx), %rdi              # car
    call print_value

    leaq msg_dot(%rip), %rsi
    movl $msg_dot_len, %edx
    call serial_write

    movq 8(%rbx), %rdi              # cdr
    call print_value

    leaq msg_close_paren(%rip), %rsi
    movl $msg_close_paren_len, %edx
    call serial_write
    jmp .Lp_done

.Lp_symbol:
    # Symbols are interned ids; the target observes only the id, never the
    # compiler-owned name. Serialize the observable representation alone.
    leaq msg_sym_prefix(%rip), %rsi
    movl $msg_sym_prefix_len, %edx
    call serial_write
    movq %rbx, %rax
    shrq $3, %rax
    movq %rax, %rdi
    call print_decimal
    jmp .Lp_done

.Lp_fixnum:
    movq %rbx, %rax
    sarq $3, %rax                   # arithmetic shift for sign
    testq %rax, %rax
    jns 1f
    pushq %rax
    movl $'-', %eax
    call serial_putc
    popq %rax
    negq %rax
1:
    movq %rax, %rdi
    call print_decimal
    jmp .Lp_done

.Lp_done:
    popq %r12
    popq %rbx
    ret

# Print unsigned 64-bit decimal in RDI
print_decimal:
    pushq %rbp
    movq %rsp, %rbp
    subq $32, %rsp

    movq %rdi, %rax
    leaq -1(%rbp), %rcx
    movb $0, (%rcx)                 # null terminator

    movq $10, %r8
.Ldec_loop:
    xorq %rdx, %rdx
    divq %r8
    addb $'0', %dl
    decq %rcx
    movb %dl, (%rcx)
    testq %rax, %rax
    jnz .Ldec_loop

    # rcx points to start of string
    movq %rcx, %rsi
    leaq -1(%rbp), %rdx
    subq %rcx, %rdx                 # length
    call serial_write

    leave
    ret

# ---------------------------------------------------------------------------
# Serial port routines (COM1 = 0x3F8)
# ---------------------------------------------------------------------------
serial_init:
    movw $0x3F9, %dx                # IER = 0 (disable interrupts)
    xorl %eax, %eax
    outb %al, %dx

    movw $0x3FB, %dx                # LCR: enable DLAB (0x80)
    movb $0x80, %al
    outb %al, %dx

    movw $0x3F8, %dx                # DLL = 1 (115200 baud)
    movb $0x01, %al
    outb %al, %dx

    movw $0x3F9, %dx                # DLM = 0
    xorl %eax, %eax
    outb %al, %dx

    movw $0x3FB, %dx                # LCR = 0x03 (8 bits, no parity, 1 stop bit)
    movb $0x03, %al
    outb %al, %dx

    movw $0x3FA, %dx                # FCR = 0xC7 (enable FIFO, clear TX/RX, 14-byte threshold)
    movb $0xC7, %al
    outb %al, %dx

    movw $0x3FC, %dx                # MCR = 0x0B (DTR + RTS + OUT2)
    movb $0x0B, %al
    outb %al, %dx
    ret

serial_putc:
    movl %eax, %r8d
    movw $0x3FD, %dx                # LSR
    movl $100000, %ecx              # finite retry bound (~100k polls)
1:
    inb %dx, %al
    testb $0x20, %al                # THRE (transmitter holding register empty)
    jnz 2f
    loop 1b                         # dec %ecx; jnz if not zero

    # Transport failure: UART never became ready.
    # Distinct from kernel_failure/panic/result schema.
    # Exit via ISA debug port 0xF4 with code 0x13 (19) = serial transport failure.
    movw $0xF4, %dx
    movl $0x13, %eax
    outl %eax, %dx
    hlt

2:
    movw $0x3F8, %dx
    movl %r8d, %eax
    outb %al, %dx
    ret

# RSI = buffer, EDX = length
serial_write:
    pushq %rbx
    pushq %r12
    movq %rsi, %rbx
    movl %edx, %r12d
.Lwrite_loop:
    testl %r12d, %r12d
    jz .Lwrite_done
    movzbl (%rbx), %eax
    call serial_putc
    incq %rbx
    decl %r12d
    jmp .Lwrite_loop
.Lwrite_done:
    popq %r12
    popq %rbx
    ret

kernel_failure:
    # RDI still holds the RuntimeContext (wsm_fail calls the handler without
    # modifying it). Emit the structured condition, then exit 0x12 -> shell 37.
    pushq %rbx
    movq %rdi, %rbx

    leaq msg_cond_pre(%rip), %rsi
    movl $msg_cond_pre_len, %edx
    call serial_write

    movl 48(%rbx), %edi             # condition.kind
    call print_condition_kind

    leaq msg_cond_source(%rip), %rsi
    movl $msg_cond_source_len, %edx
    call serial_write
    movl 52(%rbx), %edi             # condition.source_id
    call print_decimal

    leaq msg_cond_value(%rip), %rsi
    movl $msg_cond_value_len, %edx
    call serial_write
    movq 56(%rbx), %rdi             # condition.offending_value
    call print_decimal

    leaq msg_newline(%rip), %rsi
    movl $msg_newline_len, %edx
    call serial_write

    movw $0xF4, %dx
    movl $0x12, %eax
    outl %eax, %dx
    hlt

# print_condition_kind: serializes the closed condition-kind name in EDI.
print_condition_kind:
    cmpl $1, %edi
    je .Lck_oom
    cmpl $2, %edi
    je .Lck_type
    cmpl $3, %edi
    je .Lck_symbol
    cmpl $4, %edi
    je .Lck_abi
    cmpl $5, %edi
    je .Lck_overflow
    leaq msg_kind_unknown(%rip), %rsi
    movl $msg_kind_unknown_len, %edx
    jmp serial_write
.Lck_oom:
    leaq msg_kind_oom(%rip), %rsi
    movl $msg_kind_oom_len, %edx
    jmp serial_write
.Lck_type:
    leaq msg_kind_type(%rip), %rsi
    movl $msg_kind_type_len, %edx
    jmp serial_write
.Lck_symbol:
    leaq msg_kind_symbol(%rip), %rsi
    movl $msg_kind_symbol_len, %edx
    jmp serial_write
.Lck_abi:
    leaq msg_kind_abi(%rip), %rsi
    movl $msg_kind_abi_len, %edx
    jmp serial_write
.Lck_overflow:
    leaq msg_kind_overflow(%rip), %rsi
    movl $msg_kind_overflow_len, %edx
    jmp serial_write

.section .bootloader-config,"a",@progbits
.incbin "src/bootloader-config.bin"

.section .note.GNU-stack,"",@progbits
