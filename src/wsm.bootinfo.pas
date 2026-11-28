unit wsm.bootinfo;

{$mode objfpc}{$H+}{$J-}

interface

type
  { Fixed-width status values are part of this unit's stable target interface. }
  TWsmBootInfoStatus = type Byte;

const
  WSM_BOOTINFO_STATUS_OK: TWsmBootInfoStatus = 0;
  WSM_BOOTINFO_STATUS_MISSING: TWsmBootInfoStatus = 1;
  WSM_BOOTINFO_STATUS_INVALID_TAG: TWsmBootInfoStatus = 2;
  WSM_BOOTINFO_STATUS_ZERO_OFFSET: TWsmBootInfoStatus = 3;

  { bootloader_api 0.11.17: Optional<u64> discriminant and payload offsets. }
  WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET = $58;
  WSM_BOOTINFO_PHYSICAL_MEMORY_VALUE_OFFSET = $60;
  WSM_BOOTINFO_OPTIONAL_SOME_TAG = 0;
  WSM_BOOTINFO_OPTIONAL_NONE_TAG = 1;

function WsmBootInfoReadPhysicalMemoryOffset(
  BootInfo: Pointer;
  out PhysicalMemoryOffset: QWord;
  out DiagnosticValue: QWord
): TWsmBootInfoStatus; cdecl;

implementation

type
  TBytePtr = ^Byte;

function ReadByte(Base: TBytePtr; Offset: PtrUInt): Byte; inline;
begin
  Result := (Base + Offset)^;
end;

function ReadUInt64LE(Base: TBytePtr; Offset: PtrUInt): QWord;
begin
  { Read one byte at a time: BootInfo fields need not be naturally aligned. }
  Result :=
    QWord(ReadByte(Base, Offset)) or
    (QWord(ReadByte(Base, Offset + 1)) shl 8) or
    (QWord(ReadByte(Base, Offset + 2)) shl 16) or
    (QWord(ReadByte(Base, Offset + 3)) shl 24) or
    (QWord(ReadByte(Base, Offset + 4)) shl 32) or
    (QWord(ReadByte(Base, Offset + 5)) shl 40) or
    (QWord(ReadByte(Base, Offset + 6)) shl 48) or
    (QWord(ReadByte(Base, Offset + 7)) shl 56);
end;

function WsmBootInfoReadPhysicalMemoryOffset(
  BootInfo: Pointer;
  out PhysicalMemoryOffset: QWord;
  out DiagnosticValue: QWord
): TWsmBootInfoStatus; cdecl;
var
  Base: TBytePtr;
  Tag: Byte;
begin
  PhysicalMemoryOffset := 0;
  DiagnosticValue := 0;

  if BootInfo = nil then
  begin
    Result := WSM_BOOTINFO_STATUS_MISSING;
    Exit;
  end;

  Base := TBytePtr(BootInfo);
  Tag := ReadByte(Base, WSM_BOOTINFO_PHYSICAL_MEMORY_TAG_OFFSET);

  if Tag = WSM_BOOTINFO_OPTIONAL_NONE_TAG then
  begin
    Result := WSM_BOOTINFO_STATUS_OK;
    Exit;
  end;

  if Tag <> WSM_BOOTINFO_OPTIONAL_SOME_TAGthen
  begin
    DiagnosticValue := QWord(Tag);
    Result := WSM_BOOTINFO_STATUS_INVALID_TAG;
    Exit;
  end;

  PhysicalMemoryOffset := ReadUInt64LE(Base,
    WSM_BOOTINFO_PHYSICAL_MEMORY_VALUE_OFFSET
  );
  if PhysicalMemoryOffset = 0 then
  begin
    Result := WSM_BOOTINFO_STATUS_ZERO_OFFSET;
    Exit;
  end;

  Result := WSM_BOOTINFO_STATUS_OK;
end;

end.
