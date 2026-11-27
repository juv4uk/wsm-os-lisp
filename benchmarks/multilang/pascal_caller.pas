program PascalCallsC;

{$mode objfpc}
{$PACKRECORDS C}
{$linklib probe}

type
  TProbeRecord = record
    Tag: LongInt;
    Value: QWord;
  end;
  PProbeRecord = ^TProbeRecord;
  TProbeCallback = function(Value: LongInt; Context: Pointer): LongInt; cdecl;

function c_mix(Left, Right: LongInt): LongInt; cdecl; external name 'c_mix';
function c_probe_record_size: QWord; cdecl; external name 'c_probe_record_size';
function c_probe_record_value_offset: QWord; cdecl; external name 'c_probe_record_value_offset';
function c_record_transform(RecordPtr: PProbeRecord; Callback: TProbeCallback;
  Context: Pointer): LongInt; cdecl; external name 'c_record_transform';

function ProbeCallback(Value: LongInt; Context: Pointer): LongInt; cdecl;
var
  Multiplier: PLongInt;
begin
  if Context = nil then
    Exit(-100);
  Multiplier := PLongInt(Context);
  Result := Value * Multiplier^;
end;

var
  Actual: LongInt;
  RecordValue: TProbeRecord;
  Multiplier: LongInt;
  CallbackResult: LongInt;
  PascalOffset: QWord;

begin
  Actual := c_mix(13, 29);
  if Actual <> 439 then
    Halt(1);

  PascalOffset := QWord(PtrUInt(@RecordValue.Value) - PtrUInt(@RecordValue));
  if c_probe_record_size <> QWord(SizeOf(TProbeRecord)) then
    Halt(2);
  if c_probe_record_value_offset <> PascalOffset then
    Halt(3);

  RecordValue.Tag := 6;
  RecordValue.Value := 100;
  Multiplier := 7;
  CallbackResult := c_record_transform(@RecordValue, @ProbeCallback, @Multiplier);
  if CallbackResult <> 42 then
    Halt(4);
  if RecordValue.Value <> 107 then
    Halt(5);

  { C must reject invalid borrowed arguments without calling back. }
  if c_record_transform(nil, @ProbeCallback, @Multiplier) <> -1 then
    Halt(6);
  if c_record_transform(@RecordValue, nil, @Multiplier) <> -1 then
    Halt(7);
  if c_record_transform(@RecordValue, @ProbeCallback, nil) <> -1 then
    Halt(8);

  WriteLn('abi=cdecl i32 scalar result=', Actual);
  WriteLn('abi=record size=', SizeOf(TProbeRecord),
    ' value_offset=', PascalOffset, ' value=', RecordValue.Value);
  WriteLn('abi=callback borrowed_context result=', CallbackResult);
  WriteLn('abi=negative null_arguments=rejected');
end.
