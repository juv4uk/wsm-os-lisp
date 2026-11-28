unit pascal_handoff;

{$mode objfpc}{$H+}{$J-}

interface

type
  TWord = UInt64;

function wsm_entry(ctx: Pointer): TWord; cdecl;
  public name 'wsm_entry';

implementation

uses
  wsm.bootinfo;

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

function wsm_entry(ctx: Pointer): TWord; cdecl;
var
  offset: TWord;
  diagnostic: TWord;
  status: TWsmBootInfoStatus;
begin
  status := WsmBootInfoReadPhysicalMemoryOffset(
    saved_boot_info,
    offset,
    diagnostic
  );

  { Avoid case labels on exported typed constants across FPC targets. }
  if status <> WSM_BOOTINFO_STATUS_OK then
  begin
    if status = WSM_BOOTINFO_STATUS_MISSING then
      wsm_fail_src(ctx, ERR_ABI, HAN_ERR_MISSING, diagnostic)
    else if status = WSM_BOOTINFO_STATUS_INVALID_TAG then
      wsm_fail_src(ctx, ERR_ABI, HAN_ERR_TAG, diagnostic)
    else if status = WSM_BOOTINFO_STATUS_ZERO_OFFSET then
      wsm_fail_src(ctx, ERR_ABI, HAN_ERR_ZERO, diagnostic)
    else
      wsm_fail_src(ctx, ERR_ABI, HAN_ERR_TAG, TWord(status));
  end;

  if offset <> wsm_target_phys_mem_offset then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_MISMATCH, offset);

  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

end.
