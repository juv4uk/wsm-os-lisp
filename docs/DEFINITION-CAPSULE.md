# Definition capsule v1

`artifacts/definition-capsule.json` is inspectable metadata for the first
compiled WSM definition. It identifies evidence; it is not a loader, world
image, or authorization for hot replacement.

## Stable identity

`definition_id` is `sha256:` plus the SHA-256 of compact JSON containing, in
serde_json's deterministic key order:

```text
schema + schema_version
source semantic SHA-256
entry symbol
target ABI schema + version
my-lisp contract + revision
CML supported contract + revision
```

The definition ID deliberately excludes machine-code bytes. Recompiling the
same admitted definition for the same semantic contracts preserves identity;
assembly and object digests still detect implementation drift.

## Digest boundary

All capsule and manifest digests are SHA-256. Source has two distinct digests:

- `file_digest` covers the committed `fixture.wsm` bytes, including its final
  newline;
- `semantic_digest` covers the exact source admitted by CML, without that
  repository formatting newline.

Code ranges are object-relative `.text` offsets, not runtime addresses. The
literal and symbol-table digests cover compact JSON encodings of their
committed entries.

## Verification

`scripts/check-definition-capsule.sh`:

1. regenerates the complete bundle twice from pinned CML;
2. requires byte-identical source, assembly, object, manifest and capsule;
3. compares all regenerated files with the committed bundle;
4. independently recomputes capsule sections and artifact digests;
5. proves that a deliberately altered capsule is rejected.

The hosted harness copies the committed assembly while the kernel links the
committed object. The regeneration gate proves both belong to the same
definition bundle.

GNU assembler versions may add different non-semantic
`.note.gnu.property` metadata. The generator removes that section with GNU
`objcopy` before hashing or linking, so the committed ELF object remains
byte-identical across the pinned Guix and GitHub environments rather than
weakening comparison to instruction-only equivalence.

---

# Капсула визначення версія 1 (Ukrainian)

`artifacts/definition-capsule.json` — це доступні для інспектування метадані
для першого скомпільованого WSM-визначення. Він ідентифікує докази (evidence); 
це не є завантажувачем, образом світу чи дозволом на гарячу заміну 
(hot replacement).

## Стабільна ідентичність

`definition_id` складається з префікса `sha256:` та SHA-256 хеша від
компактного JSON, який містить, у детермінованому порядку ключів `serde_json`:

```text
schema + schema_version
семантичний SHA-256 вихідного коду (source semantic SHA-256)
символ точки входу (entry symbol)
схема цільового ABI + версія
контракт my-lisp + ревізія
підтримуваний контракт CML + ревізія
```

Ідентифікатор визначення навмисно виключає байти машинного коду. 
Перекомпіляція того самого схваленого (admitted) визначення під ті самі
семантичні контракти зберігає його ідентичність; дайджести (digests)
асемблерного та об'єктного файлів усе одно дозволяють виявляти зміни в
реалізації (implementation drift).

## Межі дайджестів

Усі дайджести в капсулі та маніфесті використовують алгоритм SHA-256. Вихідний 
код має два різні дайджести:

- `file_digest` охоплює байти закоміченого файлу `fixture.wsm`, включно з
  його останнім символом нового рядка;
- `semantic_digest` охоплює точний вихідний код, прийнятий `cml`, без цього 
  репозиторного символу нового рядка.

Діапазони коду — це зміщення секції `.text` відносно початку об'єктного
файлу, а не адреси під час виконання. Дайджести літералів та таблиці символів 
охоплюють компактні JSON-кодування їхніх закомічених записів.

## Верифікація

Скрипт `scripts/check-definition-capsule.sh`:

1. двічі регенерує повний бандл (bundle) за допомогою зафіксованої версії CML;
2. вимагає байтової ідентичності між вихідним кодом, асемблером, об'єктом, маніфестом і капсулою;
3. порівнює всі регенеровані файли із закоміченим бандлом;
4. незалежно переобчислює секції капсули та дайджести артефактів;
5. доводить, що навмисно змінена капсула відхиляється.

Hosted-оболонка копіює закомічений асемблерний код, тоді як ядро лінкує 
закомічений об'єктний файл. Перевірка регенерації доводить, що обидва
належать до того самого бандла визначення.

Різні версії GNU assembler можуть додавати неоднакові несемантичні
метадані в секцію `.note.gnu.property`. Генератор видаляє цю секцію
за допомогою GNU `objcopy` перед хешуванням або лінкуванням, тому закомічений
ELF-об'єкт залишається байт-у-байт ідентичним як у зафіксованому середовищі
Guix, так і в GitHub, що дозволяє уникнути послаблення перевірки до лише
інструкційної еквівалентності (instruction-only equivalence).
