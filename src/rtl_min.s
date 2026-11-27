# ===========================================================================
# src/rtl_min.s — LEGACY historical no-op hooks; not linked by active unit tests
#
# Early FPC PROGRAM experiments emitted five references when the program
# is compiled with -Cn (no link stage) and linked by us:
#
#   fpc_initializeunits            unit initialisation entry
#   fpc_do_exit                    program exit path
#   INIT$_$SYSTEM                  system unit initialiser
#   FINALIZE$_$OBJPAS              objpas finaliser
#   THREADVARLIST_$SYSTEM$indirect threadvar table
#
# These definitions are no-ops with a fixed shape. They are historical evidence, not
# an active RTL. Current kernel experiments use Pascal UNITs and fail closed
# on unresolved imports. No active unit test may link this file.
#
# Any future PROGRAM runtime must implement and witness the real services;
# do not extend these no-op definitions.
#
# See docs/FPC-KERNEL-SKELETON.md and docs/research/FPC-EMBEDDED-PROBE-2026-11-27.md.
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
