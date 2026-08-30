# Owner hardware profile

**Captured:** 2026-08-29T11:45:33+03:00  
**Purpose:** constrain `wsm-os` boot, runtime and future driver decisions.  
**Privacy:** serial numbers, UUIDs and MAC addresses are intentionally excluded
from this public document.

## Evidence classes

- **WINDOWS-OBSERVED:** Windows CIM or Windows `nvidia-smi` read the physical
  machine.
- **WSL-OBSERVED:** visible inside the current WSL2 environment; resource
  limits may differ from the physical host.
- **INFERRED:** architectural consequence of observed hardware.
- **UNKNOWN:** not established by the available command or permission level.

## Physical platform

| Component | Observed value | Evidence |
|---|---|---|
| System / motherboard | Gigabyte Technology Co., Ltd. H170-Gaming 3 | WINDOWS-OBSERVED |
| Baseboard version | `x.x` | WINDOWS-OBSERVED |
| Firmware | American Megatrends Inc. BIOS `F22e` | WINDOWS-OBSERVED |
| BIOS release date | 2018-03-09 | WINDOWS-OBSERVED |
| Firmware type | UEFI (`BiosFirmwareType=2`) | WINDOWS-OBSERVED |
| Secure Boot | Unknown: query was denied by Windows privilege boundary | UNKNOWN |
| Host OS | Windows 11 Pro for Workstations, 64-bit, version 10.0 build 26200 | WINDOWS-OBSERVED |

### Consequence for `wsm-os`

The physical machine is a valid later UEFI target, but the first boot remains
QEMU-only. A UEFI GOP/serial path is preferable to writing an Intel or NVIDIA
display driver in the first milestones. No physical disk or EFI partition may
be written automatically.

## CPU

| Property | Observed value | Evidence |
|---|---|---|
| Processor | Intel Core i5-6400 @ 2.70 GHz | WINDOWS + WSL |
| Microarchitecture | Skylake, family 6 model 94 stepping 3 | WSL-OBSERVED |
| Topology | 1 socket, 4 cores, 4 logical processors, no SMT exposed | WINDOWS + WSL |
| Maximum reported clock | 2701 MHz | WINDOWS-OBSERVED |
| Byte order | little-endian | WSL-OBSERVED |
| Address sizes visible to WSL | 39-bit physical, 48-bit virtual | WSL-OBSERVED |
| Cache | L1d 4×32 KiB; L1i 4×32 KiB; L2 4×256 KiB; shared L3 6 MiB | WSL-OBSERVED |
| Virtualization | Microsoft hypervisor present; WSL reports VT-x/full virtualization | WINDOWS + WSL |

### Relevant exposed ISA features

```text
x86_64 NX SSE SSE2 SSSE3 SSE4.1 SSE4.2 AVX AVX2 FMA
AES PCLMULQDQ POPCNT BMI1 BMI2 ADX RDRAND RDSEED
VMX EPT VPID 1GiB pages SMEP SMAP PCID INVPCID
```

This permits a normal scalar x86_64 baseline and later measured AVX2/BMI2
specialization. The first WSM witness must not require those optional
extensions: correctness precedes optimization.

`VirtualizationFirmwareEnabled=false` was returned by one WMI field while a
Microsoft hypervisor and working WSL2 are directly observed. The field is not
used as evidence that hardware virtualization is disabled.

## Memory

| Scope/module | Capacity | Speed | Part |
|---|---:|---:|---|
| Physical host total | 16 GiB (17,060,347,904 bytes reported) | — | WINDOWS-OBSERVED |
| DIMM 1 | 8 GiB | DDR4-2133 configured at 2133 | `CT8G4DFS8213.C8FBD1` |
| DIMM 2 | 8 GiB | DDR4-2133 configured at 2133 | `TEAMGROUP-UD4-2133` |
| Current WSL allocation | 7.7 GiB RAM | — | WSL-OBSERVED |
| Current WSL swap | 2.0 GiB | — | WSL-OBSERVED |

The two DIMMs have different reported manufacturers/part numbers. This is not
currently treated as an error; memory validation belongs to physical hardware
testing, not the QEMU milestone.

### Consequence for `wsm-os`

M1/M2 should use a deliberately small fixed heap and explicitly test OOM.
Identity mapping of all host RAM is not necessary for the first release.

## Graphics and compute

| Device | Memory / capability | Driver/runtime evidence |
|---|---|---|
| Intel HD Graphics 530 | WMI reports 1 GiB adapter memory | Windows driver `26.20.100.7262` |
| NVIDIA GeForce GTX 1050 Ti | 4096 MiB, CUDA capability 6.1 (`sm_61`) | Windows NVIDIA driver `582.66` |

Windows `nvidia-smi` additionally reported for the GTX 1050 Ti:

| Property | Value |
|---|---:|
| PCI location | `00000000:01:00.0` |
| Power limit | 90 W |
| Maximum graphics clock | 1974 MHz |
| Maximum memory clock | 3504 MHz |
| Capture-time performance state | P8 (idle/low-power state) |

The current restricted agent process could not initialize Linux NVML and had
no `nvcc` in PATH. Windows `nvidia-smi` did work. This is an environment
capability difference, not evidence of a missing GPU.

### Consequence for `wsm-os`

- initial output: serial, then optionally UEFI GOP;
- Intel/NVIDIA native display drivers are deferred;
- CUDA is a hosted accelerator concern for `wsm-cuda`, not an M1 bare-metal
  service;
- Pascal `sm_61` must remain explicit in any later CUDA build matrix.

## Storage

| Device | Type / bus | Capacity | Windows health |
|---|---|---:|---|
| Kingston `SNV2S1000G` | NVMe SSD | 1 TB | Healthy |
| Samsung SSD 850 EVO | SATA SSD | 120 GB | Healthy |
| Samsung `HD321KJ` | SATA HDD | 320 GB | Healthy |

WSL exposes virtual disks rather than these physical devices directly,
including a 1 TiB virtual disk plus small system/swap disks.

### Safety boundary

M1-M5 create image files only. They must not select, partition, format or write
any physical device. A later owner-authorized hardware test must identify its
exact removable target independently and use a recoverable workflow.

## Network

| Device | Observed capability | Evidence |
|---|---|---|
| Killer E2200 Gigabit Ethernet Controller | Ethernet 802.3, 1 Gbit/s | WINDOWS-OBSERVED |
| Tailscale Tunnel | virtual adapter, reported separately | WINDOWS-OBSERVED |

The first `wsm-os` milestones have no network stack. The exact E2200 PCI
device/revision and driver design remain a future hardware-inventory task.

## Audio

Windows reports these healthy audio endpoints/devices:

- High Definition Audio Device;
- NVIDIA High Definition Audio;
- Intel Display Audio;
- NVIDIA Virtual Audio Device.

Audio is outside the first release and does not influence the boot substrate.

## Current development environment

| Property | Observed value |
|---|---|
| WSL kernel | `6.18.33.2-microsoft-standard-WSL2` |
| Distribution | Ubuntu 24.04.4 LTS |
| WSL CPUs | 4 online |
| Rust | `rustc/cargo 1.98.0` |
| Installed Rust targets | `x86_64-unknown-linux-gnu`, `x86_64-pc-windows-gnu`, `wasm32-unknown-unknown` |
| Binutils | GNU `objcopy` 2.42 |
| Guix | available (`0cc8f411...` build) |
| QEMU x86_64 | not found in the current agent PATH |
| Bare-metal Rust target | not installed |
| `clang`, `lld`, `nasm`, `xorriso` | not found in the current agent PATH |

These are tool-availability observations, not hardware limitations. M0 must
choose and provision the minimum reproducible boot toolchain before M1 begins.

## Architecture decisions derived from this profile

1. **Primary target:** x86_64 little-endian UEFI.
2. **First execution environment:** QEMU, not the physical disks.
3. **First I/O:** serial transcript; UEFI GOP is optional and later.
4. **First memory model:** bounded allocator with explicit OOM.
5. **Optimization baseline:** scalar x86_64; AVX2/BMI2 only after profiling.
6. **GPU boundary:** GTX 1050 Ti belongs to hosted `wsm-cuda` evidence until a
   separately ratified driver/runtime plan exists.
7. **Resource policy:** builds/tests remain bounded for 4 CPU threads and the
   7.7 GiB currently assigned to WSL.

## Reproduction commands

Linux/WSL evidence was collected with `uname`, `/etc/os-release`, `lscpu`,
`free`, `lsblk`, `systemd-detect-virt` and tool `--version` probes. Physical
Windows evidence came from read-only `Get-CimInstance`, `Get-PhysicalDisk`,
`Get-ComputerInfo` and `nvidia-smi` queries selecting only the fields published
above.

---

# Профіль заліза власника (український переклад)

**Зафіксовано:** 2026-08-29T11:45:33+03:00  
**Призначення:** обмежити рішення щодо boot, рантайму та майбутніх драйверів
`wsm-os`.  
**Приватність:** серійні номери, UUID і MAC-адреси навмисно виключені з цього
публічного документа.

## Класи evidence

- **WINDOWS-OBSERVED:** Windows CIM або Windows `nvidia-smi` прочитали фізичну
  машину.
- **WSL-OBSERVED:** видимо всередині поточного середовища WSL2; ліміти ресурсів
  можуть відрізнятися від фізичного хоста.
- **INFERRED:** архітектурний наслідок спостереженого заліза.
- **UNKNOWN:** не встановлено доступною командою або рівнем дозволів.

## Фізична платформа

| Компонент | Спостережене значення | Evidence |
|---|---|---|
| Система / материнська плата | Gigabyte Technology Co., Ltd. H170-Gaming 3 | WINDOWS-OBSERVED |
| Версія baseboard | `x.x` | WINDOWS-OBSERVED |
| Firmware | American Megatrends Inc. BIOS `F22e` | WINDOWS-OBSERVED |
| Дата релізу BIOS | 2018-03-09 | WINDOWS-OBSERVED |
| Тип firmware | UEFI (`BiosFirmwareType=2`) | WINDOWS-OBSERVED |
| Secure Boot | Невідомо: запит відхилено межею привілеїв Windows | UNKNOWN |
| Host OS | Windows 11 Pro for Workstations, 64-bit, версія 10.0 build 26200 | WINDOWS-OBSERVED |

### Наслідок для `wsm-os`

Фізична машина є валідною пізнішою UEFI-ціллю, але перший boot залишається
лише в QEMU. Шлях UEFI GOP/serial є кращим, ніж написання Intel- чи
NVIDIA-драйвера дисплея в перших milestones. Жоден фізичний диск чи EFI-розділ
не може бути записаний автоматично.

## CPU

| Властивість | Спостережене значення | Evidence |
|---|---|---|
| Процесор | Intel Core i5-6400 @ 2.70 GHz | WINDOWS + WSL |
| Мікроархітектура | Skylake, family 6 model 94 stepping 3 | WSL-OBSERVED |
| Топологія | 1 socket, 4 ядра, 4 логічні процесори, SMT не показано | WINDOWS + WSL |
| Максимальна заявлена частота | 2701 MHz | WINDOWS-OBSERVED |
| Порядок байтів | little-endian | WSL-OBSERVED |
| Розміри адрес, видимі для WSL | 39-бітна фізична, 48-бітна віртуальна | WSL-OBSERVED |
| Кеш | L1d 4×32 KiB; L1i 4×32 KiB; L2 4×256 KiB; спільний L3 6 MiB | WSL-OBSERVED |
| Віртуалізація | Microsoft hypervisor присутній; WSL повідомляє VT-x/повну віртуалізацію | WINDOWS + WSL |

### Відповідні показані ISA-функції

```text
x86_64 NX SSE SSE2 SSSE3 SSE4.1 SSE4.2 AVX AVX2 FMA
AES PCLMULQDQ POPCNT BMI1 BMI2 ADX RDRAND RDSEED
VMX EPT VPID 1GiB pages SMEP SMAP PCID INVPCID
```

Це дозволяє звичайний скалярний x86_64-базис і пізнішу виміряну спеціалізацію
AVX2/BMI2. Перший WSM-свідок не повинен вимагати цих опційних розширень:
коректність передує оптимізації.

`VirtualizationFirmwareEnabled=false` повернуло одне WMI-поле, тоді як Microsoft
hypervisor і робочий WSL2 спостерігаються безпосередньо. Це поле не
використовується як доказ, що апаратна віртуалізація вимкнена.

## Пам'ять

| Обсяг/модуль | Місткість | Швидкість | Part |
|---|---|---:|---:|---|
| Усього на фізичному хості | 16 GiB (повідомлено 17,060,347,904 bytes) | — | WINDOWS-OBSERVED |
| DIMM 1 | 8 GiB | DDR4-2133, налаштовано на 2133 | `CT8G4DFS8213.C8FBD1` |
| DIMM 2 | 8 GiB | DDR4-2133, налаштовано на 2133 | `TEAMGROUP-UD4-2133` |
| Поточний розподіл WSL | 7.7 GiB RAM | — | WSL-OBSERVED |
| Поточний swap WSL | 2.0 GiB | — | WSL-OBSERVED |

Два DIMM мають різні заявлені виробники/part-номери. Це зараз не трактується
як помилка; валідація пам'яті належить тестуванню фізичного заліза, а не
QEMU-milestone.

### Наслідок для `wsm-os`

M1/M2 мають використовувати навмисно малу фіксовану купу й явно тестувати OOM.
Identity-mapping усієї RAM хоста не потрібен для першого релізу.

## Графіка та обчислення

| Пристрій | Пам'ять / спроможність | Evidence драйвера/рантайму |
|---|---|---|
| Intel HD Graphics 530 | WMI повідомляє 1 GiB адаптерної пам'яті | Windows драйвер `26.20.100.7262` |
| NVIDIA GeForce GTX 1050 Ti | 4096 MiB, CUDA capability 6.1 (`sm_61`) | Windows NVIDIA драйвер `582.66` |

Windows `nvidia-smi` додатково повідомив для GTX 1050 Ti:

| Властивість | Значення |
|---|---:|
| PCI розташування | `00000000:01:00.0` |
| Ліміт потужності | 90 W |
| Максимальна частота графіки | 1974 MHz |
| Максимальна частота пам'яті | 3504 MHz |
| Performance state на момент збору | P8 (idle/low-power стан) |

Поточний обмежений process агента не міг ініціалізувати Linux NVML і не мав
`nvcc` у PATH. Windows `nvidia-smi` спрацювало. Це різниця спроможностей
середовища, а не доказ відсутності GPU.

### Наслідок для `wsm-os`

- початковий вивід: serial, потім опційно UEFI GOP;
- власні драйвери дисплея Intel/NVIDIA відкладено;
- CUDA — це hosted-акселератор для `wsm-cuda`, а не bare-metal сервіс M1;
- Pascal `sm_61` має лишатися явним у будь-якій пізнішій build-матриці CUDA.

## Зберігання

| Пристрій | Тип / шина | Місткість | Стан у Windows |
|---|---|---:|---|
| Kingston `SNV2S1000G` | NVMe SSD | 1 TB | Healthy |
| Samsung SSD 850 EVO | SATA SSD | 120 GB | Healthy |
| Samsung `HD321KJ` | SATA HDD | 320 GB | Healthy |

WSL показує віртуальні диски, а не ці фізичні пристрої безпосередньо,
включно з віртуальним диском 1 TiB плюс малі системний/swap-диски.

### Межа безпеки

M1–M5 створюють лише файли образів. Вони не повинні обирати, розбивати,
форматувати чи записувати будь-який фізичний пристрій. Пізніше
owner-авторизоване тестування заліза має незалежно ідентифікувати точну
знімну ціль і використовувати відновлюваний робочий процес.

## Мережа

| Пристрій | Спостережена спроможність | Evidence |
|---|---|---|
| Killer E2200 Gigabit Ethernet Controller | Ethernet 802.3, 1 Gbit/s | WINDOWS-OBSERVED |
| Tailscale Tunnel | віртуальний адаптер, повідомляється окремо | WINDOWS-OBSERVED |

Перші milestones `wsm-os` не мають мережевого стеку. Точний PCI-пристрій/ревізія
E2200 і дизайн драйвера лишаються майбутнім завданням інвентаризації заліза.

## Аудіо

Windows повідомляє ці справні аудіо-завершення/пристрої:

- High Definition Audio Device;
- NVIDIA High Definition Audio;
- Intel Display Audio;
- NVIDIA Virtual Audio Device.

Аудіо поза першим релізом і не впливає на boot-субстрат.

## Поточне середовище розробки

| Властивість | Спостережене значення |
|---|---|
| WSL kernel | `6.18.33.2-microsoft-standard-WSL2` |
| Дистрибутив | Ubuntu 24.04.4 LTS |
| WSL CPUs | 4 online |
| Rust | `rustc/cargo 1.98.0` |
| Встановлені Rust-цілі | `x86_64-unknown-linux-gnu`, `x86_64-pc-windows-gnu`, `wasm32-unknown-unknown` |
| Binutils | GNU `objcopy` 2.42 |
| Guix | доступний (build `0cc8f411...`) |
| QEMU x86_64 | не знайдено в поточному PATH агента |
| Bare-metal Rust ціль | не встановлено |
| `clang`, `lld`, `nasm`, `xorriso` | не знайдено в поточному PATH агента |

Це спостереження доступності інструментів, а не обмеження заліза. M0 має обрати
й забезпечити мінімальний відтворюваний boot-toolchain до початку M1.

## Архітектурні рішення, виведені з цього профілю

1. **Основна ціль:** x86_64 little-endian UEFI.
2. **Перше середовище виконання:** QEMU, не фізичні диски.
3. **Перший I/O:** serial-транскрипт; UEFI GOP — опційно й пізніше.
4. **Перша модель пам'яті:** обмежений алокатор з явним OOM.
5. **Базис оптимізації:** скалярний x86_64; AVX2/BMI2 лише після профілювання.
6. **Межа GPU:** GTX 1050 Ti належить до hosted evidence `wsm-cuda`, доки не
   існує окремо ратифікованого плану драйвера/рантайму.
7. **Resource policy:** build-и/тести лишаються обмеженими 4 CPU-потоками та
   7.7 GiB, поточним розподілом для WSL.

## Команди відтворення

Linux/WSL-доказ зібрано `uname`, `/etc/os-release`, `lscpu`, `free`, `lsblk`,
`systemd-detect-virt` і `--version`-пробами інструментів. Фізичний
Windows-доказ отримано з read-only запитів `Get-CimInstance`,
`Get-PhysicalDisk`, `Get-ComputerInfo` і `nvidia-smi`, що обирають лише поля,
опубліковані вище.
