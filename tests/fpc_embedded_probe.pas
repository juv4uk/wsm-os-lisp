unit fpc_embedded_probe;

{$mode objfpc}

interface

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl; public name 'wsm_fpc_embedded_probe';

implementation

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl;
begin
  Result := Left + Right;
end;

end.
