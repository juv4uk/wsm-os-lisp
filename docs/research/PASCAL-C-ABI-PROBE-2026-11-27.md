# Мінімальний доказ Pascal ↔ C через ABI

**Статус:** тестовий зріз додано; очікує GitHub Actions execution.  
**Issue:** [#116](https://github.com/juv4uk/wsm-os-lisp/issues/116).

## Що доводить

C-функція `c_mix(int32_t, int32_t)` компілюється GCC у статичну бібліотеку. Free Pascal викликає її через `cdecl` та зовнішній символ `c_mix`. Тест очікує точний результат `367`.

Це доводить лише вузький hosted Linux ABI slice:
- виклик за C calling convention;
- два 32-бітні цілі аргументи за значенням;
- 32-бітне ціле значення повернення;
- зв'язування Pascal-програми зі статичною C-бібліотекою.

## Що навмисно не доводить

- передавання вказівників або ownership пам'яті між мовами;
- структури, packing, callbacks, variadic functions чи thread-safety;
- freestanding/kernel ABI, драйверний контекст або UEFI сумісність;
- право переносити hosted RTL у ядро.

У прикладі немає heap-об'єктів, тому правила звільнення пам'яті між мовами не виникають. Для складніших API ownership/lifetime мають бути окремо визначені й протестовані.

## Запуск

```sh
python3 benchmarks/multilang/run_abi_probe.py
```

Workflow `Toolchain iteration benchmark` виконує цей зріз разом із вимірюванням компіляторів. Позитивний результат — рядок `PASCAL-C-ABI-PASS`; будь-яка помилка компіляції, лінкування, запуску або checksum завершує тест ненульовим кодом.
