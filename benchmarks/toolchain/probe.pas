program ToolchainProbe;

var
  I: Int64;
  Sum: Int64;

begin
  Sum := 0;
  for I := 1 to 1000000 do
    Sum := Sum + ((I * 17) mod 97);
  WriteLn('result=', Sum);
end.
