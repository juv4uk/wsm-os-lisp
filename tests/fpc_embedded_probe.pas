unit fpc_embedded_probe;

{$mode objfpc}

interface

type
  TEfiProbeFunction = function(A, B, C, D: QWord): QWord; MS_ABI_Default;

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl;
  public name 'wsm_fpc_embedded_probe';
function wsm_invoke_efi_probe(Fn: TEfiProbeFunction): QWord; cdecl;
  public name 'wsm_invoke_efi_probe';
function wsm_efi_callback(Value: QWord; Context: Pointer): QWord;
  MS_ABI_Default; public name 'wsm_efi_callback';

implementation

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl;
begin
  Result := Left + Right;
end;

function wsm_invoke_efi_probe(Fn: TEfiProbeFunction): QWord; cdecl;
begin
  Result := Fn(1, 2, 3, 4);
end;

function wsm_efi_callback(Value: QWord; Context: Pointer): QWord;
  MS_ABI_Default;
begin
  if Context = nil then
    Exit(0);
  Result := Value + PQWord(Context)^;
end;

end.
