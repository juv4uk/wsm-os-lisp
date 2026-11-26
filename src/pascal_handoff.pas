// ===========================================================================
// src/pascal_handoff.pas — the handoff boundary, owned by Pascal.
//
// ADR-006 P1 remainder: until now the asm entry parsed BootInfo and handed
// Pascal a ready RuntimeContext*, so "Pascal owns the kernel entry" was only
// half true. Here Pascal reads the bootloader record itself, validates it, and
// fails closed with a named condition when it is missing or malformed.
//
// The record layout is the one already documented in
// docs/TARGET-BOOT-HANDOFF-ABI.md and implemented in src/runtime.s:
//   BootInfo + 0x58 : u8   Optional<u64> tag   0 = Some, 1 = None
//   BootInfo + 0x60 : u64  physical_memory_offset value (when tag = 0)
//
// The witness asserts parity with the assembly result: if Pascal's reading of
// the record disagrees with wsm_target_phys_mem_offset, that is an ABI defect
// and it fails closed instead of proceeding on a guess.
// ===========================================================================
program pascal_handoff;

{$mode objfpc}{$H+}{$J-}

type
  TWord = UInt64;
  TBytePtr = ^Byte;

const
  SYMBOL_A = (TWord(1) shl 3) or TWord(4);
  SYMBOL_B = (TWord(2) shl 3) or TWord(4);

  // Closed condition vocabulary shared with src/runtime.s.
  ERR_ABI = LongWord(4);

  // Handoff failure sources, same 0x..NN family as the GC and MMIO codes.
  HAN_ERR_MISSING  = LongWord($48414E01);  // no BootInfo pointer at all
  HAN_ERR_TAG      = LongWord($48414E02);  // Optional<u64> tag is neither 0 nor 1
  HAN_ERR_ZERO     = LongWord($48414E03);  // tag says Some, value is zero
  HAN_ERR_MISMATCH = LongWord($48414E04);  // Pascal and asm read different offsets

function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

// Never returns: it records the condition and the entry handler exits.
procedure wsm_fail_src(ctx: Pointer; code: LongWord; source: LongWord; value: TWord);
  cdecl; external name 'wsm_fail_src';

var
  saved_boot_info: Pointer; cvar; external;
  wsm_target_phys_mem_offset: TWord; cvar; external;

// Returns the validated physical-memory offset, or 0 when the bootloader
// explicitly reported that no mapping was provided (tag = 1).
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

  // Little-endian u64 at +0x60, assembled byte by byte so the read does not
  // depend on the compiler's alignment assumptions for an unaligned pointer.
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

function wsm_entry(ctx: Pointer): TWord; public name 'wsm_entry';
var
  offset: TWord;
begin
  offset := handoff_offset(ctx, TBytePtr(saved_boot_info));

  // Parity with the assembly reading of the same record. A disagreement is a
  // defect in one of the two readers, never something to paper over.
  if offset <> wsm_target_phys_mem_offset then
    wsm_fail_src(ctx, ERR_ABI, HAN_ERR_MISMATCH, offset);

  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;

begin
end.
