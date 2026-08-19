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
