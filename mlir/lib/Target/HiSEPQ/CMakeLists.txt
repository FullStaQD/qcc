# The HiSEP-Q backend is the only component that may depend on the HiSEP-Q LLVM
# fork; its RISC-V/QV codegen components are pulled in via LINK_COMPONENTS. The
# fork provides the experimental "xqv" RISC-V vector extension used to emit
# native QISA.
add_mlir_library(
  QCCTargetHiSEPQ
  HiSEPQTarget.cpp
  LINK_COMPONENTS
  RISCVCodeGen
  RISCVAsmParser
  RISCVDesc
  RISCVInfo
  CodeGen
  MC
  Target
  SelectionDAG
  AsmPrinter
  LINK_LIBS
  MLIRPass
  QCCTargetQIR
  QCCToHiSEPQ)

add_subdirectory(Elf2Mem)
