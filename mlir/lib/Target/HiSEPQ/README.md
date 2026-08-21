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

## Simulating

You can download a prebuilt simulator `sim_hisepq` with our
`utils/provision-sim-hisepq` script. Then use it like so

```shell
# Run it on the RTL testbench:
sim_hisepq +MEM_FILE=out.mem
```

Note that `sim_hisepq` exits 0 unconditionally -- even when it loads no memory
image at all it still prints `RESULT: PASS`, having executed nothing. Judge a
run by its instruction trace and event counters, not by its exit status.
