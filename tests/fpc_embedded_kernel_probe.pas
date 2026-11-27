unit fpc_embedded_kernel_probe;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = QWord;
  TEfiProbeFunction = function(A, B, C, D: QWord): QWord; MS_ABI_Default;

function wsm_entry(Context: Pointer): TWord; cdecl;
  public name 'wsm_entry';
function wsm_efi_callback(Value: QWord; Context: Pointer): QWord;
  MS_ABI_Default; public name 'wsm_efi_callback';

implementation

function wsm_cons(Context: Pointer; Car, Cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';
function wsm_efi_msabi_stub(A, B, C, D: QWord): QWord;
  MS_ABI_Default; external name 'wsm_efi_msabi_stub';

const
  SymbolA = (TWord(1) shl 3) or TWord(4);
  SymbolB = (TWord(2) shl 3) or TWord(4);

function wsm_efi_callback(Value: QWord; Context: Pointer): QWord;
  MS_ABI_Default;
begin
  if Context = nil then
    Exit(0);
  Result := Value + PQWord(Context)^;
end;

function wsm_entry(Context: Pointer): TWord; cdecl;
var
  EfiFunction: TEfiProbeFunction;
  AbiResult: QWord;
begin
  EfiFunction := @wsm_efi_msabi_stub;
  AbiResult := EfiFunction(1, 2, 3, 4);
  if AbiResult <> 22 then
    Exit(0);
  Result := wsm_cons(Context, SymbolA, SymbolB);
end;

end.
