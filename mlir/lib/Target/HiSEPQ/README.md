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

`sim_hisepq` is the RTL testbench of HiSEP-Q built with Verilator. Our tests use
it to run compiled programs, and `utils/provision-sim-hisepq` downloads the
prebuilt version they expect. Testing a build with `QCC_ENABLE_HISEPQ` requires it
and `ld.lld`; only a build that cannot provide them opts out with
`-DQCC_HISEPQ_SIM_TESTS=OFF`, which skips the tests that need them. It runs the processor on a memory image and logs
the quantum events and the pulses it sends per qubit control line. It has
no quantum state, though: the outcomes of the measurements are given to it. So
a run checks how a program reacts to given outcomes, not which outcomes it
produces.

```shell
sim_hisepq +MEM_FILE=out.mem +MEASURE_FILE=outcomes.txt +AWG_EXPECT=pulses.expect
```

It takes its options as plusargs, of which our tests use:

- `+MEM_FILE=<file>`: the memory image to run, from `hisepq-elf2mem`.
- `+MEASURE_RESULT=<hex>`: the content of `qv.mres` after every measurement (see
  above). Bit `k` is the outcome of element `k`.
- `+MEASURE_FILE=<file>`: one line per measurement instead, in the order the
  program measures (see below).

  Without either, every measurement reports `A5A5A5A5`, so outcome 1 for
  element 0, after 50 cycles.

- `+AWG_EXPECT=<file>`: the pulses the run must send (see below).

The run ends with `RESULT : PASS`, or with `RESULT : FAIL` and a nonzero exit
status, e.g. if a measurement finds no line left in `+MEASURE_FILE` or the
pulses differ from `+AWG_EXPECT`. Running nothing fails too, after a timeout.

### Measurement file (`*.outcomes`)

One line per measurement (`qv.mz`), consumed in order:

```text
<qv.mres in hex> <delay in cycles>
```

For example `00000001 20` reports outcome 1 for element 0 and 0 for any other
element, after a delay of 20 cycles.

### Pulse file (`*.expect`)

One line per pulse the run must send:

```text
<qubit in decimal> <gate id in hex> <C|T> <payload valid: 0|1> <payload in hex>
```

For example `0 64 C 0 00000000` is an H on qubit 0 and `3 66 T 1 00000000` the
target side of a CX on qubit 3 whose control is qubit 0. The payload is only
compared if it is valid. The gate ids our tests see are `64` (H), `66` (CX) and
`68` (measurement) from the HiSEP-Q QISA specification, and `02` (X). The
specification does not assign X yet; `02` is the provisional id our LLVM patch
gives `qv.x`
([`0002-Update-instruction-encoding-4.patch`](../../../../third-party/llvm/patches/qisa/0002-Update-instruction-encoding-4.patch)),
which the testbench passes through unchanged.

The testbench compares the pulses as a multiset: every pulse must match a line
of its own and every line a pulse, but their order is not checked. It reads at
most 64 pulses.

Neither format allows comments: the testbench fails on a line of a measurement
file it cannot parse, and hangs on one of a pulse file. Our tests keep comments
after a `#` and strip them with `sed 's/#.*//'` before passing a file on.

For details see the HiSEP-Q
[verification notes](https://github.com/caps-tum/HiSEP-Q-2.0/blob/59f5696/docs/verification.md)
and [`demo/run.sh`](https://github.com/caps-tum/HiSEP-Q-2.0/blob/59f5696/demo/run.sh),
at the version `utils/provision-sim-hisepq` provides.
