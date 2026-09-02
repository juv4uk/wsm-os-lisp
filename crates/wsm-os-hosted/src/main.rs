use std::mem::MaybeUninit;

use wsm_os_runtime::{ConsCell, RuntimeContext, wsm_fail};
use wsm_os_target::{ClosureDescriptor, FIRST_FIXTURE_SOURCE, Word, decode_fixnum, decode_symbol};

core::arch::global_asm!(
    include_str!(concat!(env!("OUT_DIR"), "/fixture.s")),
    options(att_syntax)
);

unsafe extern "C" {
    fn wsm_entry(context: *mut RuntimeContext) -> Word;
}

const PCI_CONFIG_CAPABILITY_ID: Word = 1;

#[unsafe(no_mangle)]
pub extern "C" fn wsm_pci_config_capability(_context: *mut RuntimeContext) -> Word {
    wsm_os_target::encode_capability(PCI_CONFIG_CAPABILITY_ID).unwrap()
}

/// Hosted reference mechanism for the fixed QEMU D1 fixture BDF 00:05.0.
/// Driver recognition remains in the generated WSM object.
#[unsafe(no_mangle)]
pub extern "C" fn wsm_pci_config_read16(
    context: *mut RuntimeContext,
    capability: Word,
    bus: Word,
    device: Word,
    function: Word,
    offset: Word,
) -> Word {
    let valid_capability =
        capability == wsm_os_target::encode_capability(PCI_CONFIG_CAPABILITY_ID).unwrap();
    let coordinates = (
        decode_fixnum(bus),
        decode_fixnum(device),
        decode_fixnum(function),
        decode_fixnum(offset),
    );
    let value = match (valid_capability, coordinates) {
        (true, (Some(0), Some(5), Some(0), Some(0))) => 0x1af4,
        (true, (Some(0), Some(5), Some(0), Some(2))) => 0x1042,
        (true, (Some(0), Some(0..=31), Some(0..=7), Some(offset @ 0..=254))) if offset % 2 == 0 => {
            0xffff
        }
        _ => unsafe {
            wsm_fail(
                context,
                wsm_os_target::ErrorCode::AbiViolation as u32,
                capability,
                0x5043_4903,
            )
        },
    };
    wsm_os_target::encode_fixnum(value).unwrap()
}

extern "C" fn hosted_failure(context_ptr: *const RuntimeContext, code: u32) -> ! {
    let ctx = unsafe { &*context_ptr };
    let kind_str = match ctx.condition.kind {
        1 => "OOM",
        2 => "TYPE",
        3 => "SYMBOL",
        4 => "ABI",
        _ => "UNKNOWN",
    };
    eprintln!(
        "WSM-OS CONDITION schema=1 kind={} source={} value={}",
        kind_str, ctx.condition.source_id, ctx.condition.offending_value
    );
    std::process::exit(i32::try_from(code).unwrap_or(255));
}

fn render(value: Word, context: &RuntimeContext) -> Result<String, &'static str> {
    if value == wsm_os_target::NIL {
        return Ok("()".to_string());
    }
    if value == wsm_os_target::TRUE {
        return Ok("t".to_string());
    }
    // 2026-09-02: wsm-os-runtime's eq/atom no longer produce Tag::True (a
    // manufactured primitive canonical WSM never had) -- they produce
    // canonical Symbol("t"), encoded with the reserved SYMBOL_ID_MAX
    // sentinel id (see wsm-os-runtime::CANONICAL_T's own comment for why a
    // sentinel, not a proven-unique id, given wsm-os-target's per-program
    // symbol interning). Render it the same way the old TAG_TRUE case was
    // rendered, before falling through to this fixture's own hardcoded
    // per-program symbol table (which never registered this id, since it
    // is not a symbol *this* compiled program itself interned).
    if let Some(wsm_os_target::SYMBOL_ID_MAX) = decode_symbol(value) {
        return Ok("t".to_string());
    }
    if let Some(integer) = decode_fixnum(value) {
        return Ok(integer.to_string());
    }
    if let Some(symbol) = decode_symbol(value) {
        return match symbol {
            1 => Ok("A".to_string()),
            2 => Ok("B".to_string()),
            _ => Err("unknown image-local symbol id"),
        };
    }
    let cell = context.cell(value).map_err(|_| "invalid cons pointer")?;
    let car = render(cell.car, context)?;
    if cell.cdr == wsm_os_target::NIL {
        return Ok(format!("({car})"));
    }
    if context.cell(cell.cdr).is_ok() {
        let tail = render_list_tail(cell.cdr, context)?;
        Ok(format!("({car} {tail})"))
    } else {
        Ok(format!("({car} . {})", render(cell.cdr, context)?))
    }
}

fn render_list_tail(value: Word, context: &RuntimeContext) -> Result<String, &'static str> {
    let cell = context.cell(value).map_err(|_| "invalid list tail")?;
    let car = render(cell.car, context)?;
    if cell.cdr == wsm_os_target::NIL {
        Ok(car)
    } else if context.cell(cell.cdr).is_ok() {
        Ok(format!("{car} {}", render_list_tail(cell.cdr, context)?))
    } else {
        Ok(format!("{car} . {}", render(cell.cdr, context)?))
    }
}

fn main() {
    assert_eq!(FIRST_FIXTURE_SOURCE, "(cons (quote A) (quote B))");
    let mut heap = [MaybeUninit::<ConsCell>::uninit(); 8];
    let mut closures = [MaybeUninit::<ClosureDescriptor>::uninit(); 4];
    // SAFETY: the aligned arena remains alive and exclusively owned until
    // after generated code and canonical rendering finish.
    let mut context = unsafe {
        RuntimeContext::new_with_closures(
            heap.as_mut_ptr(),
            heap.len(),
            closures.as_mut_ptr(),
            closures.len(),
            hosted_failure,
        )
    };
    // SAFETY: `wsm_entry` is generated from pinned CML and follows target ABI v1.
    let result = unsafe { wsm_entry(&mut context) };
    println!(
        "{}",
        render(result, &context).expect("generated result must render")
    );
}
