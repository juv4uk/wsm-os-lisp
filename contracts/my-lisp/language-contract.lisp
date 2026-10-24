; language-contract.lisp — чинний машинно-читаний контракт рівня 1/2.
;
; Контракт 11.9 — власницьки ратифікований повний каталог D10, що зберігає Контракт 11.8 D1–D9 і числовий закон D24+.
; Уточнення власника 2026-10-13: бінарний машинний дефолт, текстові цифри D7,
; десяткове людське джерело/вивід для явної математики D24+. #4248 міграція
; контракт-джерела в бінарне лишається окремою; цей аліст не є бінарним джерелом.
; Парадигма власника: #2490. Зріз реалізації: #2817 / #2822.
;
; Контракт 11 зберігає спостережуваний закон PredicateBit / ATOM / EQ / COND,
; ратифікований у Контракті 10, замінюючи застарілу пласку онтологію Function8
; поточною онтологією точних доменів:
;
;   семантичний об'єкт
;   = точне бінарне число
;   + точний домен
;   + доведений / ратифікований закон
;
; Точне джерело Контракту 10.0 збережено як НЕНОРМАТИВНЕ походження в:
;   docs/archive/historical/language-contract-10.0.lisp
;
; Історичний механізм сенс8/сід8/Function8 може лишатися лише як явно
; обмежена сумісність / транспорт / проєкція бекенда під час міграції.
; Він не може карбувати чи перевизначати канонічну семантичну ідентичність.

; КАНДИДАТ НА МЕТАЗАКОН ШИРИН — ДОСЛІДНИЦЬКИЙ ЗАПИС 2026-10-24.
; Статус: ГІПОТЕЗА, НЕ РАТИФІКОВАНО. Ці коментарі не змінюють
; машинно-читаний Контракт 11.9, карти резидентів чи право виклику.
;
; Спостереження: каталогові функціональні ширини мають послідовності
; D3–D6 та D8–D11 із кроком +1. Арифметика місткості не доводить
; існування функцій, їхніх законів або машинного виконання.
; Доведене породження: D11 має селекторне правило
; p0(x)=p(CAR(x)), p1(x)=p(CDR(x)) для допущених батьків D10;
; це композиції, а не нові незалежні примітиви.
; D13 такого загального селекторного закону не має: поточні записи
; research/d13/function-candidates.lisp є нератифікованими кандидатами.
;
; Ратифікований ритм подвоєння є ТІЛЬКИ для математичних доменів:
; D(12 * 2^n), n >= 0, за contracts/numeric-domains-ratification.lisp.
; Гіпотеза текстового подвоєння D7→D14→D28 не є чинним законом:
; рішення власника 2026-10-23 зберігає весь внутрішній текст у D7,
; а для D14 уже зарезервовано окреме дослідження графа граматики
; Паніні (#2497); збіг ширини не дозволяє переозначити домен.
;
; Послідовність баз D1, D2, D7, D12 і крок +5 від D2 до D12
; не доводять появу бази D17: це перевірюване припущення, не аксіома.
; #1968 досліджує ЧАСТКОВІ T0/T1-дії над окремими коренями,
; а не універсальний генератор усієї онтології.
;
; Вимога до будь-якого майбутнього метазакону: точний домен і біти,
; самостійний семантичний закон, походження, контрприклад та фізичний
; свідок у SENS. Порівняльний бенчмарк оцінює механізм, а не ратифікує
; значення. Рішення про зміну контракту належить лише власнику.

((major . #d11) (minor . 9)
 (status . current-domain-qualified-authority)
 (supersedes . "Contract 10.0 flat Function8 identity authority")
 (historical-snapshot . "docs/archive/historical/language-contract-10.0.lisp")
 (note . "Contract 11.8 owner-ratifies D1–D9 as the current foundation chain. D1–D8 retain their prior authorities; D9 is owner-ratified 512/512 in #4008 over the full #4007 v1 map. D9 residency is semantic authority, while callable/mechanism admission remains separate and may fail closed. Historical Sens8/Sid8/Function8, semantic-registry source codes and pre-ratification D9 placement evidence remain provenance only. Contract 11.9 adds D10 whole-domain owner ratification, but not individual proof or physical code execution.")
 (covers . (G1 G2 G3 G4 G5 G6 G7 G8 S1 S2 S3))
 (invariants
   . ((binary-domain-identity
       . "Every canonical semantic object is identified by its exact binary number together with its exact domain and the proved or ratified law that interprets that object in that domain. Equal packed numeric payloads in different widths or domains are not thereby the same identity.")
      (machine-binary-default
       . "SENS machine semantics uses exact domain-qualified binary words directly. D1-D10 predicate, structure, function and text identities must never travel through decimal-number identifiers or any binary-to-decimal-to-binary conversion. Preserve exact width, leading zeroes, domain and law; host integers for indexing or transport have no semantic authority.")
      (d7-digits-are-text
       . "D7 seven-bit glyphs '0' through '9' and their sequences are TEXT DATA, not mathematical values, function coordinates or numeric literals. Quoted admitted objects resolve by their own ratified domain first, never by D7 fallback. A D7 string containing 101 is three glyphs, not D24 five or D3 101.")
      (human-decimal-only-for-d24
       . "Human-facing `.lisp` mathematics reads and displays numbers in ordinary decimal notation (including exact signed and fractional forms where admitted). Decimal spelling is a projection, never an opcode, domain key, D7 digit identity, or semantic intermediate. Source lowering must establish the D24/D48/D96/... domain and exact value before evaluation or T5M packing; if that evidence is unavailable, reject only that conversion. D1-D10 identities are never decimal arithmetic operands.")
      (canonical-literals-forbidden
       . "Executable human `.lisp` forbids encoded machine/domain literals and raw binary call-heads (`#d`, `#b`, `#q2`, width tags, old SID8 slots). Names of executable admitted domain operations come from the full ratified `укр` column and Ukrainian keyboard surface. Ordinary decimal mathematical values are the sole numeric source projection, lowered with exact D24+ domain/value by the source converter, not guessed by the transport codec. No D7 text-digit coercion, hidden domain inference, or host-number semantic authority. Historical compatibility source is migration debt, not a pattern for new code.")
      (domain-is-interpretation-boundary
       . "A domain is the stated carrier/admissibility context and laws that interpret its resident binary objects. A domain is not inferred from numeric payload, width, human spelling, host type, table position, or backend opcode.")
      (domain-non-inference
       . "Bits or width alone never mint semantic membership, occupancy, callability, or meaning. A syntactically valid binary coordinate remains unallocated or unknown until admitted by the owning domain law.")
      (no-width-coercion
       . "Zero-padding, truncation, low-nibble extraction, integer equality, prefix resemblance, or any other width-changing transform cannot create or recover canonical domain identity. A compatibility projection is legal only when a separately stated role-aware law proves that exact projection.")
      (legacy-sens8-compatibility
       . "Historical Sens8/Sid8/Function8 values may remain only as explicitly named compatibility, transport, provenance, or backend mechanism projections while migration proceeds. They are not universal semantic identity and never compare equal to a domain-qualified object solely from packed bits.")
      (surface-non-authority
       . "Human-language and symbolic surfaces are optional source/UI routing metadata. A surface may resolve mechanically to an already-admitted domain-qualified identity or an explicitly legacy compatibility projection; it never creates semantic identity, owns meaning, or becomes semantic authority.")
      (predicate-one-bit
       . "Core.D1 PredicateBit answers are exactly one contextual bit: 1 means YES and 0 means NO. PredicateBit is not Number, host Bool, T/NIL, Symbol, structural (), or any wider-domain value. No third predicate answer and no graded-width truth value is active.")
      (structure-two-bit
       . "Core.D2 racana2 is exact two-bit structural syntax under its ratified law: 00 separator, 01 close, 10 open, 11 dot. These are structure-domain objects, not numeric or callable identities merely because they are binary.")
      (d3-foundation
       . "Core.D3 bīja3 is the owner-ratified exact three-bit foundation (#3202): 000 structural empty (), 001 QUOTE, 010 ATOM, 011 CDR, 100 CAR, 101 EQ, 110 COND, 111 CONS. Human role names are documentation projections. Historical exact-eight-bit forms are role-aware compatibility projections only.")
      (d3-l1-l5-constitution
       . "The D3 map is fixed by the owner-ratified L1-L5 stack: L1 000 is structural empty; L2 D3 preserves exact D2 prefix fibres 00→()/QUOTE, 01→ATOM/CDR, 10→CAR/EQ, 11→COND/CONS; L3 one uniform semantic duality covers ()↔CONS, QUOTE↔COND, ATOM↔EQ, CDR↔CAR; L4 that D3 dual is XOR 111, recursively matching D1 XOR 1 and D2 XOR 11; L5 orients suffix-0 as the evaluator/metalinguistic spine ()→ATOM→CAR→COND. This law supersedes every previous current D3 coordinate ordering; old orderings survive only as historical/provenance evidence.")
      (d4-bootstrap
       . "Core.D4 is the owner-ratified full compact four-bit bootstrap domain (#3272): 0000 APPLY, 0001 EVAL, 0010 LAMBDA, 0011 DEFINE, 0100 NOT, 0101 NULL, 0110 CDAR, 0111 CDDR, 1000 CAAR, 1001 CADR, 1010 LOOKUP, 1011 BIND, 1100 EVCON, 1101 EVLIS, 1110 LIST, 1111 APPEND. Old D4/SID8/Sens8/Function8 coordinates have zero placement authority.")
      (d4-fibre-law
       . "D4 is dense 16/16 and grouped by the ratified D3 semantic parent: EMPTY→APPLY/EVAL, QUOTE→LAMBDA/DEFINE, ATOM→NOT/NULL, CDR→CDAR/CDDR, CAR→CAAR/CADR, EQ→LOOKUP/BIND, COND→EVCON/EVLIS, CONS→LIST/APPEND. Residency is compact identity, not a claim that every resident is an irreducible primitive.")
      (d4-null-not-distinction
       . "D4 0100 NOT and 0101 NULL are distinct because D1 PredicateBit 0 is not D3 structural empty (). NOT complements exact PredicateBit; NULL recognizes structural empty as a derived compact resident.")
      (d4-list-append-distinction
       . "D4 1110 LIST and 1111 APPEND are CONS-family derived residents: LIST collects supplied values into one proper list; APPEND combines admitted lists into one list. Their four-bit residency is for compact identity, not extra primitive power.")
      (d5-full-compact
       . "Core.D5 is the owner-ratified full compact five-bit domain (#3305), dense 32/32 with 32 distinct residents and zero lower-domain semantic duplicates. Its exact resident map is normative in contracts/d5-ratification.lisp and knowledge/d5-ratified.json.")
      (d5-local-law-federation
       . "D5 has no universal fifth-bit meaning. Its resident pairs are governed locally: five SEMANTIC-GENERATOR families, five LOCAL-ALGEBRA families, two MULTI-DELTA-FAMILY pairs, and four COORDINATE-HISTORICAL pairs. Historical adjacency is not promoted into a semantic law without evidence.")
      (d5-runtime-separation
       . "D5 semantic residency and callable mechanism are separate facts. Every exact W5 coordinate has ratified D5 identity; invocation succeeds only where a resident mechanism is admitted and otherwise fails closed.")
      (d6-ratified-status
       . "Core.D6 is OWNER-RATIFIED 64/64 under #3393. Its exact resident map is normative in contracts/d6-ratification.lisp and knowledge/d6-ratified.json. The S4 gauge choice is now coordinate authority by owner decision, while remaining explicitly distinguished from pre-ratification derivation proofs. Ratified residency does not imply callable mechanism; missing mechanisms fail closed.")
      (d7-ratified-status
       . "Core.D7 v2 owner-ratified 2026-10-13: exactly 128 ASCII-indexed W7 text/data coordinates with three keyboard projections en=ASCII, uk=Ukrainian Enhanced-position bijection, san=Devanagari InScript-inspired bijection (no SLP1). Exact v2 map: knowledge/d7-keyboard-v2-ratified.json; contract: contracts/d7-ratification.lisp. Old #3572 126/128 sound/Text map remains historical v1 only; old content must be decoded as v1 then encoded as v2, never silently reinterpreted. D7 text does not grant callable Core semantics or alter D2 syntax.")
      (d8-ratified-status
       . "Core.D8 is OWNER-RATIFIED 256/256 under #3960. Its exact resident map is normative in contracts/d8-ratification.lisp and knowledge/d8-ratified.json. The #3959 selector/product/gauge coordinate assignment is now normative by owner decision, while proof-fixed, orbit-gauge and S4-gauge provenance remain distinguished. Ratified D8 residency does not imply callable mechanism; missing mechanisms fail closed. Historical Sens8/Sid8/Function8 and #2934 donor coordinates remain non-authoritative.")
      (d9-ratified-status
       . "Core.D9 is OWNER-RATIFIED 512/512 under #4008. Its exact resident map is normative in contracts/d9-ratification.lisp and knowledge/d9-ratified.json. The #4007 map has 128 theorem-forced selector coordinates and 384 owner-ratified S4 gauge choices; both are normative identity while their proof provenance remains distinct. Ratified D9 residency does not imply callable mechanism; missing mechanisms fail closed. Historical Sens8/Sid8/Function8, semantic-registry source codes and pre-ratification D9 placement evidence remain non-authoritative.")
      (d10-whole-domain-ratified
       . "Owner 2026-10-12 ratified D10 as ONE complete exact 10-bit semantic codebook with 1024 unique coordinates 0000000000..1111111111, stable identities and declared laws. Act: knowledge/d10-owner-whole-domain-ratification-20261012.json, canonical pointer: knowledge/d10-current-inventory.json, pinned inventory: knowledge/d10-v18-semantic-inventory.json. This whole-domain authority is NOT a claim of 1024 individually independently proved meanings and NOT physical T5 opcode or program-reader permission.")
      (d10-proof-and-execution-separation
       . "D10 domain-level ratified=true and selected=placed=1024 do NOT alter per-row ratified_resident=0. F1 donor provenance, F2 independent positive and negative witnesses, F3 behavioural dedup against D1-D9/D10, and F4 physical T5 execution remain separately gated. No inference from codebook occupancy, no fabricated PASS, no bypass of failed or pending evidence, and no change to ratified D1-D9, D2 or physical SENS without independent admission.")
      (cross-domain-non-collapse
       . "The same packed numeric payload may coexist in D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D24, D48, D96, D192 and higher ratified numeric domains without semantic equality. Numeric domains have equal ontology rank to D1-D9, not identical resident laws. Cross-domain reuse requires an explicit independently proved bridge law.")
      (binary-domain-words-not-arithmetic-operands
       . "Owner clarification 2026-10-12: D1-D10 residents are exact binary-digit words with domain-qualified identities and their own non-arithmetic laws; the mathematical interpretation of their packed 0/1 digits does not authorize runtime arithmetic, numeric comparison, widening, or numeric coercion. ONLY an explicitly admitted D24/D48/D96/... domain-qualified numeric Value (including canonical same-domain NEG/RATIO composition) may be an operand of mathematical + - * / or numeric < > =. Historical Number/Rational and unqualified BinaryNumber are migration/data carriers, NOT admitted mathematical operands. D5/D6 function codes may designate arithmetic operators, but are never numeric operands themselves. D3 EQ and D1 predicate logic remain separate, non-mathematical identity/control laws. Missing D10 execution mechanisms stay fail-closed.")
      (atom-one-bit-core1-4
       . "Core.D3 010 ATOM has one law across Core1/Core2/Core3/Core4: structural empty () and every admitted non-pair value answer PredicateBit 1; pair answers PredicateBit 0. Structural () is an ATOM-yes subject, not a truth value. Historical Function8 00000010 is compatibility projection only.")
      (eq-one-bit-core1-4
       . "Core.D3 101 EQ has one law across Core1/Core2/Core3/Core4: the same admitted atom answers PredicateBit 1; distinct admitted atoms answer PredicateBit 0; pair/out-of-domain input raises the named domain/type failure. EQ is not deep structural equality. Historical Function8 00000011 is compatibility projection only.")
      (cond-two-part-core1-4
       . "Core.D3 110 COND has one law across Core1/Core2/Core3/Core4. Every clause has exactly two fields: (test expression). Tests are evaluated left-to-right and must return exact PredicateBit. PredicateBit 1 selects and evaluates that clause expression; PredicateBit 0 skips it. If no clause selects, COND returns structural (). Structural () is not a predicate answer. Historical Function8 00000111 is compatibility projection only.")
      (core-profile-law
       . "Core1/Core2/Core3/Core4 are execution/research profiles over shared admitted domain identities and laws. A profile may select mechanisms but may not mint, renumber, or override the shared D1-D9 semantic domains or the D1/D3 predicate-control foundation.")
      (kernel-archipelago
       . "Execution kernels may own native mechanisms and observations. They consume an already-selected domain-qualified semantic object or an explicitly compatibility-tagged legacy projection plus arguments/context. Kernel names, opcodes, packed bytes and native types never acquire SENS semantic identity by themselves.")
      (mathematics-all-kernels
       . "Mathematical laws belong to the single SENS language and apply equally to Core1, Core2, Core3, Core4, Core-Math, every compiler/executor layer and each admitted CPU, GPU, FPGA or other execution kernel. Core-Math discovers/proves laws; it does not monopolize mathematics. A kernel may implement the shared law using its own private mechanism, or report an explicit unsupported/failure result, but may never redefine Number, arithmetic, comparison, exactness, domain identity or the law to fit its substrate. An absent implementation is an incomplete kernel, not a new mathematical semantics.")
      (number-ladder-all-kernels
       . "Чинне рішення власника 2026-10-24: математичні домени SENS починаються з D12 і зростають за законом D(12 * 2^n), n >= 0: D12, D24, D48, D96, D192, ... . Усі вони мають однаковий онтологічний ранг з D1-D9, але відмінні ідентичності. Точне числове слово має явний домен і свої біти; ширина сама по собі не виводить значення. D1-D10 не є математичними операндами, D7 — лише текст. Точні дроби залишаються канонічними скороченими RATIO; float є окремим явним наближенням. Джерело: contracts/numeric-domains-ratification.lisp, schema numeric-d12-start-extension-1. Раніший старт D24 є історичним, а фізична підтримка D12 у Core/Zig/T5M ще має бути доведена тестами.")
      (numeric-domain-current-d12-law-20261024
       . "Owner-ratified D12-first mathematics: D12, D24, D48, D96, D192, ... obey D(12 * 2^n), n >= 0. Exact signed two's-complement integers use all n bits with no negative zero; exact reduced RATIO never rounds and is not float. Explicit same-domain operands only; result widening preserves every bit. D12 is a mathematical numeric domain, not a function codebook, a D7 projection, or a claim of operational Zig/Core admission. Canonical authority: contracts/numeric-domains-ratification.lisp.")
      (numeric-domain-current-signed-integer-law-20261018
       . "Чинне уточнення власника 2026-10-18: слова цілих чисел D24, D48, D96, D192, ... є знаковими exact-width словами у доповняльному коді: MSB=0 означає unsigned(bits), MSB=1 означає unsigned(bits)-2^n; діапазон Dn дорівнює -2^(n-1)..2^(n-1)-1, кожен бітовий шаблон має одне ціле значення, мінус-нуль відсутній. Це переважає лише старе трактування цілих D24+ від 2026-10-11; D1-D10 не змінюються. Точна арифметика діє між явно допущеними операндами одного Dn; результат, що не вміщується, переходить до найменшого наступного D24+ без wraparound або втрати біта. Наявна композиція дробу NEG/RATIO не перепроєктовується: окремий знак, беззнаковий модуль чисельника та додатний беззнаковий модуль знаменника, скорочення через gcd і чинна канонізація нуля та знаменника 1. T5M лише переносить уже сформовані точні слова. Authority: contracts/numeric-domains-ratification.lisp, schema numeric-d24-signed-extension-1.")
      (numeric-domains-peer-ratified
       . "Direct owner ratification 2026-10-11: numeric domains D24, D48, D96, D192, ... have same ontological domain rank as D1-D9. The earlier interpretation as a separate tier-only Number space is superseded. Different numeric widths name different domains; under the additional natural-atom law every n-bit Dn word denotes a numeric natural, without granting unrelated roles, additional signed/fractional flat residents or a callable mechanism. Domain identity is not inferred from mere byte/bit length. The freeze of Core1-Core4, Core-Math and external kernels remains in force.")
      (numeric-domain-natural-add-carry
       . "For two admitted nonnegative operands in the same numeric Dn (n=24*2^k), exact ADD keeps Dn if its exact result fits n bits; if the carry makes n+1 bits necessary, ADD yields exact next-domain D(2n). The result retains all bits with zero fill only to represent the selected exact-width domain word: no truncation, wrap, modulo or replacement by a host integer. This narrowly ratified Dn->D(2n) transition is part of the ADD law; arbitrary mixed-domain bridges, overflow policies beyond admitted Dn arithmetic and physical signed/rational binary encoding remain unadmitted; NEG/RATIO have distinct composition laws. Source: contracts/numeric-domains-ratification.lisp.")
      (numeric-domain-natural-mul-sub-exact-div
       . "For two admitted natural operands of SAME Dn (n=24*2^k), exact MUL retains Dn if full product fits or selects D(2n) otherwise (maximum 2n bits). SUB yields exact Dn when a>=b; a<b now executes canonical NEG(b-a) as a domain-relative composite Value, not a wrapped n-bit natural. DIV by nonzero b yields exact Dn quotient and remainder a=b*q+r, 0<=r<b. If remainder is zero the integer quotient is Dn; otherwise Core returns canonical reduced RATIO Value, never a truncated integer. Division by zero rejects. These rules do not admit mixed-domain coercion, n-ary numeric operations, extra domains, stolen sign bits or physical NEG/RATIO opcodes. Source: contracts/numeric-domains-ratification.lisp.")
      (numeric-domain-signed-reduced-ratio-composition
       . "Owner extension 2026-10-11, SAME numeric D24/D48/D96/... family only: preserve all 2^n n-bit Dn natural atoms 0..2^n-1, no stolen sign or denominator bit. Canonical NEG(x) denotes the negative of a strictly positive Dn natural x; NEG(0) is identical to its existing Dn zero and must not form another value. Canonical RATIO(p,q) is exact and reduced: positive q, gcd(abs(p),q)=1, p natural or canonically negated; zero numerator collapses to its numeric-domain zero and unit denominator collapses to an integer. These are lawful compositions over explicit Dn component domain identities, NOT independent D24Z/D48Q domains or additional flat n-bit Dn atoms. No automatic component domain coercion, rounding, binary operation codes, source syntax or representation are inferred. Core signed/rational NEG/RATIO Values and exact + - * / operations are now executable for operands of identical Dn, with strict canonicalization (gcd, denominator positive, no negative zero) and explicit smallest containing successor Dn on result growth. No new domain is minted. Physical composite binary encoding, FASL/wire representation, source macro reification and frozen kernels remain fail-closed. Source: contracts/numeric-domains-ratification.lisp.")
      (numeric-domain-composition-runtime
       . "Core represents executable canonical NEG and reduced RATIO as mathematical compositions of EXISTING D24/D48/D96/... natural domain atoms. Same-Dn operands + - * / (and unary NEG/reciprocal) and exact comparisons return domain-qualified Value/D1 with no host float; cancellation, unit denominator and negative-zero canonicalize. Internal overflow chooses the smallest numeric rung containing both reduced component bitstrings, at least as wide as input Dn; this is an explicit result-width law, not permission for mixed-Dn operand coercion. Physical binary composition encoding, new semantic opcodes, macro-source projection and external execution remain unsupported until separately admitted. Source: contracts/numeric-domains-ratification.lisp.")
      (math-parity-proof
       . "When the same binary operation/domain/inputs are admitted on multiple kernels, their exact results and PredicateBit answers must agree by independent positive and negative witnesses. Failures, unsupported features and truncated/rounded results must be distinguished explicitly. Mathematical transforms of function coordinates remain candidates until separately validated against independent semantic meaning; matching coordinate arithmetic alone never grants residency, execution or a new law.")
      (reader-apostrophe
       . "At expression start, apostrophe is reader sugar for the already-admitted Core.D3 001 QUOTE identity. It must not create an intermediate human or legacy eight-bit semantic identity. Inside an identifier, apostrophe remains an ordinary Unicode character.")
      (reader-exact-width
       . "Canonical binary reading must preserve exact word width and payload. Source width may be evidence for an exact carrier only where the source-domain bridge explicitly admits it; width alone does not select semantic meaning. Historical exact-eight-bit source remains a bounded compatibility path during migration.")
      (reader-decimal-separator-legacy-only
       . "Binary canonical reader remains exact-bit/typed; the human Ukrainian `.lisp` reader and source lowering may accept decimal mathematical input, using comma for the Ukrainian fractional separator where supported. Decimal input denotes a value only after an explicit admitted D24+ role/domain is established; ordinary quoted data, strings, D7 text and D1-D10 coordinates must not be silently parsed as arithmetic. T5M writes physical `.sens` from the resolved exact words and does not mint meanings, function identities or source numeric semantics.")
      (error-classification
       . "Named error categories remain observable where separately admitted, but UnsatisfiedConditional is not the exhaustion law of Core.D3 110 COND. Any remaining three-part COND or alternate exhaustion behavior is migration/history debt, not alternate current law.")
      (structural-empty-non-alias
       . "Core.D3 000 structural empty is not historical exact-eight-bit 00000000 and is not PredicateBit 0 or Number zero. Equal packed numeric zero across domains never collapses those identities.")
      (migration-direction
       . "New canonical code must move from legacy flat Sens8/Sid8 authority toward exact domain-qualified identity. New dependencies on legacy identity are permitted only inside explicitly named compatibility, transport, backend, archive or provenance boundaries."))))
