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
  MLIRTransforms
  MLIRArithToLLVM
  MLIRControlFlowToLLVM
  MLIRFuncToLLVM
  MLIRSCFToControlFlow
  MLIRVectorToLLVMPass
  # `mlir/Conversion/Passes.h` transitively pulls in openmp stuff. GCC at -O0 emits those unused symbols into object
  # files which then cause unknown symbols errors during linking if we do not add the openmp dialect library.
  MLIROpenMPDialect
  MLIRQCToQCO
  QCCTargetQIR
  QCCQCOToQVec
  QCCQVecTransforms
  QCCToHiSEPQ)

add_subdirectory(Elf2Mem)
