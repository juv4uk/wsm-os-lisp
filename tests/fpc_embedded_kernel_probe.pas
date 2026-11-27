unit fpc_embedded_kernel_probe;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = QWord;

function wsm_entry(Context: Pointer): TWord; cdecl;
  public name 'wsm_entry';

implementation

function wsm_cons(Context: Pointer; Car, Cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

const
  SymbolA = (TWord(1) shl 3) or TWord(4);
  SymbolB = (TWord(2) shl 3) or TWord(4);

function wsm_entry(Context: Pointer): TWord; cdecl;
begin
  Result := wsm_cons(Context, SymbolA, SymbolB);
end;

end.
