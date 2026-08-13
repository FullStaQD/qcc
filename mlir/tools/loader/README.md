# HiSEP-Q loader

`qcc --target=hisep-q` only compiles: it lowers a circuit down to native RISC-V
QISA (`--compile-to=native`) and stops there. Getting from there to something
the [HiSEP-Q-2.0](https://github.com/caps-tum/HiSEP-Q-2.0) co-simulation
testbench (the RTL sim in that repo's `demo/`, runnable via Vivado `xsim` or
Verilator) or real hardware can actually run takes two more steps.

First, link the object file against `hisepq.ld`, the linker script in this
directory. It places code at the hardware's boot address and lays out
`.rodata`/`.data`/`.bss` the way the opcode simulator expects (see the comment
block at the top of the script for the memory-layout contract).

Then convert the linked ELF into the `$readmemh` memory image the simulator
loads, using the `elf2mem` tool (`mlir/tools/elf2mem`).

```sh
qcc --target=hisep-q --compile-to=native --binary input.mlir -o out.o
ld.lld -T mlir/tools/loader/hisepq.ld out.o -o out.elf
elf2mem out.elf -o out.mem
```

Any RISC-V-capable linker works for the link step, not just `ld.lld` — just
pass `-T hisepq.ld` to whichever one you use.
