#!/usr/bin/env python3
import os
import subprocess
import sys
import time

def main():
    # Build repl kernel image
    print("Building REPL kernel and UEFI image...")
    env = os.environ.copy()
    env["WSM_FIXTURE"] = "repl-fixture"
    subprocess.run(
        ["cargo", "build", "-p", "wsm-os-kernel", "--target", "x86_64-unknown-none"],
        env=env,
        check=True,
    )
    subprocess.run(
        [
            "cargo",
            "run",
            "-p",
            "wsm-os-image",
            "--",
            "target/x86_64-unknown-none/debug/wsm-os-kernel",
            "target/wsm-os-repl-uefi.img",
        ],
        check=True,
    )

    ovmf_code = os.environ.get("OVMF_CODE")
    ovmf_vars = os.environ.get("OVMF_VARS")
    if not ovmf_code or not ovmf_vars:
        # Source ovmf-env.sh
        ovmf_env_out = subprocess.check_output(
            ["bash", "-c", "source scripts/ovmf-env.sh && echo $OVMF_CODE && echo $OVMF_VARS"],
            text=True,
        ).splitlines()
        ovmf_code = ovmf_env_out[0]
        ovmf_vars = ovmf_env_out[1]

    vars_copy = "/tmp/wsm-test-ovmf-vars.fd"
    subprocess.run(["cp", ovmf_vars, vars_copy], check=True)
    os.chmod(vars_copy, 0o600)

    qemu_cmd = [
        "qemu-system-x86_64",
        "-machine", "q35",
        "-m", "128M",
        "-drive", f"if=pflash,unit=0,format=raw,readonly=on,file={ovmf_code}",
        "-drive", f"if=pflash,unit=1,format=raw,file={vars_copy}",
        "-drive", "format=raw,file=target/wsm-os-repl-uefi.img",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
        "-display", "none",
        "-serial", "stdio",
        "-no-reboot",
    ]

    print("Launching QEMU interactive session...")
    proc = subprocess.Popen(
        qemu_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )

    def read_until(expected: bytes, timeout: float = 15.0) -> bytes:
        start = time.time()
        buf = bytearray()
        while time.time() - start < timeout:
            ch = proc.stdout.read(1)
            if not ch:
                break
            buf.extend(ch)
            if expected in buf:
                return bytes(buf)
        raise TimeoutError(f"Timed out waiting for {expected!r}. Received so far: {bytes(buf)!r}")

    def send_line(line: str):
        print(f">> SEND: {line.strip()}")
        proc.stdin.write(line.encode("utf-8") + b"\n")
        proc.stdin.flush()

    try:
        # Wait for prompt
        out = read_until(b"\n> ", timeout=45.0)
        print(f"<< RECV BOOT:\n{out.decode('utf-8', errors='replace')}")

        test_cases = [
            ("(cons 1 2)", "WSM-OS REPL value=(1 . 2)"),
            ("(car (cons 42 nil))", "WSM-OS REPL value=42"),
            ("(cdr (cons 42 99))", "WSM-OS REPL value=99"),
            ("(atom 5)", "WSM-OS REPL value=t"),
            ("(atom (cons 1 2))", "WSM-OS REPL value=nil"),
            ("(eq 7 7)", "WSM-OS REPL value=t"),
            ("(eq 7 8)", "WSM-OS REPL value=nil"),
            ("(+ 10 32)", "WSM-OS REPL value=42"),
            ("(- 100 58)", "WSM-OS REPL value=42"),
            ("(* 6 7)", "WSM-OS REPL value=42"),
            ("(< 5 10)", "WSM-OS REPL value=t"),
            ("(> 5 10)", "WSM-OS REPL value=nil"),
            ("(= 42 42)", "WSM-OS REPL value=t"),
            ("(def x 100)", "WSM-OS REPL value=100"),
            ("(+ x 5)", "WSM-OS REPL value=105"),
            ("(сполучити 1 2)", "WSM-OS REPL value=(1 . 2)"),
            ("(перше (сполучити 77 nil))", "WSM-OS REPL value=77"),
            ("(if (eq 0 0) 10 20)", "WSM-OS REPL value=10"),
            ("(if (eq 1 0) 10 20)", "WSM-OS REPL value=20"),
            ("(def dec (lambda (n) (- n 1)))", "WSM-OS REPL value="),
            ("(dec 5)", "WSM-OS REPL value=4"),
            ("(def fact (lambda (n) (if (eq n 0) 1 (* n (fact (- n 1))))))", "WSM-OS REPL value="),
            ("(fact 1)", "WSM-OS REPL value=1"),
            ("(fact 2)", "WSM-OS REPL value=2"),
            ("(fact 3)", "WSM-OS REPL value=6"),
            ("(fact 4)", "WSM-OS REPL value=24"),
            ("(fact 5)", "WSM-OS REPL value=120"),
            ("(визначити укр-факт (лямбда (н) (якщо (тотожне? н 0) 1 (помножити н (укр-факт (відняти н 1))))))", "WSM-OS REPL value="),
            ("(укр-факт 5)", "WSM-OS REPL value=120"),
            ("(logand 255 15)", "WSM-OS REPL value=15"),
            ("(logior 4 8)", "WSM-OS REPL value=12"),
            ("(logxor 15 10)", "WSM-OS REPL value=5"),
            ("(ash 1 4)", "WSM-OS REPL value=16"),
            ("(ash 32 -2)", "WSM-OS REPL value=8"),
            ("(побітове-і 7 3)", "WSM-OS REPL value=3"),
            ("(побітове-або 1 2)", "WSM-OS REPL value=3"),
            ("(зсув 4 1)", "WSM-OS REPL value=8"),
            ("(ps2-mouse-init)", "WSM-OS REPL value=t"),
            ("(mouse-pos)", "WSM-OS REPL value=(512 . 384)"),
            ("(mouse-buttons)", "WSM-OS REPL value=0"),
            ("(миша-позиція)", "WSM-OS REPL value=(512 . 384)"),
            ("(миша-кнопки)", "WSM-OS REPL value=0"),
            ("(def decode-delta (lambda (raw sign) (if (= (logand sign 1) 1) (- raw 256) raw)))", "WSM-OS REPL value="),
            ("(decode-delta 255 1)", "WSM-OS REPL value=-1"),
            ("(decode-delta 10 0)", "WSM-OS REPL value=10"),
            ("(> (rdtsc) 0)", "WSM-OS REPL value=t"),
            ("(> (лічильник-тактів) 0)", "WSM-OS REPL value=t"),
            ("(def t1 (rdtsc))", "WSM-OS REPL value="),
            ("(def t2 (rdtsc))", "WSM-OS REPL value="),
            ("(< t1 t2)", "WSM-OS REPL value=t"),
            ("(= (logand (cr-read 0) 1) 1)", "WSM-OS REPL value=t"),
            ("(> (cr-read 3) 0)", "WSM-OS REPL value=t"),
            ("(> (зчитати-cr 3) 0)", "WSM-OS REPL value=t"),
            ("(> (car (cpuid 0 0)) 0)", "WSM-OS REPL value=t"),
            ("(= (logand (pci-read 0 0 0 0) 65535) 32902)", "WSM-OS REPL value=t"),
            ("(= (побітове-і (зчитати-pci 0 0 0 0) 65535) 32902)", "WSM-OS REPL value=t"),
            ("(def pci-find (lambda (bus dev max) (if (> dev max) nil (if (= (logand (pci-read bus dev 0 0) 65535) 65535) (pci-find bus (+ dev 1) max) (cons dev (pci-find bus (+ dev 1) max))))))", "WSM-OS REPL value=#<closure>"),
            ("(pci-read 0 1 0 0)", "WSM-OS REPL value="),
            ("(pci-read 0 2 0 0)", "WSM-OS REPL value="),
            ("(pci-read 0 3 0 0)", "WSM-OS REPL value="),
            ("(logand (pci-read 0 31 0 0) 65535)", "WSM-OS REPL value=32902"),
        ]

        for expr, expected in test_cases:
            send_line(expr)
            out = read_until(b"\n> ")
            decoded = out.decode("utf-8", errors="replace")
            print(f"<< RECV: {decoded.strip()}")
            assert expected in decoded, f"FAIL: expected {expected!r} in {decoded!r}"

        # Quit REPL
        send_line("q")
        proc.wait(timeout=5)
        print(f"QEMU exited cleanly with code {proc.returncode}")
        # isa-debug-exit with 0x10 lowers to status (0x10 << 1) | 1 = 33
        assert proc.returncode in (33, 0), f"Unexpected exit code {proc.returncode}"
        print("ALL REPL TESTS PASSED!")

    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if os.path.exists(vars_copy):
            os.unlink(vars_copy)

if __name__ == "__main__":
    main()
