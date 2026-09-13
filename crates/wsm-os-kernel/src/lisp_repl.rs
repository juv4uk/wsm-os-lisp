// Pure, bounded bare-metal Lisp REPL for WSM-OS.
//
// Adheres to ADR-003 and Lisp Machine principles:
// 1. Tag-driven semantic dispatch over 64-bit tagged Words.
// 2. Bounded cons-arena allocation via RuntimeContext (no host std/alloc).
// 3. Recursive-descent S-expression reader with dotted pair and quote support.
// 4. Evaluator with lexical environments, closures, primitives, and arithmetic.
// 5. Dual English and Ukrainian surface vocabulary.

use wsm_os_runtime::RuntimeContext;
use wsm_os_target::{
    decode_fixnum, decode_symbol, encode_fixnum, encode_symbol, Tag, Word,
    CANONICAL_T, NIL, TAG_MASK,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReplError {
    Empty,
    UnexpectedEof,
    UnexpectedCloseParen,
    InvalidToken,
    NumericOverflow,
    SymbolTableFull,
    TypeMismatch,
    UnboundSymbol,
    UndefinedFunction,
    WrongArgCount,
    OutOfMemory,
}

impl ReplError {
    pub fn as_str(self) -> &'static [u8] {
        match self {
            Self::Empty => b"EMPTY",
            Self::UnexpectedEof => b"UNEXPECTED_EOF",
            Self::UnexpectedCloseParen => b"UNEXPECTED_CLOSE_PAREN",
            Self::InvalidToken => b"INVALID_TOKEN",
            Self::NumericOverflow => b"NUMERIC_OVERFLOW",
            Self::SymbolTableFull => b"SYMBOL_TABLE_FULL",
            Self::TypeMismatch => b"TYPE_MISMATCH",
            Self::UnboundSymbol => b"UNBOUND_SYMBOL",
            Self::UndefinedFunction => b"UNDEFINED_FUNCTION",
            Self::WrongArgCount => b"WRONG_ARG_COUNT",
            Self::OutOfMemory => b"OOM",
        }
    }
}

// Predefined core symbol IDs
pub const SYM_QUOTE: Word = 1;
pub const SYM_CONS: Word = 2;
pub const SYM_CAR: Word = 3;
pub const SYM_CDR: Word = 4;
pub const SYM_ATOM: Word = 5;
pub const SYM_EQ: Word = 6;
pub const SYM_COND: Word = 7;
pub const SYM_IF: Word = 8;
pub const SYM_DEF: Word = 9;
pub const SYM_LAMBDA: Word = 10;
pub const SYM_ADD: Word = 11;
pub const SYM_SUB: Word = 12;
pub const SYM_MUL: Word = 13;
pub const SYM_LT: Word = 14;
pub const SYM_GT: Word = 15;
pub const SYM_NUM_EQ: Word = 16;
pub const SYM_CLOSURE: Word = 17;
pub const SYM_LOGAND: Word = 18;
pub const SYM_LOGIOR: Word = 19;
pub const SYM_LOGXOR: Word = 20;
pub const SYM_ASH: Word = 21;
pub const SYM_IO_IN8: Word = 22;
pub const SYM_IO_OUT8: Word = 23;
pub const SYM_MOUSE_INIT: Word = 24;
pub const SYM_MOUSE_POS: Word = 25;
pub const SYM_MOUSE_BUTTONS: Word = 26;
pub const SYM_MOUSE_POLL: Word = 27;
pub const SYM_KBD_POLL: Word = 28;
pub const SYM_RDTSC: Word = 29;
pub const SYM_RDRAND: Word = 30;
pub const SYM_CPUID: Word = 31;
pub const SYM_CR_READ: Word = 32;
pub const SYM_MSR_READ: Word = 33;
pub const SYM_MSR_WRITE: Word = 34;
pub const SYM_PCI_READ: Word = 35;
pub const SYM_PCI_WRITE: Word = 36;
pub const SYM_MEM_READ64: Word = 37;

pub const PREDEFINED_SYMBOL_COUNT: usize = 37;

static PREDEFINED_NAMES: [&[u8]; PREDEFINED_SYMBOL_COUNT] = [
    b"quote",
    b"cons",
    b"car",
    b"cdr",
    b"atom",
    b"eq",
    b"cond",
    b"if",
    b"def",
    b"lambda",
    b"+",
    b"-",
    b"*",
    b"<",
    b">",
    b"=",
    b"#<closure>",
    b"logand",
    b"logior",
    b"logxor",
    b"ash",
    b"io-in8",
    b"io-out8",
    b"ps2-mouse-init",
    b"mouse-pos",
    b"mouse-buttons",
    b"mouse-poll",
    b"kbd-poll",
    b"rdtsc",
    b"rdrand",
    b"cpuid",
    b"cr-read",
    b"msr-read",
    b"msr-write",
    b"pci-read",
    b"pci-write",
    b"mem-read64",
];

const MAX_DYNAMIC_SYMBOLS: usize = 64;
const MAX_SYM_NAME_LEN: usize = 32;

#[derive(Clone, Copy)]
struct DynamicSymbol {
    name: [u8; MAX_SYM_NAME_LEN],
    len: usize,
}

static mut DYNAMIC_SYMBOLS: [DynamicSymbol; MAX_DYNAMIC_SYMBOLS] = [DynamicSymbol {
    name: [0; MAX_SYM_NAME_LEN],
    len: 0,
}; MAX_DYNAMIC_SYMBOLS];

static mut DYNAMIC_SYMBOL_COUNT: usize = 0;

pub static mut GLOBAL_ENV: Word = NIL;

pub fn bytes_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x == y)
}

fn intern_symbol(name: &[u8]) -> Result<Word, ReplError> {
    // Check canonical predefined English & Ukrainian names
    if bytes_eq(name, b"quote") || bytes_eq(name, "як-є".as_bytes()) {
        return Ok(SYM_QUOTE);
    }
    if bytes_eq(name, b"cons") || bytes_eq(name, "сполучити".as_bytes()) {
        return Ok(SYM_CONS);
    }
    if bytes_eq(name, b"car") || bytes_eq(name, "перше".as_bytes()) {
        return Ok(SYM_CAR);
    }
    if bytes_eq(name, b"cdr") || bytes_eq(name, "решта".as_bytes()) {
        return Ok(SYM_CDR);
    }
    if bytes_eq(name, b"atom") || bytes_eq(name, b"atom?") || bytes_eq(name, "атом?".as_bytes()) {
        return Ok(SYM_ATOM);
    }
    if bytes_eq(name, b"eq") || bytes_eq(name, b"eq?") || bytes_eq(name, "тотожне?".as_bytes()) {
        return Ok(SYM_EQ);
    }
    if bytes_eq(name, b"cond") || bytes_eq(name, "за-умовою".as_bytes()) {
        return Ok(SYM_COND);
    }
    if bytes_eq(name, b"if") || bytes_eq(name, "якщо".as_bytes()) {
        return Ok(SYM_IF);
    }
    if bytes_eq(name, b"def") || bytes_eq(name, b"define") || bytes_eq(name, "визначити".as_bytes()) {
        return Ok(SYM_DEF);
    }
    if bytes_eq(name, b"lambda") || bytes_eq(name, b"fn") || bytes_eq(name, "лямбда".as_bytes()) {
        return Ok(SYM_LAMBDA);
    }
    if bytes_eq(name, b"+") || bytes_eq(name, "додати".as_bytes()) {
        return Ok(SYM_ADD);
    }
    if bytes_eq(name, b"-") || bytes_eq(name, "відняти".as_bytes()) {
        return Ok(SYM_SUB);
    }
    if bytes_eq(name, b"*") || bytes_eq(name, "помножити".as_bytes()) {
        return Ok(SYM_MUL);
    }
    if bytes_eq(name, b"<") || bytes_eq(name, "менше?".as_bytes()) {
        return Ok(SYM_LT);
    }
    if bytes_eq(name, b">") || bytes_eq(name, "більше?".as_bytes()) {
        return Ok(SYM_GT);
    }
    if bytes_eq(name, b"=") || bytes_eq(name, "дорівнює?".as_bytes()) {
        return Ok(SYM_NUM_EQ);
    }
    if bytes_eq(name, b"logand") || bytes_eq(name, "побітове-і".as_bytes()) {
        return Ok(SYM_LOGAND);
    }
    if bytes_eq(name, b"logior") || bytes_eq(name, "побітове-або".as_bytes()) {
        return Ok(SYM_LOGIOR);
    }
    if bytes_eq(name, b"logxor") || bytes_eq(name, "побітове-виключне-або".as_bytes()) {
        return Ok(SYM_LOGXOR);
    }
    if bytes_eq(name, b"ash") || bytes_eq(name, "зсув".as_bytes()) {
        return Ok(SYM_ASH);
    }
    if bytes_eq(name, b"io-in8") || bytes_eq(name, "ввід-порт".as_bytes()) {
        return Ok(SYM_IO_IN8);
    }
    if bytes_eq(name, b"io-out8") || bytes_eq(name, "вивід-порт".as_bytes()) {
        return Ok(SYM_IO_OUT8);
    }
    if bytes_eq(name, b"ps2-mouse-init") || bytes_eq(name, "миша-ініціалізувати".as_bytes()) {
        return Ok(SYM_MOUSE_INIT);
    }
    if bytes_eq(name, b"mouse-pos") || bytes_eq(name, "миша-позиція".as_bytes()) {
        return Ok(SYM_MOUSE_POS);
    }
    if bytes_eq(name, b"mouse-buttons") || bytes_eq(name, "миша-кнопки".as_bytes()) {
        return Ok(SYM_MOUSE_BUTTONS);
    }
    if bytes_eq(name, b"mouse-poll") || bytes_eq(name, "миша-опитати".as_bytes()) {
        return Ok(SYM_MOUSE_POLL);
    }
    if bytes_eq(name, b"kbd-poll") || bytes_eq(name, "клавіатура-опитати".as_bytes()) {
        return Ok(SYM_KBD_POLL);
    }
    if bytes_eq(name, b"rdtsc") || bytes_eq(name, "лічильник-тактів".as_bytes()) {
        return Ok(SYM_RDTSC);
    }
    if bytes_eq(name, b"rdrand") || bytes_eq(name, "апаратна-випадковість".as_bytes()) {
        return Ok(SYM_RDRAND);
    }
    if bytes_eq(name, b"cpuid") || bytes_eq(name, "ідентифікатор-процесора".as_bytes()) {
        return Ok(SYM_CPUID);
    }
    if bytes_eq(name, b"cr-read") || bytes_eq(name, "зчитати-cr".as_bytes()) {
        return Ok(SYM_CR_READ);
    }
    if bytes_eq(name, b"msr-read") || bytes_eq(name, "зчитати-msr".as_bytes()) {
        return Ok(SYM_MSR_READ);
    }
    if bytes_eq(name, b"msr-write") || bytes_eq(name, "записати-msr".as_bytes()) {
        return Ok(SYM_MSR_WRITE);
    }
    if bytes_eq(name, b"pci-read") || bytes_eq(name, "зчитати-pci".as_bytes()) {
        return Ok(SYM_PCI_READ);
    }
    if bytes_eq(name, b"pci-write") || bytes_eq(name, "записати-pci".as_bytes()) {
        return Ok(SYM_PCI_WRITE);
    }
    if bytes_eq(name, b"mem-read64") || bytes_eq(name, "зчитати-памʼять".as_bytes()) {
        return Ok(SYM_MEM_READ64);
    }

    // Check dynamic symbol table
    unsafe {
        for i in 0..DYNAMIC_SYMBOL_COUNT {
            let entry = &DYNAMIC_SYMBOLS[i];
            if bytes_eq(&entry.name[..entry.len], name) {
                return Ok((PREDEFINED_SYMBOL_COUNT + 1 + i) as Word);
            }
        }
        if DYNAMIC_SYMBOL_COUNT >= MAX_DYNAMIC_SYMBOLS {
            return Err(ReplError::SymbolTableFull);
        }
        if name.len() > MAX_SYM_NAME_LEN {
            return Err(ReplError::InvalidToken);
        }
        let idx = DYNAMIC_SYMBOL_COUNT;
        let mut buf = [0_u8; MAX_SYM_NAME_LEN];
        buf[..name.len()].copy_from_slice(name);
        DYNAMIC_SYMBOLS[idx] = DynamicSymbol {
            name: buf,
            len: name.len(),
        };
        DYNAMIC_SYMBOL_COUNT += 1;
        Ok((PREDEFINED_SYMBOL_COUNT + 1 + idx) as Word)
    }
}

pub fn symbol_name(id: Word) -> Option<&'static [u8]> {
    if id >= 1 && id <= PREDEFINED_SYMBOL_COUNT as Word {
        return Some(PREDEFINED_NAMES[(id - 1) as usize]);
    }
    let dyn_idx = id.checked_sub((PREDEFINED_SYMBOL_COUNT + 1) as Word)? as usize;
    unsafe {
        if dyn_idx < DYNAMIC_SYMBOL_COUNT {
            let entry = &DYNAMIC_SYMBOLS[dyn_idx];
            // SAFETY: string bytes are static and immutable once written
            Some(core::slice::from_raw_parts(entry.name.as_ptr(), entry.len))
        } else {
            None
        }
    }
}

// ---------------------------------------------------------------------------
// S-Expression Reader
// ---------------------------------------------------------------------------

fn is_whitespace(b: u8) -> bool {
    b == b' ' || b == b'\t' || b == b'\r' || b == b'\n'
}

fn is_delimiter(b: u8) -> bool {
    is_whitespace(b) || b == b'(' || b == b')' || b == b'\'' || b == b';'
}

fn skip_whitespace_and_comments(input: &[u8], cursor: &mut usize) {
    while *cursor < input.len() {
        let b = input[*cursor];
        if is_whitespace(b) {
            *cursor += 1;
        } else if b == b';' {
            // Skip until newline or EOF
            while *cursor < input.len() && input[*cursor] != b'\n' {
                *cursor += 1;
            }
        } else {
            break;
        }
    }
}

fn parse_i64(slice: &[u8]) -> Option<i64> {
    if slice.is_empty() {
        return None;
    }
    let (neg, digits) = match slice[0] {
        b'-' => (true, &slice[1..]),
        b'+' => (false, &slice[1..]),
        _ => (false, slice),
    };
    if digits.is_empty() {
        return None;
    }
    let mut acc: i64 = 0;
    for &b in digits {
        if !b.is_ascii_digit() {
            return None;
        }
        let d = (b - b'0') as i64;
        acc = acc.checked_mul(10)?;
        if neg {
            acc = acc.checked_sub(d)?;
        } else {
            acc = acc.checked_add(d)?;
        }
    }
    Some(acc)
}

pub fn read_expr(
    input: &[u8],
    cursor: &mut usize,
    context: &mut RuntimeContext,
) -> Result<Word, ReplError> {
    skip_whitespace_and_comments(input, cursor);
    if *cursor >= input.len() {
        return Err(ReplError::Empty);
    }
    let b = input[*cursor];
    if b == b'(' {
        *cursor += 1;
        read_list(input, cursor, context)
    } else if b == b')' {
        *cursor += 1;
        Err(ReplError::UnexpectedCloseParen)
    } else if b == b'\'' {
        *cursor += 1;
        let sub = read_expr(input, cursor, context)?;
        let quote_sym = encode_symbol(SYM_QUOTE).ok_or(ReplError::SymbolTableFull)?;
        let tail = context.cons(sub, NIL).map_err(|_| ReplError::OutOfMemory)?;
        context.cons(quote_sym, tail).map_err(|_| ReplError::OutOfMemory)
    } else {
        read_atom(input, cursor)
    }
}

fn read_list(
    input: &[u8],
    cursor: &mut usize,
    context: &mut RuntimeContext,
) -> Result<Word, ReplError> {
    skip_whitespace_and_comments(input, cursor);
    if *cursor >= input.len() {
        return Err(ReplError::UnexpectedEof);
    }
    if input[*cursor] == b')' {
        *cursor += 1;
        return Ok(NIL);
    }
    if input[*cursor] == b'.' {
        *cursor += 1;
        let cdr = read_expr(input, cursor, context)?;
        skip_whitespace_and_comments(input, cursor);
        if *cursor >= input.len() || input[*cursor] != b')' {
            return Err(ReplError::UnexpectedCloseParen);
        }
        *cursor += 1;
        return Ok(cdr);
    }
    let head = read_expr(input, cursor, context)?;
    let tail = read_list(input, cursor, context)?;
    context.cons(head, tail).map_err(|_| ReplError::OutOfMemory)
}

fn read_atom(input: &[u8], cursor: &mut usize) -> Result<Word, ReplError> {
    let start = *cursor;
    while *cursor < input.len() && !is_delimiter(input[*cursor]) {
        *cursor += 1;
    }
    let token = &input[start..*cursor];
    if token.is_empty() {
        return Err(ReplError::InvalidToken);
    }
    if bytes_eq(token, b"nil") {
        return Ok(NIL);
    }
    if bytes_eq(token, b"t") {
        return Ok(CANONICAL_T);
    }
    if let Some(n) = parse_i64(token) {
        return encode_fixnum(n).ok_or(ReplError::NumericOverflow);
    }
    let id = intern_symbol(token)?;
    encode_symbol(id).ok_or(ReplError::SymbolTableFull)
}

// ---------------------------------------------------------------------------
// Evaluator
// ---------------------------------------------------------------------------

fn env_lookup(sym: Word, mut env: Word, context: &RuntimeContext) -> Option<Word> {
    while env != NIL {
        let cell = context.cell(env).ok()?;
        let binding = context.cell(cell.car).ok()?;
        if binding.car == sym {
            return Some(binding.cdr);
        }
        env = cell.cdr;
    }
    None
}

fn env_bind(
    sym: Word,
    val: Word,
    env: Word,
    context: &mut RuntimeContext,
) -> Result<Word, ReplError> {
    let pair = context.cons(sym, val).map_err(|_| ReplError::OutOfMemory)?;
    context.cons(pair, env).map_err(|_| ReplError::OutOfMemory)
}

fn is_sym_id(word: Word, expected_id: Word) -> bool {
    decode_symbol(word) == Some(expected_id)
}

pub fn eval_expr(
    expr: Word,
    env: Word,
    context: &mut RuntimeContext,
) -> Result<Word, ReplError> {
    // 1. Immediates
    if expr == NIL || expr == CANONICAL_T {
        return Ok(expr);
    }
    let tag = expr & TAG_MASK;
    if tag == Tag::Fixnum as Word {
        return Ok(expr);
    }
    // 2. Symbol lookup
    if tag == Tag::Symbol as Word {
        if let Some(id) = decode_symbol(expr) {
            if id == wsm_os_target::SYMBOL_ID_MAX {
                return Ok(CANONICAL_T);
            }
        }
        if let Some(val) = env_lookup(expr, env, context) {
            return Ok(val);
        }
        if let Some(val) = env_lookup(expr, unsafe { GLOBAL_ENV }, context) {
            return Ok(val);
        }
        return Err(ReplError::UnboundSymbol);
    }
    // 3. Cons cell / Form
    if tag == Tag::Cons as Word {
        let op = context.car(expr).map_err(|_| ReplError::TypeMismatch)?;
        let args = context.cdr(expr).map_err(|_| ReplError::TypeMismatch)?;

        // Special form: quote / як-є
        if is_sym_id(op, SYM_QUOTE) {
            return context.car(args).map_err(|_| ReplError::WrongArgCount);
        }
        // Special form: if / якщо
        if is_sym_id(op, SYM_IF) {
            let cond_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let rest = context.cdr(args).map_err(|_| ReplError::WrongArgCount)?;
            let then_expr = context.car(rest).map_err(|_| ReplError::WrongArgCount)?;
            let else_expr = match context.cdr(rest) {
                Ok(r) if r != NIL => context.car(r).unwrap_or(NIL),
                _ => NIL,
            };
            let c = eval_expr(cond_expr, env, context)?;
            return if c != NIL {
                eval_expr(then_expr, env, context)
            } else {
                eval_expr(else_expr, env, context)
            };
        }
        // Special form: cond / за-умовою
        if is_sym_id(op, SYM_COND) {
            let mut clauses = args;
            while clauses != NIL {
                let clause = context.car(clauses).map_err(|_| ReplError::WrongArgCount)?;
                let test_expr = context.car(clause).map_err(|_| ReplError::WrongArgCount)?;
                let body = context.cdr(clause).map_err(|_| ReplError::WrongArgCount)?;
                let res_test = if test_expr == CANONICAL_T || is_sym_id(test_expr, SYM_EQ) {
                    CANONICAL_T
                } else {
                    eval_expr(test_expr, env, context)?
                };
                if res_test != NIL {
                    let first_expr = context.car(body).map_err(|_| ReplError::WrongArgCount)?;
                    return eval_expr(first_expr, env, context);
                }
                clauses = context.cdr(clauses).map_err(|_| ReplError::WrongArgCount)?;
            }
            return Ok(NIL);
        }
        // Special form: def / визначити
        if is_sym_id(op, SYM_DEF) {
            let sym = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            if (sym & TAG_MASK) != Tag::Symbol as Word {
                return Err(ReplError::TypeMismatch);
            }
            let val_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let val = eval_expr(val_expr, env, context)?;
            unsafe {
                GLOBAL_ENV = env_bind(sym, val, GLOBAL_ENV, context)?;
            }
            return Ok(val);
        }
        // Special form: lambda / лямбда
        if is_sym_id(op, SYM_LAMBDA) {
            let params = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let body = context.cdr(args).map_err(|_| ReplError::WrongArgCount)?;
            let closure_sym = encode_symbol(SYM_CLOSURE).ok_or(ReplError::SymbolTableFull)?;
            // Representation: (SYM_CLOSURE params body env)
            let c3 = context.cons(env, NIL).map_err(|_| ReplError::OutOfMemory)?;
            let c2 = context.cons(body, c3).map_err(|_| ReplError::OutOfMemory)?;
            let c1 = context.cons(params, c2).map_err(|_| ReplError::OutOfMemory)?;
            return context.cons(closure_sym, c1).map_err(|_| ReplError::OutOfMemory);
        }

        // Builtin primitive applications
        if is_sym_id(op, SYM_CONS) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let a = eval_expr(a_expr, env, context)?;
            let b = eval_expr(b_expr, env, context)?;
            return context.cons(a, b).map_err(|_| ReplError::OutOfMemory);
        }
        if is_sym_id(op, SYM_CAR) {
            let p_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let p = eval_expr(p_expr, env, context)?;
            return context.car(p).map_err(|_| ReplError::TypeMismatch);
        }
        if is_sym_id(op, SYM_CDR) {
            let p_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let p = eval_expr(p_expr, env, context)?;
            return context.cdr(p).map_err(|_| ReplError::TypeMismatch);
        }
        if is_sym_id(op, SYM_ATOM) {
            let v_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let v = eval_expr(v_expr, env, context)?;
            return context.atom(v).map_err(|_| ReplError::TypeMismatch);
        }
        if is_sym_id(op, SYM_EQ) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let a = eval_expr(a_expr, env, context)?;
            let b = eval_expr(b_expr, env, context)?;
            return context.eq(a, b).map_err(|_| ReplError::TypeMismatch);
        }
        if is_sym_id(op, SYM_ADD) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let a = eval_expr(a_expr, env, context)?;
            let b = eval_expr(b_expr, env, context)?;
            let na = decode_fixnum(a).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(b).ok_or(ReplError::TypeMismatch)?;
            let sum = na.checked_add(nb).ok_or(ReplError::NumericOverflow)?;
            return encode_fixnum(sum).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_SUB) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let rest = context.cdr(args).map_err(|_| ReplError::WrongArgCount)?;
            let a = eval_expr(a_expr, env, context)?;
            let na = decode_fixnum(a).ok_or(ReplError::TypeMismatch)?;
            if rest == NIL {
                let neg = 0_i64.checked_sub(na).ok_or(ReplError::NumericOverflow)?;
                return encode_fixnum(neg).ok_or(ReplError::NumericOverflow);
            }
            let b_expr = context.car(rest).map_err(|_| ReplError::WrongArgCount)?;
            let b = eval_expr(b_expr, env, context)?;
            let nb = decode_fixnum(b).ok_or(ReplError::TypeMismatch)?;
            let diff = na.checked_sub(nb).ok_or(ReplError::NumericOverflow)?;
            return encode_fixnum(diff).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MUL) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let a = eval_expr(a_expr, env, context)?;
            let b = eval_expr(b_expr, env, context)?;
            let na = decode_fixnum(a).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(b).ok_or(ReplError::TypeMismatch)?;
            let prod = na.checked_mul(nb).ok_or(ReplError::NumericOverflow)?;
            return encode_fixnum(prod).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_LT) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return Ok(if na < nb { CANONICAL_T } else { NIL });
        }
        if is_sym_id(op, SYM_GT) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return Ok(if na > nb { CANONICAL_T } else { NIL });
        }
        if is_sym_id(op, SYM_NUM_EQ) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return Ok(if na == nb { CANONICAL_T } else { NIL });
        }
        if is_sym_id(op, SYM_LOGAND) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return encode_fixnum(na & nb).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_LOGIOR) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return encode_fixnum(na | nb).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_LOGXOR) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let nb = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            return encode_fixnum(na ^ nb).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_ASH) {
            let a_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let b_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let na = decode_fixnum(eval_expr(a_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let count = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let shifted = if count >= 0 {
                let shift = (count as u32).min(62);
                na << shift
            } else {
                let shift = ((-count) as u32).min(62);
                na >> shift
            };
            return encode_fixnum(shifted).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_IO_IN8) {
            let port_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let port_num = decode_fixnum(eval_expr(port_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = unsafe { crate::inb(port_num as u16) };
            return encode_fixnum(val as i64).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_IO_OUT8) {
            let port_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let val_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let port_num = decode_fixnum(eval_expr(port_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val_num = decode_fixnum(eval_expr(val_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            unsafe { crate::outb(port_num as u16, val_num as u8) };
            return encode_fixnum(val_num).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MOUSE_INIT) {
            let ok = crate::ps2::mouse_init();
            return Ok(if ok { CANONICAL_T } else { NIL });
        }
        if is_sym_id(op, SYM_MOUSE_POS) {
            let (mx, my) = crate::ps2::mouse_get_pos();
            let fx = encode_fixnum(mx as i64).ok_or(ReplError::NumericOverflow)?;
            let fy = encode_fixnum(my as i64).ok_or(ReplError::NumericOverflow)?;
            return context.cons(fx, fy).map_err(|_| ReplError::OutOfMemory);
        }
        if is_sym_id(op, SYM_MOUSE_BUTTONS) {
            let (l, r, m) = crate::ps2::mouse_get_buttons();
            let mask = (if l { 1 } else { 0 }) | (if r { 2 } else { 0 }) | (if m { 4 } else { 0 });
            return encode_fixnum(mask).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MOUSE_POLL) {
            let ev = crate::ps2::poll_raw();
            match ev {
                Some(crate::ps2::Ps2RawEvent::Mouse(b)) => {
                    crate::ps2::mouse_handle_byte(b);
                    return encode_fixnum(b as i64).ok_or(ReplError::NumericOverflow);
                }
                _ => return Ok(NIL),
            }
        }
        if is_sym_id(op, SYM_KBD_POLL) {
            let ev = crate::ps2::poll_raw();
            match ev {
                Some(crate::ps2::Ps2RawEvent::Keyboard(b)) => {
                    return encode_fixnum(b as i64).ok_or(ReplError::NumericOverflow);
                }
                _ => return Ok(NIL),
            }
        }
        if is_sym_id(op, SYM_RDTSC) {
            let val = unsafe { crate::rdtsc() };
            let tsc_num = (val & 0x3FFF_FFFF_FFFF_FFFF) as i64;
            return encode_fixnum(tsc_num).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_RDRAND) {
            let opt = unsafe { crate::rdrand() };
            match opt {
                Some(val) => {
                    let rand_num = (val & 0x3FFF_FFFF_FFFF_FFFF) as i64;
                    return encode_fixnum(rand_num).ok_or(ReplError::NumericOverflow);
                }
                None => return Ok(NIL),
            }
        }
        if is_sym_id(op, SYM_CPUID) {
            let leaf_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let sub_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let leaf = decode_fixnum(eval_expr(leaf_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let sub = decode_fixnum(eval_expr(sub_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let (a, b, c, d) = unsafe { crate::cpuid(leaf as u32, sub as u32) };
            let fa = encode_fixnum((a & 0x3FFF_FFFF) as i64).ok_or(ReplError::NumericOverflow)?;
            let fb = encode_fixnum((b & 0x3FFF_FFFF) as i64).ok_or(ReplError::NumericOverflow)?;
            let fc = encode_fixnum((c & 0x3FFF_FFFF) as i64).ok_or(ReplError::NumericOverflow)?;
            let fd = encode_fixnum((d & 0x3FFF_FFFF) as i64).ok_or(ReplError::NumericOverflow)?;
            let list_d = context.cons(fd, NIL).map_err(|_| ReplError::OutOfMemory)?;
            let list_c = context.cons(fc, list_d).map_err(|_| ReplError::OutOfMemory)?;
            let list_b = context.cons(fb, list_c).map_err(|_| ReplError::OutOfMemory)?;
            return context.cons(fa, list_b).map_err(|_| ReplError::OutOfMemory);
        }
        if is_sym_id(op, SYM_CR_READ) {
            let reg_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let reg = decode_fixnum(eval_expr(reg_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = unsafe { crate::read_cr(reg as u8) };
            return encode_fixnum((val & 0x3FFF_FFFF_FFFF_FFFF) as i64).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MSR_READ) {
            let idx_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let idx = decode_fixnum(eval_expr(idx_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = unsafe { crate::read_msr(idx as u32) };
            return encode_fixnum((val & 0x3FFF_FFFF_FFFF_FFFF) as i64).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MSR_WRITE) {
            let idx_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let val_expr = context
                .car(context.cdr(args).map_err(|_| ReplError::WrongArgCount)?)
                .map_err(|_| ReplError::WrongArgCount)?;
            let idx = decode_fixnum(eval_expr(idx_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = decode_fixnum(eval_expr(val_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            unsafe { crate::write_msr(idx as u32, val as u64) };
            return encode_fixnum(val).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_PCI_READ) {
            let b_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let r1 = context.cdr(args).map_err(|_| ReplError::WrongArgCount)?;
            let d_expr = context.car(r1).map_err(|_| ReplError::WrongArgCount)?;
            let r2 = context.cdr(r1).map_err(|_| ReplError::WrongArgCount)?;
            let f_expr = context.car(r2).map_err(|_| ReplError::WrongArgCount)?;
            let r3 = context.cdr(r2).map_err(|_| ReplError::WrongArgCount)?;
            let off_expr = context.car(r3).map_err(|_| ReplError::WrongArgCount)?;

            let bus = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let dev = decode_fixnum(eval_expr(d_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let func = decode_fixnum(eval_expr(f_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let offset = decode_fixnum(eval_expr(off_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;

            let val = unsafe { crate::pci_read32(bus as u8, dev as u8, func as u8, offset as u8) };
            return encode_fixnum(val as i64).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_PCI_WRITE) {
            let b_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let r1 = context.cdr(args).map_err(|_| ReplError::WrongArgCount)?;
            let d_expr = context.car(r1).map_err(|_| ReplError::WrongArgCount)?;
            let r2 = context.cdr(r1).map_err(|_| ReplError::WrongArgCount)?;
            let f_expr = context.car(r2).map_err(|_| ReplError::WrongArgCount)?;
            let r3 = context.cdr(r2).map_err(|_| ReplError::WrongArgCount)?;
            let off_expr = context.car(r3).map_err(|_| ReplError::WrongArgCount)?;
            let r4 = context.cdr(r3).map_err(|_| ReplError::WrongArgCount)?;
            let val_expr = context.car(r4).map_err(|_| ReplError::WrongArgCount)?;

            let bus = decode_fixnum(eval_expr(b_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let dev = decode_fixnum(eval_expr(d_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let func = decode_fixnum(eval_expr(f_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let offset = decode_fixnum(eval_expr(off_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = decode_fixnum(eval_expr(val_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;

            unsafe { crate::pci_write32(bus as u8, dev as u8, func as u8, offset as u8, val as u32) };
            return encode_fixnum(val).ok_or(ReplError::NumericOverflow);
        }
        if is_sym_id(op, SYM_MEM_READ64) {
            let addr_expr = context.car(args).map_err(|_| ReplError::WrongArgCount)?;
            let addr = decode_fixnum(eval_expr(addr_expr, env, context)?).ok_or(ReplError::TypeMismatch)?;
            let val = unsafe { crate::mem_read64(addr as u64) };
            return encode_fixnum((val & 0x3FFF_FFFF_FFFF_FFFF) as i64).ok_or(ReplError::NumericOverflow);
        }

        // Application of a function expression (e.g. variable holding closure or inline lambda)
        let func = eval_expr(op, env, context)?;
        if is_closure(func, context) {
            let closure_cell = context.cell(func).map_err(|_| ReplError::TypeMismatch)?;
            let c1 = context.cell(closure_cell.cdr).map_err(|_| ReplError::TypeMismatch)?;
            let params = c1.car;
            let c2 = context.cell(c1.cdr).map_err(|_| ReplError::TypeMismatch)?;
            let body = c2.car;
            let c3 = context.cell(c2.cdr).map_err(|_| ReplError::TypeMismatch)?;
            let captured_env = c3.car;

            // Evaluate arguments
            let mut evaled_args = NIL;
            let mut rev_evaled = NIL;
            let mut cur_arg = args;
            while cur_arg != NIL {
                let a = context.car(cur_arg).map_err(|_| ReplError::WrongArgCount)?;
                let va = eval_expr(a, env, context)?;
                rev_evaled = context.cons(va, rev_evaled).map_err(|_| ReplError::OutOfMemory)?;
                cur_arg = context.cdr(cur_arg).map_err(|_| ReplError::WrongArgCount)?;
            }
            // Reverse rev_evaled to preserve order
            while rev_evaled != NIL {
                let va = context.car(rev_evaled).map_err(|_| ReplError::WrongArgCount)?;
                evaled_args = context.cons(va, evaled_args).map_err(|_| ReplError::OutOfMemory)?;
                rev_evaled = context.cdr(rev_evaled).map_err(|_| ReplError::WrongArgCount)?;
            }

            // Bind params to arguments in captured_env
            let mut call_env = captured_env;
            let mut cur_p = params;
            let mut cur_a = evaled_args;
            while cur_p != NIL && cur_a != NIL {
                let p = context.car(cur_p).map_err(|_| ReplError::WrongArgCount)?;
                let a = context.car(cur_a).map_err(|_| ReplError::WrongArgCount)?;
                call_env = env_bind(p, a, call_env, context)?;
                cur_p = context.cdr(cur_p).map_err(|_| ReplError::WrongArgCount)?;
                cur_a = context.cdr(cur_a).map_err(|_| ReplError::WrongArgCount)?;
            }
            if cur_p != NIL || cur_a != NIL {
                return Err(ReplError::WrongArgCount);
            }

            // Evaluate body expressions in sequence
            let mut result = NIL;
            let mut cur_expr = body;
            while cur_expr != NIL {
                let e = context.car(cur_expr).map_err(|_| ReplError::WrongArgCount)?;
                result = eval_expr(e, call_env, context)?;
                cur_expr = context.cdr(cur_expr).map_err(|_| ReplError::WrongArgCount)?;
            }
            return Ok(result);
        }

        return Err(ReplError::UndefinedFunction);
    }

    Ok(expr)
}

pub fn is_closure(val: Word, context: &RuntimeContext) -> bool {
    if (val & TAG_MASK) != Tag::Cons as Word {
        return false;
    }
    if let Ok(head) = context.car(val) {
        is_sym_id(head, SYM_CLOSURE)
    } else {
        false
    }
}

// ---------------------------------------------------------------------------
// S-Expression Printer
// ---------------------------------------------------------------------------

pub fn print_val<W: FnMut(&[u8])>(
    val: Word,
    context: &RuntimeContext,
    write_fn: &mut W,
) {
    if val == NIL {
        write_fn(b"nil");
        return;
    }
    if val == CANONICAL_T {
        write_fn(b"t");
        return;
    }
    let tag = val & TAG_MASK;
    if tag == Tag::Fixnum as Word {
        if let Some(n) = decode_fixnum(val) {
            print_signed_decimal(n, write_fn);
        }
        return;
    }
    if tag == Tag::Symbol as Word {
        if let Some(id) = decode_symbol(val) {
            if id == wsm_os_target::SYMBOL_ID_MAX {
                write_fn(b"t");
            } else if let Some(name) = symbol_name(id) {
                write_fn(name);
            } else {
                write_fn(b"sym#");
                print_unsigned_decimal(id, write_fn);
            }
        }
        return;
    }
    if tag == Tag::Cons as Word {
        if is_closure(val, context) {
            write_fn(b"#<closure>");
            return;
        }
        write_fn(b"(");
        let mut curr = val;
        let mut first = true;
        while let Ok(cell) = context.cell(curr) {
            if !first {
                write_fn(b" ");
            }
            first = false;
            print_val(cell.car, context, write_fn);
            if cell.cdr == NIL {
                break;
            }
            if (cell.cdr & TAG_MASK) == Tag::Cons as Word && !is_closure(cell.cdr, context) {
                curr = cell.cdr;
            } else {
                write_fn(b" . ");
                print_val(cell.cdr, context, write_fn);
                break;
            }
        }
        write_fn(b")");
        return;
    }
    if tag == Tag::Closure as Word {
        write_fn(b"#<closure-desc>");
        return;
    }
    if tag == Tag::Capability as Word {
        write_fn(b"#<capability>");
        return;
    }
    write_fn(b"#<unknown>");
}

fn print_signed_decimal<W: FnMut(&[u8])>(mut val: i64, write_fn: &mut W) {
    if val < 0 {
        write_fn(b"-");
        if val == i64::MIN {
            write_fn(b"9223372036854775808");
            return;
        }
        val = -val;
    }
    print_unsigned_decimal(val as u64, write_fn);
}

fn print_unsigned_decimal<W: FnMut(&[u8])>(mut val: u64, write_fn: &mut W) {
    let mut digits = [0_u8; 20];
    let mut cursor = digits.len();
    if val == 0 {
        write_fn(b"0");
        return;
    }
    while val != 0 && cursor > 0 {
        cursor -= 1;
        digits[cursor] = b'0' + (val % 10) as u8;
        val /= 10;
    }
    write_fn(&digits[cursor..]);
}

// ---------------------------------------------------------------------------
// Evaluates one line of input and prints result
// ---------------------------------------------------------------------------

pub fn repl_eval_and_print<W: FnMut(&[u8])>(
    input: &[u8],
    context: &mut RuntimeContext,
    write_fn: &mut W,
) {
    let mut cursor = 0;
    match read_expr(input, &mut cursor, context) {
        Ok(expr) => match eval_expr(expr, NIL, context) {
            Ok(result) => {
                write_fn(b"WSM-OS REPL value=");
                print_val(result, context, write_fn);
            }
            Err(err) => {
                write_fn(b"WSM-OS CONDITION schema=1 kind=");
                write_fn(err.as_str());
                write_fn(b" source=eval value=");
                write_fn(input);
            }
        },
        Err(ReplError::Empty) => {}
        Err(err) => {
            write_fn(b"WSM-OS CONDITION schema=1 kind=");
            write_fn(err.as_str());
            write_fn(b" source=reader value=");
            write_fn(input);
        }
    }
}
