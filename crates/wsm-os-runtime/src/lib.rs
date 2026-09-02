#![no_std]

//! Allocation-bounded runtime core for CML-generated `wsm-os` objects.
//!
//! The core owns no host services. Its only storage is a caller-provided,
//! 16-byte-aligned cons arena. Hosted startup/printing and future boot I/O are
//! wrappers around this same ABI implementation.

use core::mem::MaybeUninit;
use wsm_os_target::{
    ClosureDescriptor, ErrorCode, NIL, RESULT_REGISTER, RUNTIME_IMPORTS, SYMBOL_ID_MAX, TRUE,
    Word, encode_symbol,
};

/// Canonical `t`, as an ordinary interned Symbol -- not the standalone
/// `Tag::True` primitive canonical WSM never had (`t` is plain
/// `Symbol("t")` in the Rust oracle, not a distinct primitive). 2026-09-02
/// owner directive: "() не визначаємо... t має пройти тим самим шляхом, що
/// й будь-який інший Symbol." `wsm-os-target`'s symbol ids are documented
/// as image-local-interned (each compiled program gets its own sequential
/// ids), so there is no single canonical id for `t` shared across programs
/// the way a frozen global symbol table would provide -- `SYMBOL_ID_MAX` is
/// reserved as a sentinel here, matching `wsm-my-lisp/asm/nucleus.s`'s own
/// `SYM_T_WORD` fix, making collision with a real per-program-interned id
/// practically unreachable but not a proven-unique encoding. `Tag::True`
/// itself stays declared in `wsm_os_target::Tag` for now (a separate,
/// bigger question); nothing in this crate produces it anymore.
const CANONICAL_T: Word = match encode_symbol(SYMBOL_ID_MAX) {
    Some(word) => word,
    None => unreachable!(),
};

/// `RuntimeContext::new`/`new_with_closures`'s safety contract requires each
/// arena to be exclusively owned by exactly one live context. That contract
/// used to be caller-enforced prose only. This is a real, checked guard
/// against the specific danger (two live contexts over the *same* arena
/// pointer) rather than a global single-context limit, so it doesn't break
/// legitimate concurrent contexts over distinct arenas (parallel unit
/// tests, or a future host running more than one independent context).
/// Capacity is generous for that reason, not because deep concurrency is
/// expected on the bare-metal target this crate ships to.
///
/// Deliberately plain `usize`, not `AtomicUsize`: this `no_std` target's
/// symbol-purity gate (`scripts/check-runtime-symbols.sh`) builds
/// unoptimized, where every `core::sync::atomic` operation -- even a bare
/// `load` -- lowers to an unapproved external `core::sync::atomic::atomic_*`
/// intrinsic call instead of a single inlined instruction. Plain reads/
/// writes match the rest of this crate's synchronization story: production
/// use is single-threaded bare metal (so is every other piece of state
/// here, including `RuntimeContext` itself). See `claim_arena`'s SAFETY
/// comment for the one place a real second OS thread touches this array
/// (this crate's own regression test) and why that's still race-free.
const MAX_TRACKED_ARENAS: usize = 32;
static mut LIVE_ARENAS: [usize; MAX_TRACKED_ARENAS] = [0; MAX_TRACKED_ARENAS];

/// Registers `addr` as a live arena, halting (see `arena_violation`) if it
/// is already registered (the exact violation `RuntimeContext::new`'s
/// safety contract forbids) or if the tracking registry is full. A null
/// address (an absent, unused closure arena) is never tracked.
fn claim_arena(addr: usize) {
    if addr == 0 {
        return;
    }
    // SAFETY: raw, unsynchronized access to LIVE_ARENAS -- sound because
    // production use never has two threads at all, and this crate's own
    // regression test proving arena_violation() fires performs every write
    // to this array (claiming the first context's arena) strictly before
    // calling `std::thread::spawn` for the second, violating attempt;
    // `thread::spawn` is documented to establish a happens-before edge for
    // everything before it, so that later thread's read is never racing a
    // concurrent write, even without atomics. Pointer arithmetic (not slice
    // indexing) throughout, matching this file's existing raw-pointer style
    // (e.g. `self.closure_heap.add(self.closure_len)` below), so an
    // in-bounds access never risks an unapproved bounds-check-panic symbol.
    unsafe {
        let base = core::ptr::addr_of_mut!(LIVE_ARENAS).cast::<usize>();
        let mut free_index = MAX_TRACKED_ARENAS;
        let mut i = 0usize;
        while i < MAX_TRACKED_ARENAS {
            let slot = base.add(i);
            let current = *slot;
            if current == addr {
                arena_violation();
            }
            if current == 0 && free_index == MAX_TRACKED_ARENAS {
                free_index = i;
            }
            i += 1;
        }
        if free_index == MAX_TRACKED_ARENAS {
            arena_violation();
        }
        *base.add(free_index) = addr;
    }
}

#[cold]
fn arena_violation() -> ! {
    // Either a live arena pointer collided with another live context's
    // arena (the exact violation RuntimeContext::new's safety contract
    // forbids), or the tracking registry (MAX_TRACKED_ARENAS) is full. No
    // RuntimeContext exists yet at this point (arena registration happens
    // before construction finishes) to route a structured failure through,
    // and -- like panic_context below -- the freestanding runtime must not
    // pull in panic_fmt, so this can only spin.
    loop {
        core::hint::spin_loop();
    }
}

/// Releases `addr` from the live-arena registry, if tracked. Called from
/// `RuntimeContext`'s `Drop` so `claim_arena` only ever rejects a genuinely
/// still-live duplicate, never a stale one from an already-dropped context.
#[inline(always)]
fn release_arena(addr: usize) {
    if addr == 0 {
        return;
    }
    // SAFETY: see claim_arena above -- same single-writer-then-spawn
    // discipline, and this function is never the racing side of that test.
    unsafe {
        let base = core::ptr::addr_of_mut!(LIVE_ARENAS).cast::<usize>();
        let mut i = 0usize;
        while i < MAX_TRACKED_ARENAS {
            let slot = base.add(i);
            if *slot == addr {
                *slot = 0;
                return;
            }
            i += 1;
        }
    }
}

const _: () = assert!(RESULT_REGISTER.as_bytes()[0] == b'r');
const _: () = assert!(RUNTIME_IMPORTS.len() == 11);

pub type FailureHandler = extern "C" fn(context: *const RuntimeContext, code: u32) -> !;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ConditionRecord {
    pub kind: u32,
    pub source_id: u32,
    pub offending_value: Word,
}

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
    closure_heap: *mut MaybeUninit<ClosureDescriptor>,
    closure_capacity: usize,
    closure_len: usize,
    pub condition: ConditionRecord,
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
    /// context for its lifetime. This is now a checked invariant, not just a
    /// documented one: constructing a second context over the same `heap`
    /// pointer while one is still live panics (see `claim_arena` above),
    /// released again on `Drop`. Audited call graph as of 2026-09-01: the
    /// two real entry points (`wsm-os-kernel`'s `kernel_main`, registered as
    /// the single bootloader `entry_point!`, and `wsm-os-hosted`'s `main`)
    /// each construct exactly one context, once, over their own private
    /// arena, for the life of that function.
    pub unsafe fn new(
        heap: *mut MaybeUninit<ConsCell>,
        capacity: usize,
        failure_handler: FailureHandler,
    ) -> Self {
        claim_arena(heap as usize);
        Self {
            heap,
            capacity,
            len: 0,
            closure_heap: core::ptr::null_mut(),
            closure_capacity: 0,
            closure_len: 0,
            condition: ConditionRecord {
                kind: 0,
                source_id: 0,
                offending_value: 0,
            },
            failure_handler,
        }
    }

    /// Create a context with a separate bounded closure arena.
    ///
    /// # Safety
    /// Both arenas must remain valid, writable and exclusively owned for the
    /// context lifetime. They must not overlap.
    pub unsafe fn new_with_closures(
        heap: *mut MaybeUninit<ConsCell>,
        capacity: usize,
        closure_heap: *mut MaybeUninit<ClosureDescriptor>,
        closure_capacity: usize,
        failure_handler: FailureHandler,
    ) -> Self {
        let mut context = unsafe { Self::new(heap, capacity, failure_handler) };
        claim_arena(closure_heap as usize);
        context.closure_heap = closure_heap;
        context.closure_capacity = closure_capacity;
        context
    }

    pub const fn len(&self) -> usize {
        self.len
    }

    pub const fn capacity(&self) -> usize {
        self.capacity
    }

    pub const fn closure_len(&self) -> usize {
        self.closure_len
    }

    pub fn closure(
        &mut self,
        definition_id: u32,
        environment_ref: Word,
    ) -> Result<Word, RuntimeError> {
        if definition_id == 0 {
            return Err(RuntimeError::AbiViolation);
        }
        if self.closure_len == self.closure_capacity {
            return Err(RuntimeError::OutOfMemory);
        }
        if self.closure_heap.is_null() {
            return Err(RuntimeError::AbiViolation);
        }
        let slot = unsafe { self.closure_heap.add(self.closure_len) };
        unsafe {
            slot.write(MaybeUninit::new(ClosureDescriptor::new(
                definition_id,
                environment_ref,
            )))
        };
        self.closure_len += 1;
        wsm_os_target::encode_closure_pointer(slot.cast::<ClosureDescriptor>() as Word)
            .ok_or(RuntimeError::AbiViolation)
    }

    pub fn closure_descriptor(&self, closure: Word) -> Result<&ClosureDescriptor, RuntimeError> {
        let raw = wsm_os_target::decode_closure_pointer(closure).ok_or(RuntimeError::Type)?;
        if self.closure_heap.is_null() {
            return Err(RuntimeError::Type);
        }
        let start = self.closure_heap as usize;
        let address = usize::try_from(raw).map_err(|_| RuntimeError::Type)?;
        let offset = address.checked_sub(start).ok_or(RuntimeError::Type)?;
        if !offset.is_multiple_of(core::mem::size_of::<ClosureDescriptor>()) {
            return Err(RuntimeError::Type);
        }
        let index = offset / core::mem::size_of::<ClosureDescriptor>();
        if index >= self.closure_len {
            return Err(RuntimeError::Type);
        }
        Ok(unsafe { (&*self.closure_heap.add(index)).assume_init_ref() })
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
        Ok(if left == right { CANONICAL_T } else { NIL })
    }

    pub fn atom(&self, value: Word) -> Result<Word, RuntimeError> {
        Ok(if self.classify(value)? == ValueClass::Cons {
            NIL
        } else {
            CANONICAL_T
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
            tag if tag == wsm_os_target::Tag::Closure as Word => {
                self.closure_descriptor(value)?;
                Ok(ValueClass::Atom)
            }
            tag if tag == wsm_os_target::Tag::Capability as Word
                && wsm_os_target::decode_capability(value).is_some() =>
            {
                Ok(ValueClass::Atom)
            }
            _ => Err(RuntimeError::AbiViolation),
        }
    }

    fn fail(&mut self, error: RuntimeError, offending_value: Word, source_id: u32) -> ! {
        self.condition.kind = error.code() as u32;
        self.condition.offending_value = offending_value;
        self.condition.source_id = source_id;
        (self.failure_handler)(self as *const RuntimeContext, error.code() as u32)
    }
}

impl Drop for RuntimeContext {
    fn drop(&mut self) {
        release_arena(self.heap as usize);
        release_arena(self.closure_heap as usize);
    }
}

unsafe fn context_mut<'a>(context: *mut RuntimeContext) -> &'a mut RuntimeContext {
    // SAFETY: every exported ABI function requires the target contract's
    // non-null, exclusively borrowed context pointer. A null pointer is an
    // ABI violation; the freestanding runtime must not pull in panic_fmt.
    unsafe { context.as_mut() }.unwrap_or_else(|| panic_context())
}

#[cold]
fn panic_context() -> ! {
    // There is no valid RuntimeContext from which to call the configured
    // failure handler. Spin forever rather than importing host panic support;
    // boot/kernel wrappers can validate their context before entering the ABI.
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
        .unwrap_or_else(|error| context.fail(error, 0, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_car(context: *mut RuntimeContext, pair: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .car(pair)
        .unwrap_or_else(|error| context.fail(error, pair, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_cdr(context: *mut RuntimeContext, pair: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .cdr(pair)
        .unwrap_or_else(|error| context.fail(error, pair, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_eq(context: *mut RuntimeContext, left: Word, right: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .eq(left, right)
        .unwrap_or_else(|error| context.fail(error, left, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_atom(context: *mut RuntimeContext, value: Word) -> Word {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context
        .atom(value)
        .unwrap_or_else(|error| context.fail(error, value, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_closure_new(
    context: *mut RuntimeContext,
    definition_id: u32,
    environment_ref: Word,
) -> Word {
    let context = unsafe { context_mut(context) };
    context
        .closure(definition_id, environment_ref)
        .unwrap_or_else(|error| context.fail(error, environment_ref, definition_id))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_closure_definition(
    context: *mut RuntimeContext,
    closure: Word,
) -> u32 {
    let context = unsafe { context_mut(context) };
    context
        .closure_descriptor(closure)
        .map(|descriptor| descriptor.definition_id)
        .unwrap_or_else(|error| context.fail(error, closure, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_closure_environment(
    context: *mut RuntimeContext,
    closure: Word,
) -> Word {
    let context = unsafe { context_mut(context) };
    context
        .closure_descriptor(closure)
        .map(|descriptor| descriptor.environment_ref)
        .unwrap_or_else(|error| context.fail(error, closure, 0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wsm_fail(
    context: *mut RuntimeContext,
    error_code: u32,
    offending_value: Word,
    source_id: u32,
) -> ! {
    // SAFETY: guaranteed by this exported function's ABI contract.
    let context = unsafe { context_mut(context) };
    context.condition.kind = error_code;
    context.condition.offending_value = offending_value;
    context.condition.source_id = source_id;
    (context.failure_handler)(context as *const RuntimeContext, error_code)
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn unexpected_failure(_context: *const RuntimeContext, _code: u32) -> ! {
        panic!("unexpected ABI failure")
    }

    fn context<const N: usize>(heap: &mut [MaybeUninit<ConsCell>; N]) -> RuntimeContext {
        // SAFETY: the array supplies exactly N aligned, writable slots and
        // outlives the returned context used by each test.
        unsafe { RuntimeContext::new(heap.as_mut_ptr(), N, unexpected_failure) }
    }

    fn context_with_closures<const N: usize, const C: usize>(
        heap: &mut [MaybeUninit<ConsCell>; N],
        closures: &mut [MaybeUninit<ClosureDescriptor>; C],
    ) -> RuntimeContext {
        unsafe {
            RuntimeContext::new_with_closures(
                heap.as_mut_ptr(),
                N,
                closures.as_mut_ptr(),
                C,
                unexpected_failure,
            )
        }
    }

    #[test]
    fn constructing_a_second_context_over_the_same_arena_never_returns() {
        // Regression for the arena-exclusivity safety contract that used to
        // be caller-enforced prose only (see claim_arena / arena_violation /
        // RuntimeContext::new's SAFETY doc above) -- proves the specific
        // danger (two live contexts over the SAME arena) is now actually
        // caught, not just documented. arena_violation() spins forever
        // rather than panicking (the freestanding runtime must not pull in
        // panic_fmt/Display machinery -- see the ERROR: Forbidden external
        // import failures that caught the first, panic!-based version of
        // this guard in CI), so this proves it via a bounded wait for a
        // thread that must never complete, not catch_unwind.
        //
        // heap is intentionally leaked (Box::leak) and `first` is
        // intentionally forgotten (never Dropped): the point of this test is
        // that a second construction over the same arena must never return,
        // so nothing here could ever be safely freed anyway. `RuntimeContext`
        // holds raw pointers (not Send), so only the plain `usize` address
        // -- not `first` itself -- crosses into the spawned thread.
        let heap: &'static mut [MaybeUninit<ConsCell>; 4] =
            std::boxed::Box::leak(std::boxed::Box::new([MaybeUninit::<ConsCell>::uninit(); 4]));
        let heap_addr = heap.as_mut_ptr() as usize;
        let first = context(heap);
        core::mem::forget(first);

        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            // SAFETY: deliberately violating the exclusive-ownership
            // contract to prove the checked guard rejects it; `heap_addr`
            // points at the same arena `first` (forgotten, not dropped, so
            // still registered as live) was constructed over.
            let _second = unsafe {
                RuntimeContext::new(
                    heap_addr as *mut MaybeUninit<ConsCell>,
                    4,
                    unexpected_failure,
                )
            };
            // Unreachable if the guard works: arena_violation() never
            // returns, so this send never happens.
            let _ = tx.send(());
        });
        let timed_out = rx
            .recv_timeout(std::time::Duration::from_millis(500))
            .is_err();
        assert!(
            timed_out,
            "constructing a second context over the same live arena should never \
             return (arena_violation spins forever), but the second construction \
             completed"
        );
    }

    #[test]
    fn dropping_a_context_releases_its_arena_for_reuse() {
        // The exclusivity guard above must not become a permanent leak: once
        // a context legitimately goes out of scope, the same arena pointer
        // has to be constructible again.
        let mut heap = [MaybeUninit::<ConsCell>::uninit(); 4];
        drop(context(&mut heap));
        let second = context(&mut heap);
        drop(second);
    }

    #[test]
    fn closure_arena_owns_descriptor_and_rejects_foreign_values() {
        let mut heap = [MaybeUninit::uninit(); 1];
        let mut closures = [MaybeUninit::uninit(); 1];
        let mut runtime = context_with_closures(&mut heap, &mut closures);
        let environment = runtime.cons(TRUE, NIL).unwrap();
        let closure = runtime.closure(7, environment).unwrap();
        let descriptor = runtime.closure_descriptor(closure).unwrap();
        assert_eq!(descriptor.definition_id, 7);
        assert_eq!(descriptor.environment_ref, environment);
        assert_eq!(runtime.atom(closure), Ok(CANONICAL_T));
        assert_eq!(runtime.closure(8, NIL), Err(RuntimeError::OutOfMemory));
        assert_eq!(runtime.closure_descriptor(TRUE), Err(RuntimeError::Type));

        let mut foreign = [MaybeUninit::<ClosureDescriptor>::uninit(); 1];
        let foreign_value = wsm_os_target::encode_closure_pointer(
            foreign.as_mut_ptr().cast::<ClosureDescriptor>() as Word,
        )
        .unwrap();
        assert_eq!(
            runtime.closure_descriptor(foreign_value),
            Err(RuntimeError::Type)
        );
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
        assert_eq!(runtime.atom(TRUE), Ok(CANONICAL_T));
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
        assert_eq!(runtime.eq(TRUE, TRUE), Ok(CANONICAL_T));
        assert_eq!(runtime.eq(TRUE, NIL), Ok(NIL));
        let capability = wsm_os_target::encode_capability(1).unwrap();
        assert_eq!(runtime.atom(capability), Ok(CANONICAL_T));
        assert_eq!(runtime.eq(capability, capability), Ok(CANONICAL_T));
        let pair = runtime.cons(TRUE, NIL).unwrap();
        assert_eq!(runtime.eq(pair, pair), Err(RuntimeError::Type));
    }

    #[test]
    fn reserved_and_malformed_immediates_fail_closed() {
        let mut heap = [MaybeUninit::uninit(); 1];
        let runtime = context(&mut heap);
        assert_eq!(runtime.atom(5), Err(RuntimeError::Type));
        assert_eq!(runtime.atom(6), Err(RuntimeError::AbiViolation));
        assert_eq!(runtime.atom(9), Err(RuntimeError::AbiViolation));
        assert_eq!(runtime.atom(4), Err(RuntimeError::AbiViolation));
    }
}
