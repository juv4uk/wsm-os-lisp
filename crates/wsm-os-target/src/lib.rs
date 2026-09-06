#![no_std]

//! Machine-readable target ABI shared by CML emission and the wsm-os runtime.
//!
//! This crate defines an independent freestanding representation. It is not
//! Rust's `my_lisp::Value` layout and it does not inherit host pointers from
//! `my_lisp::layout::NanBox`.

pub const CONTRACT_SCHEMA: &str = "wsm-os-target-v1";
pub const CONTRACT_VERSION: u16 = 2;
pub const ARCHITECTURE: &str = "x86_64";
pub const ENDIANNESS: &str = "little";
pub const WORD_BITS: u8 = 64;
pub const POINTER_BITS: u8 = 64;
pub const TAG_BITS: u8 = 3;
pub const TAG_MASK: Word = (1 << TAG_BITS) - 1;
pub const PAYLOAD_BITS: u8 = WORD_BITS - TAG_BITS;

pub type Word = u64;

/// Bounded closure descriptor owned by the active runtime closure arena.
/// `definition_id` is image-local; `environment_ref` is an owned WSM value.
#[repr(C, align(16))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClosureDescriptor {
    pub definition_id: u32,
    pub environment_ref: Word,
}

impl ClosureDescriptor {
    #[inline(always)]
    pub const fn new(definition_id: u32, environment_ref: Word) -> Self {
        Self {
            definition_id,
            environment_ref,
        }
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tag {
    Cons = 0,
    Nil = 1,
    True = 2,
    Fixnum = 3,
    Symbol = 4,
    Closure = 5,
    Capability = 6,
}

pub const NIL: Word = Tag::Nil as Word;
pub const TRUE: Word = Tag::True as Word;
pub const FIXNUM_MIN: i64 = -(1_i64 << (PAYLOAD_BITS - 1));
pub const FIXNUM_MAX: i64 = (1_i64 << (PAYLOAD_BITS - 1)) - 1;
pub const SYMBOL_ID_MAX: Word = (1_u64 << PAYLOAD_BITS) - 1;
pub const CAPABILITY_ID_MAX: Word = (1_u64 << PAYLOAD_BITS) - 1;

/// Canonical `t` represented as Symbol(SYMBOL_ID_MAX) sentinel.
pub const CANONICAL_T: Word = (SYMBOL_ID_MAX << TAG_BITS) | Tag::Symbol as Word;


pub const CONS_ALIGNMENT: usize = 16;
pub const CONS_BYTES: usize = 16;
pub const CONS_CAR_OFFSET: usize = 0;
pub const CONS_CDR_OFFSET: usize = 8;
pub const CLOSURE_ALIGNMENT: usize = 16;
pub const CLOSURE_BYTES: usize = 16;
pub const CLOSURE_DEFINITION_ID_OFFSET: usize = 0;
pub const CLOSURE_ENVIRONMENT_REF_OFFSET: usize = 8;

pub const CALLING_CONVENTION: &str = "sysv-amd64-integer";
pub const ENTRY_SYMBOL: &str = "wsm_entry";
pub const ENTRY_CONTEXT_REGISTER: &str = "rdi";
pub const RESULT_REGISTER: &str = "rax";
pub const STACK_ALIGNMENT_BEFORE_CALL: usize = 16;
pub const RED_ZONE_ALLOWED: bool = false;

pub const RUNTIME_IMPORTS: &[&str] = &[
    "wsm_cons",
    "wsm_car",
    "wsm_cdr",
    "wsm_eq",
    "wsm_atom",
    "wsm_closure_new",
    "wsm_closure_definition",
    "wsm_closure_environment",
    "wsm_pci_config_capability",
    "wsm_pci_config_read16",
    "wsm_mmio_capability",
    "wsm_mmio_read32",
    "wsm_mmio_write32",
    "wsm_fail",
];

#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    OutOfMemory = 1,
    Type = 2,
    InvalidSymbol = 3,
    AbiViolation = 4,
    NumericOverflow = 5,
}

pub const MY_LISP_CONTRACT: &str = "3.0";
pub const MY_LISP_SHA: &str = "667b587394dc8d3fc8dadff7c925e5bce68ed887";
pub const CML_CLAIMED_CONTRACT: &str = "2.0";
pub const CML_SHA: &str = "7adfd0b8ae7bbc092af861c80b3cea433e2eba58";
pub const FIRST_FIXTURE_SOURCE: &str = "(cons (quote A) (quote B))";
pub const FIRST_FIXTURE_EXPECTED: &str = "(A . B)";

/// Encode a signed 61-bit fixnum. Values outside the target ABI fail closed.
pub const fn encode_fixnum(value: i64) -> Option<Word> {
    if value < FIXNUM_MIN || value > FIXNUM_MAX {
        None
    } else {
        Some(((value as Word) << TAG_BITS) | Tag::Fixnum as Word)
    }
}

pub const fn decode_fixnum(word: Word) -> Option<i64> {
    if tag(word) == Tag::Fixnum as Word {
        Some((word as i64) >> TAG_BITS)
    } else {
        None
    }
}

/// Encode a non-zero image-local interned symbol id.
pub const fn encode_symbol(id: Word) -> Option<Word> {
    if id == 0 || id > SYMBOL_ID_MAX {
        None
    } else {
        Some((id << TAG_BITS) | Tag::Symbol as Word)
    }
}

pub const fn decode_symbol(word: Word) -> Option<Word> {
    if tag(word) == Tag::Symbol as Word {
        let id = word >> TAG_BITS;
        if id != 0 {
            return Some(id);
        }
    }
    None
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CapabilityKind {
    PciConfig = 1,
    Mmio = 2,
    Dma = 3,
    Interrupt = 4,
}

pub const CAPABILITY_KIND_BITS: u8 = 8;
pub const CAPABILITY_INSTANCE_BITS: u8 = 8;
pub const CAPABILITY_NONCE_BITS: u8 = PAYLOAD_BITS - CAPABILITY_KIND_BITS - CAPABILITY_INSTANCE_BITS; // 61 - 16 = 45 bits

pub const CAPABILITY_KIND_MASK: Word = (1 << CAPABILITY_KIND_BITS) - 1;
pub const CAPABILITY_INSTANCE_MASK: Word = (1 << CAPABILITY_INSTANCE_BITS) - 1;
pub const CAPABILITY_NONCE_MAX: Word = (1 << CAPABILITY_NONCE_BITS) - 1;

/// Bounded, unforgeable capability descriptor carrying kind, instance, and provenance nonce.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapabilityDescriptor {
    pub kind: CapabilityKind,
    pub instance: u8,
    pub nonce: Word,
}

impl CapabilityDescriptor {
    pub const fn new(kind: CapabilityKind, instance: u8, nonce: Word) -> Option<Self> {
        if nonce == 0 || nonce > CAPABILITY_NONCE_MAX {
            None
        } else {
            Some(Self {
                kind,
                instance,
                nonce,
            })
        }
    }

    pub const fn to_id(self) -> Word {
        let kind_bits = (self.kind as Word) & CAPABILITY_KIND_MASK;
        let instance_bits = (self.instance as Word) & CAPABILITY_INSTANCE_MASK;
        (self.nonce << (CAPABILITY_KIND_BITS + CAPABILITY_INSTANCE_BITS))
            | (instance_bits << CAPABILITY_KIND_BITS)
            | kind_bits
    }

    pub const fn from_id(id: Word) -> Option<Self> {
        let kind_raw = (id & CAPABILITY_KIND_MASK) as u8;
        let instance = ((id >> CAPABILITY_KIND_BITS) & CAPABILITY_INSTANCE_MASK) as u8;
        let nonce = id >> (CAPABILITY_KIND_BITS + CAPABILITY_INSTANCE_BITS);
        let kind = match kind_raw {
            1 => CapabilityKind::PciConfig,
            2 => CapabilityKind::Mmio,
            3 => CapabilityKind::Dma,
            4 => CapabilityKind::Interrupt,
            _ => return None,
        };
        if nonce == 0 || nonce > CAPABILITY_NONCE_MAX {
            None
        } else {
            Some(Self {
                kind,
                instance,
                nonce,
            })
        }
    }
}

/// Encode a non-zero image-local capability handle. The numeric handle is not
/// authority by itself: every privileged ABI import must validate it against
/// the capabilities provisioned by the machine substrate.
#[inline(always)]
pub const fn encode_capability(id: Word) -> Option<Word> {
    if id == 0 || id > CAPABILITY_ID_MAX {
        None
    } else {
        Some((id << TAG_BITS) | Tag::Capability as Word)
    }
}

#[inline(always)]
pub const fn decode_capability(word: Word) -> Option<Word> {
    if tag(word) == Tag::Capability as Word {
        let id = word >> TAG_BITS;
        if id != 0 {
            return Some(id);
        }
    }
    None
}

/// Encode a verified capability descriptor into an opaque capability Word.
#[inline(always)]
pub const fn encode_capability_descriptor(descriptor: CapabilityDescriptor) -> Option<Word> {
    encode_capability(descriptor.to_id())
}

/// Decode and validate the internal capability descriptor from a capability Word.
#[inline(always)]
pub const fn decode_capability_descriptor(word: Word) -> Option<CapabilityDescriptor> {
    if let Some(id) = decode_capability(word) {
        CapabilityDescriptor::from_id(id)
    } else {
        None
    }
}

pub const fn tag(word: Word) -> Word {
    word & TAG_MASK
}

/// Structural cons-pointer check. Heap ownership/range is a runtime check.
pub const fn is_aligned_cons_pointer(word: Word) -> bool {
    word != 0 && tag(word) == Tag::Cons as Word && word.is_multiple_of(CONS_ALIGNMENT as Word)
}

/// Tag an aligned runtime-owned descriptor pointer as a closure value.
#[inline(always)]
pub const fn encode_closure_pointer(pointer: Word) -> Option<Word> {
    if pointer != 0 && pointer.is_multiple_of(CLOSURE_ALIGNMENT as Word) {
        Some(pointer | Tag::Closure as Word)
    } else {
        None
    }
}

/// Recover the untagged descriptor address. Arena ownership remains a runtime check.
#[inline(always)]
pub const fn decode_closure_pointer(word: Word) -> Option<Word> {
    if tag(word) == Tag::Closure as Word {
        Some(word & !TAG_MASK)
    } else {
        None
    }
}

pub const fn is_false(word: Word) -> bool {
    word == NIL
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use std::format;
    use std::string::String;

    #[test]
    fn fixnum_boundaries_round_trip() {
        for value in [FIXNUM_MIN, -1, 0, 1, FIXNUM_MAX] {
            let encoded = encode_fixnum(value).expect("boundary must encode");
            assert_eq!(decode_fixnum(encoded), Some(value));
        }
        assert_eq!(encode_fixnum(FIXNUM_MIN - 1), None);
        assert_eq!(encode_fixnum(FIXNUM_MAX + 1), None);
    }

    #[test]
    fn symbols_are_non_zero_image_local_ids() {
        assert_eq!(encode_symbol(0), None);
        assert_eq!(decode_symbol(encode_symbol(1).unwrap()), Some(1));
        assert_eq!(
            decode_symbol(encode_symbol(SYMBOL_ID_MAX).unwrap()),
            Some(SYMBOL_ID_MAX)
        );
    }

    #[test]
    fn capabilities_are_distinct_non_zero_handles() {
        assert_eq!(encode_capability(0), None);
        let capability = encode_capability(1).unwrap();
        assert_eq!(decode_capability(capability), Some(1));
        assert_eq!(decode_fixnum(capability), None);
        assert_eq!(decode_symbol(capability), None);
        assert_eq!(decode_capability(TRUE), None);
    }

    #[test]
    fn capability_descriptors_round_trip_and_reject_forgery() {
        let desc = CapabilityDescriptor::new(CapabilityKind::PciConfig, 0, 0x1234_5678).unwrap();
        let word = encode_capability_descriptor(desc).unwrap();
        assert_eq!(decode_capability_descriptor(word), Some(desc));

        // Different kind
        let mmio_desc = CapabilityDescriptor::new(CapabilityKind::Mmio, 1, 0x1234_5678).unwrap();
        let mmio_word = encode_capability_descriptor(mmio_desc).unwrap();
        assert_ne!(word, mmio_word);
        let decoded_mmio = decode_capability_descriptor(mmio_word).unwrap();
        assert_eq!(decoded_mmio.kind, CapabilityKind::Mmio);
        assert_eq!(decoded_mmio.instance, 1);

        // Zero or overflowing nonce fails
        assert_eq!(CapabilityDescriptor::new(CapabilityKind::PciConfig, 0, 0), None);
        assert_eq!(
            CapabilityDescriptor::new(CapabilityKind::PciConfig, 0, CAPABILITY_NONCE_MAX + 1),
            None
        );

        // Invalid kind rejected in from_id
        assert_eq!(CapabilityDescriptor::from_id(0), None);
        // Nonce is 0 in from_id
        assert_eq!(CapabilityDescriptor::from_id(1), None);
    }

    #[test]
    fn truth_and_pointer_shapes_are_distinct() {
        assert!(is_false(NIL));
        assert!(!is_false(TRUE));
        assert!(!is_false(encode_fixnum(0).unwrap()));
        assert!(!is_aligned_cons_pointer(0));
        assert!(is_aligned_cons_pointer(0x1000));
        assert!(!is_aligned_cons_pointer(0x1008));
    }

    #[test]
    fn closure_descriptor_is_metadata_not_a_runtime_value() {
        let descriptor = ClosureDescriptor::new(7, NIL);
        assert_eq!(descriptor.definition_id, 7);
        assert_eq!(descriptor.environment_ref, NIL);
        assert_eq!(core::mem::size_of::<ClosureDescriptor>(), 16);
    }

    #[test]
    fn closure_pointer_tag_round_trips_without_claiming_ownership() {
        let encoded = encode_closure_pointer(0x1000).unwrap();
        assert_eq!(tag(encoded), Tag::Closure as Word);
        assert_eq!(decode_closure_pointer(encoded), Some(0x1000));
        assert_eq!(encode_closure_pointer(0), None);
        assert_eq!(encode_closure_pointer(0x1008), None);
        assert_eq!(decode_closure_pointer(TRUE), None);
    }

    #[test]
    fn tag_values_are_unique_and_fit_mask() {
        let tags = [
            Tag::Cons,
            Tag::Nil,
            Tag::True,
            Tag::Fixnum,
            Tag::Symbol,
            Tag::Closure,
            Tag::Capability,
        ];
        for (index, left) in tags.iter().enumerate() {
            assert!((*left as Word) <= TAG_MASK);
            for right in &tags[index + 1..] {
                assert_ne!(*left as u8, *right as u8);
            }
        }
    }

    #[test]
    fn committed_wsm_projection_is_current() {
        assert_eq!(
            include_str!("../../../target-contract.wsm"),
            render_contract()
        );
    }

    fn render_contract() -> String {
        format!(
            "; generated projection of crates/wsm-os-target; do not edit numeric values by hand\n\
((kind . wsm-os-target-contract)\n\
 (schema . \"{CONTRACT_SCHEMA}\")\n\
 (version . {CONTRACT_VERSION})\n\
 (architecture . {ARCHITECTURE})\n\
 (endianness . {ENDIANNESS})\n\
 (word . ((bits . {WORD_BITS}) (pointer-bits . {POINTER_BITS}) (tag-bits . {TAG_BITS}) (tag-mask . {TAG_MASK}) (payload-bits . {PAYLOAD_BITS})))\n\
 (tags . ((cons . {}) (nil . {}) (true . {}) (fixnum . {}) (symbol . {}) (closure . {}) (capability . {})))\n\
 (immediates . ((nil . {NIL}) (true . {TRUE})))\n\
 (fixnum . ((minimum . {FIXNUM_MIN}) (maximum . {FIXNUM_MAX}) (encoding . signed-shift-left-3-or-tag)))\n\
 (symbol . ((minimum-id . 1) (maximum-id . {SYMBOL_ID_MAX}) (scope . image-local-interned)))\n\
 (cons . ((bytes . {CONS_BYTES}) (alignment . {CONS_ALIGNMENT}) (car-offset . {CONS_CAR_OFFSET}) (cdr-offset . {CONS_CDR_OFFSET}) (zero-pointer . invalid) (ownership . bounded-runtime-heap)))\n\
 (closure . ((bytes . {CLOSURE_BYTES}) (alignment . {CLOSURE_ALIGNMENT}) (definition-id-offset . {CLOSURE_DEFINITION_ID_OFFSET}) (environment-ref-offset . {CLOSURE_ENVIRONMENT_REF_OFFSET}) (definition-scope . image-local) (ownership . bounded-runtime-closure-arena)))\n\
 (capability . ((minimum-id . 1) (maximum-id . {CAPABILITY_ID_MAX}) (scope . boot-provisioned) (forgeable-by-wsm . false) (privileged-use . runtime-validated)))\n\
 (calling-convention . ((name . {CALLING_CONVENTION}) (entry . {ENTRY_SYMBOL}) (context-register . {ENTRY_CONTEXT_REGISTER}) (result-register . {RESULT_REGISTER}) (stack-alignment-before-call . {STACK_ALIGNMENT_BEFORE_CALL}) (red-zone . forbidden)))\n\
 (runtime-imports . (wsm_cons wsm_car wsm_cdr wsm_eq wsm_atom wsm_closure_new wsm_closure_definition wsm_closure_environment wsm_pci_config_capability wsm_pci_config_read16 wsm_fail))\n\
 (errors . ((out-of-memory . {}) (type . {}) (invalid-symbol . {}) (abi-violation . {})))\n\
 (truth . ((false-value . nil) (fixnum-zero . true)))\n\
 (authority . ((my-lisp-contract . \"{MY_LISP_CONTRACT}\") (my-lisp-sha . \"{MY_LISP_SHA}\") (cml-claimed-contract . \"{CML_CLAIMED_CONTRACT}\") (cml-sha . \"{CML_SHA}\")))\n\
 (first-fixture . ((source . \"{FIRST_FIXTURE_SOURCE}\") (expected . \"{FIRST_FIXTURE_EXPECTED}\"))))\n",
            Tag::Cons as u8,
            Tag::Nil as u8,
            Tag::True as u8,
            Tag::Fixnum as u8,
            Tag::Symbol as u8,
            Tag::Closure as u8,
            Tag::Capability as u8,
            ErrorCode::OutOfMemory as u32,
            ErrorCode::Type as u32,
            ErrorCode::InvalidSymbol as u32,
            ErrorCode::AbiViolation as u32,
        )
    }
}
