// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Support/Elf2Mem.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/Object/Binary.h"
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

using namespace llvm;

namespace {

struct Segment {
  uint32_t addr;
  ArrayRef<uint8_t> fileBytes;
  uint32_t memSize;
};

} // namespace

namespace qcc {

Error convertElfToMem(const MemoryBuffer& elfBuffer, raw_ostream& os) {
  Expected<std::unique_ptr<object::Binary>> binaryOrErr = object::createBinary(elfBuffer.getMemBufferRef());
  if (!binaryOrErr) {
    return binaryOrErr.takeError();
  }

  // FIXME: can we point somewhere inside LLVM to express why the boilerplate looks like this?

  auto* elfObj = dyn_cast<object::ELF32LEObjectFile>(binaryOrErr->get());
  if (elfObj == nullptr) {
    return createStringError(inconvertibleErrorCode(), "expected a 32-bit little-endian ELF (e.g. riscv32)");
  }

  const object::ELFFile<object::ELF32LE>& elfFile = elfObj->getELFFile();

  auto phdrsOrErr = elfFile.program_headers(); // FIXME: bad name
  if (!phdrsOrErr) {
    return phdrsOrErr.takeError();
  }

  std::vector<Segment> segments;
  for (const auto& phdr : *phdrsOrErr) {
    if (phdr.p_type != ELF::PT_LOAD || phdr.p_memsz == 0) {
      continue;
    }

    auto bytesOrErr = elfFile.getSegmentContents(phdr);
    if (!bytesOrErr) {
      return bytesOrErr.takeError();
    }

    segments.push_back({.addr = static_cast<uint32_t>(phdr.p_vaddr),
                        .fileBytes = *bytesOrErr,
                        .memSize = static_cast<uint32_t>(phdr.p_memsz)});
  }

  if (segments.empty()) {
    return createStringError(inconvertibleErrorCode(), "no loadable (PT_LOAD) segments found");
  }

  llvm::sort(segments, [](const Segment& lhs, const Segment& rhs) { return lhs.addr < rhs.addr; });

  for (size_t i = 0; i < segments.size(); ++i) {
    if (segments[i].addr % 4 != 0) {
      std::string message; // FIXME: not possible with Twine?
      raw_string_ostream(message) << format("segment at address 0x%08X is not word (4-byte) aligned", segments[i].addr);
      return createStringError(inconvertibleErrorCode(), message);
    }
    if (i > 0 && segments[i].addr < segments[i - 1].addr + segments[i - 1].memSize) {
      // FIXME: can this happen? If yes, why? Why do *we* check it *here*?
      return createStringError(inconvertibleErrorCode(), "overlapping loadable segments");
    }
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
        uint8_t byte = idx < seg.fileBytes.size() ? seg.fileBytes[idx] : 0;
        word |= static_cast<uint32_t>(byte) << (8 * b);
      }
      os << format("%08X\n", word);
    }

    nextExpectedAddr = seg.addr + seg.memSize;
  }

  return Error::success();
}

} // namespace qcc
