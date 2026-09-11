use std::mem::MaybeUninit;

use wsm_os_runtime::{ConsCell, RuntimeContext, wsm_fail};
use wsm_os_target::{ClosureDescriptor, Word, decode_fixnum, decode_symbol};

const FIRST_FIXTURE_SOURCE: &str = "(cons (quote A) (quote B))";

core::arch::global_asm!(
    include_str!(concat!(env!("OUT_DIR"), "/fixture.s")),
    options(att_syntax)
);

unsafe extern "C" {
    fn wsm_entry(context: *mut RuntimeContext) -> Word;
}

use wsm_os_target::{
    CapabilityDescriptor, CapabilityKind, decode_capability_descriptor,
    encode_capability_descriptor,
};

const PCI_CONFIG_HOSTED_NONCE: Word = 0x1504_3495_4346; // 45-bit valid nonce

#[unsafe(no_mangle)]
pub extern "C" fn wsm_pci_config_capability(_context: *mut RuntimeContext) -> Word {
    let desc = CapabilityDescriptor::new(CapabilityKind::PciConfig, 0, PCI_CONFIG_HOSTED_NONCE)
        .expect("PCI config descriptor must be valid");
    encode_capability_descriptor(desc).expect("PCI config capability must encode")
}

fn hosted_verify_pci_capability(capability: Word) -> bool {
    decode_capability_descriptor(capability).is_some_and(|desc| {
        desc.kind == CapabilityKind::PciConfig
            && desc.instance == 0
            && desc.nonce == PCI_CONFIG_HOSTED_NONCE
    })
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
    let valid_capability = hosted_verify_pci_capability(capability);
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

// ---------------------------------------------------------------------------
// Hosted MMIO mocks — simulate virtio-blk COMMON_CFG for d2 fixture
// ---------------------------------------------------------------------------

use std::sync::atomic::{AtomicU32, Ordering};

/// Simulated device status register (COMMON_CFG_STATUS at offset 20 = 0x14).
static MOCK_DEVICE_STATUS: AtomicU32 = AtomicU32::new(0);

const MMIO_HOSTED_NONCE: Word = 0x1A04_9512_4347; // 45-bit valid nonce (max 0x1FFF_FFFF_FFFF)

#[unsafe(no_mangle)]
pub extern "C" fn wsm_mmio_capability(_context: *mut RuntimeContext) -> Word {
    let desc = CapabilityDescriptor::new(CapabilityKind::Mmio, 0, MMIO_HOSTED_NONCE)
        .expect("MMIO descriptor must be valid");
    encode_capability_descriptor(desc).expect("MMIO capability must encode")
}

fn hosted_verify_mmio_capability(capability: Word) -> bool {
    decode_capability_descriptor(capability).is_some_and(|desc| {
        desc.kind == CapabilityKind::Mmio && desc.instance == 0 && desc.nonce == MMIO_HOSTED_NONCE
    })
}

/// Hosted 32-bit MMIO read — returns simulated register value.
#[unsafe(no_mangle)]
pub extern "C" fn wsm_mmio_read32(
    context: *mut RuntimeContext,
    capability: Word,
    offset: Word,
) -> Word {
    let Some(offset) = wsm_os_target::decode_fixnum(offset) else {
        unsafe {
            wsm_fail(
                context,
                wsm_os_target::ErrorCode::AbiViolation as u32,
                capability,
                0x4D494F01,
            )
        }
    };
    if !hosted_verify_mmio_capability(capability)
        || !(0..=4095).contains(&offset)
        || offset % 4 != 0
    {
        unsafe {
            wsm_fail(
                context,
                wsm_os_target::ErrorCode::AbiViolation as u32,
                capability,
                0x4D494F02,
            )
        }
    }
    // Offset 20 (0x14) = COMMON_CFG_STATUS; other offsets read as 0
    let value: u32 = if offset == 20 {
        MOCK_DEVICE_STATUS.load(Ordering::SeqCst)
    } else {
        0
    };
    wsm_os_target::encode_fixnum(value as i64).unwrap()
}

/// Hosted 32-bit MMIO write — stores to simulated register.
#[unsafe(no_mangle)]
pub extern "C" fn wsm_mmio_write32(
    context: *mut RuntimeContext,
    capability: Word,
    offset: Word,
    value: Word,
) -> Word {
    let (Some(offset), Some(value)) = (
        wsm_os_target::decode_fixnum(offset),
        wsm_os_target::decode_fixnum(value),
    ) else {
        unsafe {
            wsm_fail(
                context,
                wsm_os_target::ErrorCode::AbiViolation as u32,
                capability,
                0x4D494F04,
            )
        }
    };
    if !hosted_verify_mmio_capability(capability)
        || !(0..=4095).contains(&offset)
        || offset % 4 != 0
    {
        unsafe {
            wsm_fail(
                context,
                wsm_os_target::ErrorCode::AbiViolation as u32,
                capability,
                0x4D494F05,
            )
        }
    }
    if offset == 20 {
        MOCK_DEVICE_STATUS.store(value as u32, Ordering::SeqCst);
    }
    wsm_os_target::NIL
}

extern "C" fn hosted_failure(context_ptr: *const RuntimeContext, code: u32) -> ! {
    let ctx = unsafe { &*context_ptr };
    let kind_str = match ctx.condition.kind {
        1 => "OOM",
        2 => "TYPE",
        3 => "SYMBOL",
        4 => "ABI",
        5 => "NUMERIC_OVERFLOW",
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
        return Err("legacy true tag is not admitted semantic truth");
    }
    if value == wsm_os_target::CANONICAL_T {
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

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn unexpected_failure(_context: *const RuntimeContext, _code: u32) -> ! {
        panic!("unexpected hosted failure")
    }

    #[test]
    fn legacy_true_tag_is_not_rendered_as_language_t() {
        let mut heap = [MaybeUninit::<ConsCell>::uninit(); 1];
        let runtime =
            unsafe { RuntimeContext::new(heap.as_mut_ptr(), heap.len(), unexpected_failure) };
        assert_eq!(
            render(wsm_os_target::CANONICAL_T, &runtime),
            Ok("t".to_string())
        );
        assert_eq!(
            render(wsm_os_target::TRUE, &runtime),
            Err("legacy true tag is not admitted semantic truth")
        );
    }

    #[test]
    fn legacy_numeric_capability_id_is_not_authority() {
        let legacy = wsm_os_target::encode_capability(1).unwrap();
        assert!(!hosted_verify_pci_capability(legacy));
        assert!(!hosted_verify_mmio_capability(legacy));
    }
}
