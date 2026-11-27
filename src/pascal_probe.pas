// Kernel-facing Pascal probe is a UNIT, not a PROGRAM.
// The assembly entry owns startup, stack, BootInfo parsing/runtime context.
unit pascal_probe;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = UInt64;

function wsm_entry(ctx: Pointer): TWord; cdecl;
  public name 'wsm_entry';

implementation

const
  SYMBOL_A = (TWord(1) shl 3) or TWord(4);
  SYMBOL_B = (TWord(2) shl 3) or TWord(4);

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; cdecl;
begin
  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

end.
