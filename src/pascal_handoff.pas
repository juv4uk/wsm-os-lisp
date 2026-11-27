unit pascal_handoff;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = UInt64;
  TBytePtr = ^Byte;

function wsm_entry(ctx: Pointer): TWord; cdecl;
  public name 'wsm_entry';

implementation

const
  SYMBOL_A = (TWord(1) shl 3) or TWord(4);
  SYMBOL_B = (TWord(2) shl 3) or TWord(4);
  ERR_ABI = LongWord(4);
  HAN_ERR_MISSING  = LongWord($48414E01);
  HAN_ERR_TAG      = LongWord($48414E02);
  HAN_ERR_ZERO     = LongWord($48414E03);
  HAN_ERR_MISMATCH = LongWord($48414E04);

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

procedure wsm_fail_src(ctx: Pointer; code: LongWord; source: LongWord; value: TWord);
  cdecl; external name 'wsm_fail_src';

var
  saved_boot_info: Pointer; cvar; external;
  wsm_target_phys_mem_offset: TWord; cvar; external;

function handoff_offset(ctx: Pointer; boot_info: TBytePtr): TWord;
var
  tag: Byte;
  value: TWord;
begin
  if boot_info = nil then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_MISSING, 0);

  tag := (boot_info + $58)^;
  if tag = 1 then
  begin
    Result := 0;
    Exit;
  end;
  if tag <> 0 then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_TAG, TWord(tag));

  value := TWord((boot_info + $60)^) or
           (TWord((boot_info + $61)^) shl 8) or
           (TWord((boot_info + $62)^) shl 16) or
           (TWord((boot_info + $63)^) shl 24) or
           (TWord((boot_info + $64)^) shl 32) or
           (TWord((boot_info + $65)^) shl 40) or
           (TWord((boot_info + $66)^) shl 48) or
           (TWord((boot_info + $67)^) shl 56);

  if value = 0 then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_ZERO, 0);

  Result := value;
end;

function wsm_entry(ctx: Pointer): TWord; cdecl;
var
  offset: TWord;
begin
  offset := handoff_offset(ctx, TBytePtr(saved_boot_info));
  if offset <> wsm_target_phys_mem_offset then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_MISMATCH, offset);
  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

end.
