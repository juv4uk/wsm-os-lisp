use std::mem::MaybeUninit;

use wsm_os_runtime::{ConsCell, RuntimeContext};
use wsm_os_target::{FIRST_FIXTURE_SOURCE, Word, decode_fixnum, decode_symbol};

core::arch::global_asm!(
    include_str!(concat!(env!("OUT_DIR"), "/fixture.s")),
    options(att_syntax)
);

unsafe extern "C" {
    fn wsm_entry(context: *mut RuntimeContext) -> Word;
}

extern "C" fn hosted_failure(code: u32) -> ! {
    eprintln!("WSM-OS ERROR schema=1 code={code}");
    std::process::exit(i32::try_from(code).unwrap_or(255));
}

fn render(value: Word, context: &RuntimeContext) -> Result<String, &'static str> {
    if value == wsm_os_target::NIL {
        return Ok("()".to_string());
    }
    if value == wsm_os_target::TRUE {
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
    // SAFETY: the aligned arena remains alive and exclusively owned until
    // after generated code and canonical rendering finish.
    let mut context = unsafe { RuntimeContext::new(heap.as_mut_ptr(), heap.len(), hosted_failure) };
    // SAFETY: `wsm_entry` is generated from pinned CML and follows target ABI v1.
    let result = unsafe { wsm_entry(&mut context) };
    println!(
        "{}",
        render(result, &context).expect("generated result must render")
    );
}
