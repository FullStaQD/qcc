add_executable(qcc-opt qcc-opt.cpp)
target_link_libraries(
  qcc-opt
  PRIVATE MLIRIR
          MLIROptLib
          MLIRSupport
          # Dialects
          MLIRAffineDialect
          MLIRFuncDialect
          MLIRArithDialect
          MLIRSCFDialect
          MLIRTensorDialect
          MLIRLinalgDialect
          MLIRMemRefDialect
          MLIRBufferizationDialect
          MLIRDLTIDialect
          # `mlir/Conversion/Passes.h` transitively pulls in openmp stuff. GCC at -O0 emits those unused symbols into
          # object files which then cause unknown symbols errors during linking if we do not add the openmp dialect
          # library.
          MLIROpenMPDialect
          MLIRVectorDialect
          QCCJaspDialect
          QCCAuxDialect
          QCCQVecDialect
          # Passes
          MLIRMemRefTransforms
          MLIRArithTransforms
          MLIRFuncTransforms
          MLIRLinalgTransforms
          MLIRTensorTransforms
          MLIRBufferizationTransforms
          QCCJaspToQC
          MLIRFuncToLLVM
          MLIRVectorToLLVMPass
          QCCQVecTransforms
          QCCQCOToQVec
          QCCToHiSEPQ
          QCCToQIR
          QCCAuxOutputRecording
          QCCAffineRaise
          # Extensions/Interfaces
          MLIRFuncInlinerExtension
          MLIRTransformUtils
          MLIRQCDialect
          MLIRQCODialect)
