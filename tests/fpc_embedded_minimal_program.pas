program fpc_embedded_minimal_program;

{$mode objfpc}{$H+}{$J-}

type
  TWord = UInt64;

const
  SYMBOL_A = (TWord(1) shl 3) or TWord(4);
  SYMBOL_B = (TWord(2) shl 3) or TWord(4);

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; public name 'wsm_entry';
begin
  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

begin
  // The assembly entry calls wsm_entry directly; this body is not entered.
end.
