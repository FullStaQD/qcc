// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Support/Elf2Mem.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/Object/Binary.h"
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <optional>
#include <vector>

using namespace llvm;

namespace {

struct Segment {
  uint32_t addr;
  ArrayRef<uint8_t> bytes;
  uint32_t memSize;
};

} // namespace

namespace qcc {

Error convertElfToMem(const MemoryBuffer& elfBuffer, raw_ostream& os) {
  Expected<std::unique_ptr<object::Binary>> binaryOrErr = object::createBinary(elfBuffer.getMemBufferRef());
  if (!binaryOrErr) {
    return binaryOrErr.takeError();
  }

  auto* elfObj = dyn_cast<object::ELF32LEObjectFile>(binaryOrErr->get());
  if (elfObj == nullptr) {
    return createStringError(inconvertibleErrorCode(), "expected a 32-bit little-endian ELF (e.g. riscv32)");
  }

  const object::ELFFile<object::ELF32LE>& elfFile = elfObj->getELFFile();

  auto progHeadersOrErr = elfFile.program_headers();
  if (!progHeadersOrErr) {
    return progHeadersOrErr.takeError();
  }

  std::vector<Segment> segments;
  for (const auto& phdr : *progHeadersOrErr) {
    if (phdr.p_type != ELF::PT_LOAD || phdr.p_memsz == 0) {
      continue;
    }

    auto bytesOrErr = elfFile.getSegmentContents(phdr);
    if (!bytesOrErr) {
      return bytesOrErr.takeError();
    }

    segments.push_back({.addr = static_cast<uint32_t>(phdr.p_vaddr), // FIXME: use p_paddr instead?
                        .bytes = *bytesOrErr,
                        .memSize = static_cast<uint32_t>(phdr.p_memsz)});
  }

  if (segments.empty()) {
    return createStringError("no loadable (PT_LOAD) segments found");
  }

  // gABI compliant ELF should satisfy the below checks.
  uint64_t minNextAddr = 0;
  for (const Segment& seg : segments) {
    if (seg.addr % 4 != 0) {
      return createStringError("segment at address 0x%08X is not word (4-byte) aligned", seg.addr);
    }
    if (seg.addr < minNextAddr) {
      return createStringError("loadable segments are not in ascending, non-overlapping address order");
    }
    minNextAddr = uint64_t{seg.addr} + seg.memSize;
  }

  std::optional<uint32_t> nextExpectedAddr;
  for (const Segment& seg : segments) {
    if (nextExpectedAddr != seg.addr) {
      os << format("@%08X\n", seg.addr / 4);
    }

    for (uint32_t off = 0; off < seg.memSize; off += 4) {
      uint32_t word = 0;
      for (uint32_t b = 0; b < 4; ++b) {
        uint32_t idx = off + b;
        uint8_t byte = idx < seg.bytes.size() ? seg.bytes[idx] : 0;
        word |= static_cast<uint32_t>(byte) << (8 * b);
      }
      os << format("%08X\n", word);
    }

    nextExpectedAddr = seg.addr + seg.memSize;
  }

  return Error::success();
}

} // namespace qcc
