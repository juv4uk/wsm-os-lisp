// ===========================================================================
// src/pascal_probe_oom.pas — the named-failure half of the ADR-006 P2 parity
// matrix, written in Pascal.
//
// It must produce exactly the transcript of the assembly witness
// artifacts/nucleus-witness-alloc-oom-fixture.s:
//   WSM-OS BOOT schema=1 arch=x86_64 status=ok
//   WSM-OS CONDITION schema=1 kind=OOM source=0 value=0
//
// The loop is deliberate and unbounded: the point is that exhaustion of the
// target arena reaches the same named condition through Pascal as through
// assembly. No counter, no assumption about the arena size.
// ===========================================================================
program pascal_probe_oom;

{$mode objfpc}{$H+}{$J-}

type
  TWord = UInt64;

const
  NIL_WORD = TWord(1);

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; public name 'wsm_entry';
begin
  while True do
    wsm_cons(ctx, NIL_WORD, NIL_WORD);
  Result := NIL_WORD;
end;

begin
end.
