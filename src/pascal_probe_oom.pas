unit pascal_probe_oom;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = UInt64;

function wsm_entry(ctx: Pointer): TWord; cdecl;
  public name 'wsm_entry';

implementation

const
  NIL_WORD = TWord(1);

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; cdecl;
begin
  while True do
    wsm_cons(ctx, NIL_WORD, NIL_WORD);
  Result := NIL_WORD;
end;

end.
