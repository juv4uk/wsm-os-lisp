program PascalCallsC;

{$mode objfpc}
{$linklib probe}

function c_mix(left, right: LongInt): LongInt; cdecl; external name 'c_mix';

var
  Actual: LongInt;

begin
  Actual := c_mix(13, 29);
  if Actual <> 367 then
    Halt(1);
  WriteLn('abi=cdecl i32 scalar result=', Actual);
end.
