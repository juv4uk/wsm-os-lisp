# Мінімальний доказ Pascal ↔ C через ABI
*Minimal Pascal ↔ C ABI evidence*

**Статус / Status:** hosted ABI test розширено; повторний GitHub Actions запуск очікується після оновлення workflow.  
**Issue:** [#116](https://github.com/juv4uk/wsm-os-lisp/issues/116).

## Що перевіряється / What is tested

Один FPC caller використовує статичну C-бібліотеку, зібрану GCC. Тест має чотири частини:

1. **Scalar ABI:** `cdecl`, два `int32_t` аргументи, `int32_t` результат.
2. **Struct layout:** `{$PACKRECORDS C}` проти C `struct`; перевіряються `sizeof=16` і `offsetof(value)=8`. C compile-time `_Static_assert` фіксує ті самі очікування.
3. **Callback ABI:** C викликає Pascal callback через `cdecl`; Pascal передає контекст як borrowed pointer.
4. **Negative arguments:** C відхиляє null record, callback і context до розіменування та callback invocation.

C-функція тимчасово позичає record/context лише на час виклику. Вона не зберігає покажчики, не виділяє й не звільняє caller-owned пам'ять. У цьому зрізі немає cross-language heap ownership: об'єкти створює та знищує Pascal caller.

## Очікуваний результат / Expected output

```text
PASCAL-C-ABI-PASS
abi=cdecl i32 scalar result=439
abi=record size=16 value_offset=8 value=107
abi=callback borrowed_context result=42
abi=negative null_arguments=rejected
```

Запуск:

```sh
python3 benchmarks/multilang/run_abi_probe.py
```

Будь-яка помилка компіляції, лінкування, виконання, layout або checksum завершує тест ненульовим кодом. Workflow `Toolchain iteration benchmark` запускає цей тест і зберігає артефакти основного toolchain benchmark.

## Межа доказу / Evidence boundary

Цей hosted Linux test **не** доводить:
- сумісність із kernel або freestanding ABI;
- UEFI ABI, Microsoft x64 function pointer/callback convention чи EFI entry point;
- variadic functions, thread-safety, reentrancy або callback lifetime після повернення;
- передачу ownership алокацій між Pascal та C;
- продуктивність або енергоефективність будь-якої мови.

Це вузький доказ того, що FPC може безпечно повторно використовувати конкретний C API через перевірений C ABI. Для API, який передає володіння пам'яттю, потрібен окремий контракт allocator/deallocator і негативні тести lifetime.

## English summary

The hosted probe now checks scalar arguments/results, C-compatible record layout, a C-to-Pascal callback with a borrowed context pointer, and fail-closed null-argument handling. C retains no Pascal pointers and owns no Pascal allocations. This is not evidence for kernel, freestanding, or UEFI ABI compatibility.
