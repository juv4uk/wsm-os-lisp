program fpc_embedded_program_features;

{$mode objfpc}{$H+}

type
  EProbe = class
  end;

threadvar
  ThreadValue: LongInt;

var
  Counter: LongInt;

begin
  try
    Inc(Counter);
    raise EProbe.Create;
  except
    on E: EProbe do
      ThreadValue := 1;
  end;
end.
