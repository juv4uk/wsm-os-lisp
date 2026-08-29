# Lisp Machine Heritage in WSM-OS

Цей документ фіксує історичні принципи Lisp-машин, які ми адаптуємо (або свідомо відкидаємо) для `wsm-os`. Основне правило: **нам не треба копіювати Symbolics. Нам треба забрати з Lisp-машин те, що робить Lisp природним для машини, а не те, що робить машину складною.**

## 1. Найцінніша фішка Lisp-машин — не `CAR` в залізі
Це **tagged words**. У Symbolics 3600 (32 bits data + 4 tag bits) та Ivory (40-bit tagged architecture) процесор міг перевіряти тип під час виконання. 
У `wsm-os` це вже вбудовано в `target-contract.wsm`: 61 payload bits + 3 tag bits. 
> CPU не повинен знати всю мову WSM. Але runtime повинен бачити WSM-об'єкт без зовнішньої таблиці типів.

## 2. “Тип — частина значення”
Звичайна C-машина бачить `0x0000000000000043` як просто байти. WSM machine бачить `[word payload | tag]` і одразу знає: `tag(word) == FIXNUM`. Це дає "object-ness of memory", що було центральною рисою Virtual Lisp Machine.

## 3. Не робити “апаратний CAR”
Старі Lisp-машини прискорювали CAR/CDR через microcode/hardware. Пізніший аналіз (MIT CSG) критикував цю надмірну спеціалізацію. Тому ми робимо не `CPU instruction = CAR`, а `runtime ABI = wsm_car` — дуже вдале сучасне переосмислення.

## 4. Натхнення від Scheme-79
Steele і Sussman проектували процесор Scheme-79 прямо навколо evaluator. Їхня філософія: *architecture should follow the natural structure of Lisp programs/data*. Не "Lisp -> C-машина", а "Lisp data model -> machine model".

## 5. “Typed pointer as opcode-ish information” (WSM semantic dispatch)
Dispatch починається з 3 бітів:
```rust
match tag(word) {
    Cons   => ...
    Fixnum => ...
    Symbol => ...
    Nil    => ...
    True   => ...
}
```

## 6. 16-byte cons cell — дуже хороший вибір
Ми відкидаємо історичний **CDR coding** (стиснення cons-комірок), бо він приносить забагато складності (`if cdr-code...`). 16 байтів — чудова ціна за прозорість (`address + 0 = car`, `address + 8 = cdr`).

## 7. Bump allocation
Allocation у Lisp має бути дешевим. Схема з `heap_start`, `heap_next` та `heap_end` — ідеальна для старту.

## 8. GC — не поспішайте
Symbolics мав складні GC (generational, hardware-assisted). Для нас правило v0: **bounded heap + no GC + explicit OOM**. Це створює ідеальну доказову модель.

## 9. А потім — дуже простий copying GC
Semi-space copying collector ідеально підходить для нас, бо cons cells одного розміру і tag каже, чи це pointer. Тут tagged architecture реально окупається.

## 10. Stack buffer
WSM call stack = contiguous array of Word. Три види storage (registers, stack frames, heap cons) — достатньо для прозорого рантайму.

## 11. Маленький “WSM context”
У нашому ABI: `ENTRY_CONTEXT_REGISTER = rdi`. Це маленька “машина у структурі”, яку можна запускати однаково в Linux harness, QEMU, на голому залізі чи у FPGA-симуляторі.

## 12. LIVE SYSTEM — але не одразу
Еволюція має бути поступовою: від AOT frozen expression до live Lisp environment. Не варто починати з Genera.

## 13. Symbols = IDs
`symbol = image-local interned ID`. Текст потрібен лише для printer/debugger. Runtime економить величезну кількість складності.

## 14. Розділення “symbol identity” і “symbol name”
Ядру не потрібні UTF-8, malloc, hashing чи filesystem.

## 15. Що НЕ треба брати з Lisp machines
- CDR coding
- microprogrammable ISA
- hardware GC (ephemeral, VM-aware)
- special stack hardware
- hardware closures/environments

## 16. WSM Lisp Machine v0
- **Values:** 64-bit tagged Word (fixnum, symbol, immediates)
- **Memory:** bounded heap, cons (16 bytes)
- **ABI:** cons, car, cdr, eq, atom, fail -> generated x86 -> WSM expression

## 17. Довгострокова перспектива: WSM ISA
WSM bytecode + tiny interpreter або x86.

## 18. Природна поява FPGA
FPGA (`fpga-lisp`) реалізує той самий machine contract: FETCH -> DECODE -> tag dispatch -> cons-memory -> next.

## 19. Data structure influences instruction structure
Machine representation preserves the semantic shape of WSM as long as it is simpler than lowering it away.

## 20. Рекомендація: Borrow invariants, not machinery
Що беремо:
- ✅ Tagged memory
- ✅ Object-aware memory
- ✅ Fast cons allocation
- ✅ Typed dispatch
- ✅ Small primitive substrate
- ✅ Lisp as system language (поступово)

Що відкидаємо / залишаємо на потім:
- ❌ Hardware GC, CDR coding, Huge microcode ISA, Full Genera-like OS.

**Головна теза:**
`WSM-OS aims to become a machine whose natural values are WSM values.`

Три найголовніші ідеї:
1. tag-driven semantic dispatch;
2. bump heap → пізніше simple copying GC;
3. малий WSM execution context як “машина в структурі”.
