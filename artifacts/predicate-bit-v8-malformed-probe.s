# #86 malformed boxed-handle negative witness.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_predicate_bit_bits

wsm_entry:
    movq $31, %rsi                   # boxed handle 3: (3 << 3) | 7, not owned
    call wsm_predicate_bit_bits
    movq $11, %rax                   # unreachable if fail-closed works
    ret
