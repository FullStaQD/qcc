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
 * layout only has to satisfy two constraints: the core fetches from
 * BOOT_ADDR = 0x80 after reset, and the image must fit in the testbench
 * memory (0x40000 bytes).
 *
 * `.text._start` is pulled to the front of .text so qcc's synthesized
 * `_start` lands on BOOT_ADDR.
 */

BOOT_ADDR = 0x00000080;
STACK_SIZE = 0x1000;

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

  . = ALIGN(4);
  .rodata : {
    *(.rodata .rodata.*)
  } :image

  . = ALIGN(4);
  .data : {
    *(.data .data.*)
  } :image

  . = ALIGN(4);
  .bss : {
    *(.bss .bss.*)
  } :image

  /* Keep __stack_top 16-byte aligned per the RISC-V psABI. */
  __stack_top = ALIGN(16) + STACK_SIZE;

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.riscv.attributes)
    *(.note.*)
  }
}
