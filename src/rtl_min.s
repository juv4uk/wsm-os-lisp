# ===========================================================================
# src/rtl_min.s — the entire RTL surface this target admits
#
# FPC emits five references for any program, and nothing else, when the program
# is compiled with -Cn (no link stage) and linked by us:
#
#   fpc_initializeunits            unit initialisation entry
#   fpc_do_exit                    program exit path
#   INIT$_$SYSTEM                  system unit initialiser
#   FINALIZE$_$OBJPAS              objpas finaliser
#   THREADVARLIST_$SYSTEM$indirect threadvar table
#
# Here they are no-ops with a fixed shape. That is the honest definition of
# "minimal RTL" for this slice: the hooks exist so the object links, and they
# do nothing. No strings, no I/O, no exceptions, no heap, no unit state.
#
# Any program that needs one of those services must add the mechanism to this
# file explicitly, with a witness — the point of the file is that the surface
# is countable (five symbols, not "the RTL").
#
# See docs/FPC-KERNEL-SKELETON.md and ADR-006.
# ===========================================================================
.text

# void fpc_initializeunits(void)
.globl fpc_initializeunits
.type fpc_initializeunits, @function
fpc_initializeunits:
    ret
.size fpc_initializeunits, .-fpc_initializeunits

# void fpc_do_exit(int32 code) — the probe never returns here, and returning
# keeps the boundary explicit instead of silently halting.
.globl fpc_do_exit
.type fpc_do_exit, @function
fpc_do_exit:
    ret
.size fpc_do_exit, .-fpc_do_exit

# procedure INIT$SYSTEM
.globl INIT$_$SYSTEM
.type INIT$_$SYSTEM, @function
INIT$_$SYSTEM:
    ret
.size INIT$_$SYSTEM, .-INIT$_$SYSTEM

# procedure FINALIZE$OBJPAS
.globl FINALIZE$_$OBJPAS
.type FINALIZE$_$OBJPAS, @function
FINALIZE$_$OBJPAS:
    ret
.size FINALIZE$_$OBJPAS, .-FINALIZE$_$OBJPAS

# threadvar table: a single null terminator, i.e. no thread variables.
.section .rodata
.align 8
.globl THREADVARLIST_$SYSTEM$indirect
.type THREADVARLIST_$SYSTEM$indirect, @object
THREADVARLIST_$SYSTEM$indirect:
    .quad 0
.size THREADVARLIST_$SYSTEM$indirect, .-THREADVARLIST_$SYSTEM$indirect

.section .note.GNU-stack,"",@progbits
