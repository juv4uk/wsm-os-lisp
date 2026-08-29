#![no_std]

//! Allocation-bounded runtime core for CML-generated `wsm-os` objects.
//!
//! The core owns no host services. Its only storage is a caller-provided,
//! 16-byte-aligned cons arena. Hosted startup/printing and future boot I/O are
//! wrappers around this same ABI implementation.

use core::mem::MaybeUninit;
use wsm_os_target::{ErrorCode, NIL, RESULT_REGISTER, RUNTIME_IMPORTS, TRUE, Word};

const _: () = assert!(RESULT_REGISTER.as_bytes()[0] == b'r');
const _: () = assert!(RUNTIME_IMPORTS.len() == 6);

pub type FailureHandler = extern "C" fn(u32) -> !;

#[repr(C, align(16))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConsCell {
    pub car: Word,
    pub cdr: Word,
}

#[repr(C)]
pub struct RuntimeContext {
    heap: *mut MaybeUninit<ConsCell>,
    capacity: usize,
    len: usize,
    failure_handler: FailureHandler,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeError {
    OutOfMemory,
    Type,
    AbiViolation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ValueClass {
    Atom,
    Cons,
}

impl RuntimeError {
    pub const fn code(self) -> ErrorCode {
        match self {
            Self::OutOfMemory => ErrorCode::OutOfMemory,
            Self::Type => ErrorCode::Type,
            Self::AbiViolation => ErrorCode::AbiViolation,
        }
    }
}

impl RuntimeContext {
    /// Create a context over a caller-owned arena.
    ///
    /// # Safety
    ///
    /// `heap` must point to `capacity` writable, properly aligned
    /// `MaybeUninit<ConsCell>` slots and remain exclusively owned by this
    /// context for its lifetime.
    pub unsafe fn new(
        heap: *mut MaybeUninit<ConsCell>,
        capacity: usize,
        failure_handler: FailureHandler,
    ) -> Self {
        Self {
            heap,
            capacity,
            len: 0,
            failure_handler,
        }
    }

    pub const fn len(&self) -> usize {
        self.len
    }

    pub const fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn cons(&mut self, car: Word, cdr: Word) -> Result<Word, RuntimeError> {
        if self.len == self.capacity {
            return Err(RuntimeError::OutOfMemory);
        }
        if self.heap.is_null() {
            return Err(RuntimeError::AbiViolation);
        }
        // SAFETY: constructor contract provides `capacity` writable slots;
        // the bound above proves this slot is in range and still uninitialized.
        let slot = unsafe { self.heap.add(self.len) };
        // SAFETY: `slot` is valid and uniquely owned by this context.
        unsafe { slot.write(MaybeUninit::new(ConsCell { car, cdr })) };
        self.len += 1;
        let word = slot.cast::<ConsCell>() as Word;
        if !wsm_os_target::is_aligned_cons_pointer(word) {
            return Err(RuntimeError::AbiViolation);
        }
        Ok(word)
    }

    pub fn cell(&self, pair: Word) -> Result<&ConsCell, RuntimeError> {
        if !wsm_os_target::is_aligned_cons_pointer(pair) || self.heap.is_null() {
            return Err(RuntimeError::Type);
        }
        let start = self.heap as usize;
        let address = usize::try_from(pair).map_err(|_| RuntimeError::Type)?;
        let offset = address.checked_sub(start).ok_or(RuntimeError::Type)?;
        if !offset.is_multiple_of(core::mem::size_of::<ConsCell>()) {
            return Err(RuntimeError::Type);
        }
        let index = offset / core::mem::size_of::<ConsCell>();
        if index >= self.len {
            return Err(RuntimeError::Type);
        }
        // SAFETY: range/alignment checks prove this is one of the `len`
        // initialized cells, and the shared borrow prevents mutation here.
        Ok(unsafe { (&*self.heap.add(index)).assume_init_ref() })
    }

    pub fn car(&self, pair: Word) -> Result<Word, RuntimeError> {
        Ok(self.cell(pair)?.car)
    }

    pub fn cdr(&self, pair: Word) -> Result<Word, RuntimeError> {
        Ok(self.cell(pair)?.cdr)
    }

    pub fn eq(&self, left: Word, right: Word) -> Result<Word, RuntimeError> {
        if self.classify(left)? == ValueClass::Cons || self.classify(right)? == ValueClass::Cons {
            return Err(RuntimeError::Type);
        }
        Ok(if left == right { TRUE } else { NIL })
    }

    pub fn atom(&self, value: Word) -> Result<Word, RuntimeError> {
        Ok(if self.classify(value)? == ValueClass::Cons {
            NIL
        } else {
            TRUE
        })
    }

    fn classify(&self, value: Word) -> Result<ValueClass, RuntimeError> {
        match value & wsm_os_target::TAG_MASK {
            tag if tag == wsm_os_target::Tag::Cons as Word => {
                self.cell(value)?;
                Ok(ValueClass::Cons)
            }
            tag if tag == wsm_os_target::Tag::Nil as Word && value == NIL => Ok(ValueClass::Atom),
            tag if tag == wsm_os_target::Tag::True as Word && value == TRUE => Ok(ValueClass::Atom),
            tag if tag == wsm_os_target::Tag::Fixnum as Word
                && wsm_os_target::decode_fixnum(value).is_some() =>
            {
                Ok(ValueClass::Atom)
            }
            tag if tag == wsm_os_target::Tag::Symbol as Word
                && wsm_os_target::decode_symbol(value).is_some() =>
            {
                Ok(ValueClass::Atom)
            }
            _ => Err(RuntimeError::AbiViolation),
        }
    }

    fn fail(&self, error: RuntimeError) -> ! {
        (self.failure_handler)(error.code() as u32)
    }
}

unsafe fn context_mut<'a>(context: *mut RuntimeContext) -> &'a mut RuntimeContext {
    // SAFETY: every exported ABI function requires the target contract's
    // non-null, exclusively borrowed context pointer.
    unsafe { context.as_mut() }.unwrap_or_else(|| panic_context())
}

#[cold]
fn panic_context() -> ! {
    // A null context has no failure callback. Abort is supplied by the final
    // boot/host wrapper; reaching this is an ABI violation by the caller.
    loop {
        core::hint::spin_loop();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_cons(context: *mut RuntimeContext, car: Word, cdr: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .cons(car, cdr)
        .unwrap_or_else(|error| context.fail(error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_car(context: *mut RuntimeContext, pair: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .car(pair)
        .unwrap_or_else(|error| context.fail(error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_cdr(context: *mut RuntimeContext, pair: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .cdr(pair)
        .unwrap_or_else(|error| context.fail(error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_eq(context: *mut RuntimeContext, left: Word, right: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .eq(left, right)
        .unwrap_or_else(|error| context.fail(error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_atom(context: *mut RuntimeContext, value: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .atom(value)
        .unwrap_or_else(|error| context.fail(error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_fail(context: *mut RuntimeContext, error_code: u32) -> ! {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    (context.failure_handler)(error_code)
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn unexpected_failure(_code: u32) -> ! {
        panic!("unexpected ABI failure")
    }

    fn context<const N: usize>(heap: &mut [MaybeUninit<ConsCell>; N]) -> RuntimeContext {
        // SAFETY: the array supplies exactly N aligned, writable slots and
        // outlives the returned context used by each test.
        unsafe { RuntimeContext::new(heap.as_mut_ptr(), N, unexpected_failure) }
    }

    #[test]
    fn bounded_heap_never_wraps() {
        let mut heap = [MaybeUninit::uninit(); 2];
        let mut runtime = context(&mut heap);
        assert!(runtime.cons(NIL, NIL).is_ok());
        assert!(runtime.cons(TRUE, NIL).is_ok());
        assert_eq!(runtime.cons(NIL, NIL), Err(RuntimeError::OutOfMemory));
        assert_eq!(runtime.len(), 2);
    }

    #[test]
    fn cons_car_cdr_and_atom_share_one_checked_heap() {
        let mut heap = [MaybeUninit::uninit(); 2];
        let mut runtime = context(&mut heap);
        let pair = runtime.cons(TRUE, NIL).unwrap();
        assert_eq!(runtime.car(pair), Ok(TRUE));
        assert_eq!(runtime.cdr(pair), Ok(NIL));
        assert_eq!(runtime.atom(pair), Ok(NIL));
        assert_eq!(runtime.atom(TRUE), Ok(TRUE));
        assert_eq!(runtime.car(0), Err(RuntimeError::Type));

        let mut foreign_heap = [MaybeUninit::<ConsCell>::uninit(); 1];
        let foreign_pointer = foreign_heap.as_mut_ptr().cast::<ConsCell>() as Word;
        assert!(wsm_os_target::is_aligned_cons_pointer(foreign_pointer));
        assert_eq!(runtime.car(foreign_pointer), Err(RuntimeError::Type));
        assert_eq!(runtime.car(pair + 8), Err(RuntimeError::Type));
    }

    #[test]
    fn eq_is_atomic_identity_and_rejects_pairs() {
        let mut heap = [MaybeUninit::uninit(); 1];
        let mut runtime = context(&mut heap);
        assert_eq!(runtime.eq(TRUE, TRUE), Ok(TRUE));
        assert_eq!(runtime.eq(TRUE, NIL), Ok(NIL));
        let pair = runtime.cons(TRUE, NIL).unwrap();
        assert_eq!(runtime.eq(pair, pair), Err(RuntimeError::Type));
    }

    #[test]
    fn reserved_and_malformed_immediates_fail_closed() {
        let mut heap = [MaybeUninit::uninit(); 1];
        let runtime = context(&mut heap);
        assert_eq!(runtime.atom(5), Err(RuntimeError::AbiViolation));
        assert_eq!(runtime.atom(9), Err(RuntimeError::AbiViolation));
        assert_eq!(runtime.atom(4), Err(RuntimeError::AbiViolation));
    }
}
