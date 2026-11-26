// ===========================================================================
// src/pascal_probe.pas — the first Pascal code that runs on the target.
//
// ADR-006 P1: a Pascal function receives the same RuntimeContext* the asm
// entry always passed, calls the asm runtime through the unchanged target ABI,
// and returns a tagged WSM word. The transcript must be byte-identical to the
// hand-written assembly fixture (artifacts/fixture.o), which is what makes this
// a parity witness and not a demo.
//
// What it deliberately does not do: no strings, no I/O, no heap of its own, no
// exceptions, no unit initialisation. Everything beyond arithmetic and a call
// into the asm ABI would need a mechanism that src/rtl_min.s does not provide.
//
// Calling convention: System V AMD64, the same one src/runtime.s implements —
// ctx in %rdi, first word in %rsi, second in %rdx, result in %rax.
// ===========================================================================
program pascal_probe;

{$mode objfpc}{$H+}{$J-}

type
  TWord = UInt64;

// Tag 000 is a cons pointer; tags 011 fixnum, 100 symbol, 101 closure.
const
  NIL_WORD = TWord(1);
  SYMBOL_A = (TWord(1) shl 3) or TWord(4);   // symbol id 1
  SYMBOL_B = (TWord(2) shl 3) or TWord(4);   // symbol id 2

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; public name 'wsm_entry';
begin
  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

begin
  // The asm entry calls wsm_entry directly; this program body never runs.
end.
