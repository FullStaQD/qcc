# HiSEP-Q linking and memory image

`qcc --target=hisepq` only compiles to object files. Getting from there to
something the [HiSEP-Q-2.0](https://github.com/caps-tum/HiSEP-Q-2.0)
co-simulation testbench (the RTL sim in that repo's `demo/`, runnable via Vivado
`xsim` or Verilator) or real hardware can actually run takes two more steps.

```sh
# Compile to object file.
qcc --target=hisepq --compile-to=native --binary input.mlir -o out.o

# Link with our provided linker script. You can use any RISC-V capable linker here.
ld.lld -T mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld out.o -o out.elf

# Convert to memory image for simulator.
hisepq-elf2mem out.elf -o out.mem
```

## Why we ship these files

Both the linker script and `hisepq-elf2mem` really belong to HiSEP-Q rather than
to the compiler. We carry them because HiSEP-Q ships no BSP (Board Support
Package).

TODO: Once HiSEP-Q ships a crt0, qcc emits a plain `main`, drops the `_start`
synthesis, and both files leave this tree. Our future compiler driver likely
gains a `--sysroot`-style override so an external BSP can take over.

## Simulating with `sim_hisepq`

`sim_hisepq` is the HiSEP-Q RTL testbench, built with Verilator. Our tests use
it to run compiled programs. Get it with `utils/provision-sim-hisepq`. Testing a
build with `QCC_ENABLE_HISEPQ` needs it and `ld.lld`. A build that can't provide
them sets `-DQCC_HISEPQ_SIM_TESTS=OFF` to skip the tests that need them.

The testbench runs the processor on a memory image and logs the quantum events
and the pulses it sends to each qubit. It has no quantum state, so the test
provides the measurement outcomes. A run therefore checks how a program reacts
to given outcomes, not which outcomes it produces.

```shell
sim_hisepq +MEM_FILE=out.mem +MEASURE_FILE=outcomes.txt +AWG_EXPECT=pulses.expect
```

Our tests use these plusargs:

- `+MEM_FILE=<file>`: the memory image to run, from `hisepq-elf2mem`.
- `+MEASURE_RESULT=<hex>`: the value of `qv.mres` after every measurement. Bit
  `k` is the outcome of element `k`.
- `+MEASURE_FILE=<file>`: one value per measurement instead, in the format
  below.
- `+AWG_EXPECT=<file>`: the pulses the run must send, in the format below.

Without `+MEASURE_RESULT` or `+MEASURE_FILE`, every measurement returns
`A5A5A5A5` after 50 cycles.

The run ends with `RESULT : PASS`, or with `RESULT : FAIL` and a nonzero exit
code, for example when `+MEASURE_FILE` runs out of lines or the pulses don't
match `+AWG_EXPECT`. A run that executes nothing fails after a timeout.

### Measurement file (`*.outcomes`)

One line per measurement (`qv.mz`), in order:

```text
<qv.mres in hex> <delay in cycles>
```

For example, `00000001 20` returns outcome 1 for element 0 and 0 for all other
elements after 20 cycles.

### Pulse file (`*.expect`)

One line per pulse the run must send:

```text
<qubit in decimal> <gate id in hex> <C|T> <payload valid: 0|1> <payload in hex>
```

For example, `0 64 C 0 00000000` is an H on qubit 0, and `3 66 T 1 00000000` is
the target side of a CX on qubit 3 with control qubit 0. The payload is only
compared if it is valid.

The HiSEP-Q QISA specification defines the gate ids `64` (H), `66` (CX) and `68`
(measurement). It doesn't define X yet. Our LLVM patch
[`0002-Update-instruction-encoding-4.patch`](../../../../third-party/llvm/patches/qisa/0002-Update-instruction-encoding-4.patch)
uses `02` for `qv.x`, and the testbench passes it through unchanged.

The testbench matches pulses and lines one to one, but doesn't check their
order. It reads at most 64 lines.

Neither format allows comments. The testbench fails on a measurement file it
can't parse, and hangs on such a pulse file. Our tests write comments after a
`#` anyway and strip them with `sed 's/#.*//'` before running the testbench.

More details are in the HiSEP-Q
[verification notes](https://github.com/caps-tum/HiSEP-Q-2.0/blob/59f5696/docs/verification.md)
and [`demo/run.sh`](https://github.com/caps-tum/HiSEP-Q-2.0/blob/59f5696/demo/run.sh),
at the version `utils/provision-sim-hisepq` installs.
