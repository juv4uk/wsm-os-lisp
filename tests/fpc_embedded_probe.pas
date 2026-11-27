unit FpcEmbeddedProbe;

{$mode objfpc}

interface

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl;

implementation

function wsm_fpc_embedded_probe(Left, Right: LongInt): LongInt; cdecl;
begin
  Result := Left + Right;
end;

end.
