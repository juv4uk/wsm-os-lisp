program test_wsm_bootinfo;

{$mode objfpc}{$H+}

uses
  SysUtils,
  wsm.bootinfo;

type
  TBootInfoStorage = array[0..$68] of Byte;

var
  TestsRun: Integer = 0;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure PutUInt64LE(var Storage: TBootInfoStorage; StartIndex: SizeInt; Value: QWord);
var
  Index: SizeInt;
begin
  for Index := 0 to 7 do
  begin
    Storage[StartIndex + Index] := Byte(Value and $FF);
    Value := Value shr 8;
  end;
end;

procedure TestMissingPointer;
var
  Offset: QWord;
  Diagnostic: QWord;
  Status: TWsmBootInfoStatus;
begin
  Offset := $FFFFFFFFFFFFFFFF;
  Diagnostic := $FFFFFFFFFFFFFFFF;
  Status := WsmBootInfoReadPhysicalMemoryOffset(nil, Offset, Diagnostic);
  Require(Status = WSM_BOOTINFO_STATUS_MISSING, 'nil pointer must be MISSING');
  Require(Offset = 0, 'missing pointer must clear offset');
  Require(Diagnostic = 0, 'missing pointer must clear diagnostic');
  Inc(TestsRun);
end;

procedure TestOptionalNone;
var
  Storage: TBootInfoStorage;
  Offset: QWord;
  Diagnostic: QWord;
  Status: TWsmBootInfoStatus;
begin
  FillChar(Storage, SizeOf(Storage), 0);
  Storage[WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET] := WSM_BOOTINFO_OPTIONAL_NONE_TAG;
  Offset := $FFFFFFFFFFFFFFFF;
  Diagnostic := $FFFFFFFFFFFFFFFF;
  Status := WsmBootInfoReadPhysicalMemoryOffset(@Storage[0], Offset, Diagnostic);
  Require(Status = WSM_BOOTINFO_STATUS_OK, 'Optional None must be accepted');
  Require(Offset = 0, 'Optional None must decode to zero offset');
  Require(Diagnostic = 0, 'Optional None must clear diagnostic');
  Inc(TestsRun);
end;

procedure TestSomeUnaligned;
const
  Expected = QWord($123456789ABCDEF0);
var
  Storage: TBootInfoStorage;
  Offset: QWord;
  Diagnostic: QWord;
  Status: TWsmBootInfoStatus;
begin
  FillChar(Storage, SizeOf(Storage), 0);
  Storage[1 + WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET] := WSM_BOOTINFO_OPTIONAL_SOME_TAG;
  PutUInt64LE(Storage, 1 + WSM_BOOTINFO_PHYSICAL_MEMORY_VALUE_OFFSET, Expected);
  Offset := 0;
  Diagnostic := $FFFFFFFFFFFFFFFF;
  Status := WsmBootInfoReadPhysicalMemoryOffset(@Storage[1], Offset, Diagnostic);
  Require(Status = WSM_BOOTINFO_STATUS_OK, 'unaligned Optional Some must be accepted');
  Require(Offset = Expected, 'little-endian unaligned u64 must be decoded exactly');
  Require(Diagnostic = 0, 'valid Optional Some must clear diagnostic');
  Inc(TestsRun);
end;

procedure TestInvalidTag;
var
  Storage: TBootInfoStorage;
  Offset: QWord;
  Diagnostic: QWord;
  Status: TWsmBootInfoStatus;
begin
  FillChar(Storage, SizeOf(Storage), 0);
  Storage[WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET] := 2;
  Offset := $FFFFFFFFFFFFFFFF;
  Diagnostic := 0;
  Status := WsmBootInfoReadPhysicalMemoryOffset(@Storage[0], Offset, Diagnostic);
  Require(Status = WSM_BOOTINFO_STATUS_INVALID_TAG, 'unknown Optional tag must fail closed');
  Require(Offset = 0, 'invalid tag must clear offset');
  Require(Diagnostic = 2, 'invalid tag must preserve its diagnostic value');
  Inc(TestsRun);
end;

procedure TestSomeZero;
var
  Storage: TBootInfoStorage;
  Offset: QWord;
  Diagnostic: QWord;
  Status: TWsmBootInfoStatus;
begin
  FillChar(Storage, SizeOf(Storage), 0);
  Storage[WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET] := WSM_BOOTINFO_OPTIONAL_SOME_TAG;
  PutUInt64LE(Storage, WSM_BOOTINFO_PHYSICAL_MEMORY_VALUE_OFFSET, 0);
  Offset := $FFFFFFFFFFFFFFFF;
  Diagnostic := $FFFFFFFFFFFFFFFF;
  Status := WsmBootInfoReadPhysicalMemoryOffset(@Storage[0], Offset, Diagnostic);
  Require(Status = WSM_BOOTINFO_STATUS_ZERO_OFFSET, 'Some(0) must fail closed');
  Require(Offset = 0, 'Some(0) must return zero output');
  Require(Diagnostic = 0, 'Some(0) must clear diagnostic');
  Inc(TestsRun);
end;

begin
  try
    TestMissingPointer;
    TestOptionalNone;
    TestSomeUnaligned;
    TestInvalidTag;
    TestSomeZero;
    if TestsRun <> 5 then
      raise Exception.CreateFmt('unexpected test count: %d', [TestsRun]);
    WriteLn('WSM-BOOTINFO-TESTS-PASS: ', TestsRun, '/5');
  except
    on Error: Exception do
    begin
      WriteLn(StdErr, 'WSM-BOOTINFO-TESTS-FAIL: ', Error.Message);
      Halt(1);
    end;
  end;
end.
