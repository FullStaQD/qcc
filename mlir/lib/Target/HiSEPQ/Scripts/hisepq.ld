/* ===----------------------------------------------------------------------===
 *
 * Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
 * Exceptions.
 * See <repo-root>/LICENSE.txt for license information.
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 * ===----------------------------------------------------------------------===
 *
 * Linker script for the --target=hisepq output of qcc.
 *
 * The HiSEP-Q simulator loads the image into a single flat memory, so the
 * layout only has to satisfy two constraints: the core fetches from BOOT_ADDR
 * after reset, and the image must fit in the testbench memory (MEM_SIZE).
 *
 * `.text._start` is pulled to the front of .text so qcc's synthesized
 * `_start` lands on BOOT_ADDR.
 */

BOOT_ADDR = 0x80;
STACK_SIZE = 0x1000;
MEM_SIZE = 0x40000;

OUTPUT_ARCH(riscv)
ENTRY(_start)

PHDRS
{
  image PT_LOAD;
}

SECTIONS
{
  . = BOOT_ADDR;

  .text : {
    KEEP(*(.text._start))
    *(.text .text.*)
  } :image

  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } :image

  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  } :image

  /* Nothing zeroes .bss at run time (there is no crt0). It is SHT_NOBITS and so
   * covered by p_memsz but not p_filesz, and hisepq-elf2mem materializes that
   * tail as zero words. */
  .bss : {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
  } :image

  /* Keep __stack_top 16-byte aligned per the RISC-V psABI. */
  __stack_top = ALIGN(16) + STACK_SIZE;

  ASSERT(__stack_top <= MEM_SIZE, "image + stack exceeds the HiSEP-Q memory")

  /* Deliberately absent: __global_pointer$ (the .s* sections above are reached by
   * absolute addressing; gp-relative addressing is unused) and .init_array /
   * .fini_array (qcc emits no static constructors). */

  /* .eh_frame is allocatable, so it would otherwise land in the image. */
  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.riscv.attributes)
    *(.note.*)
  }
}
