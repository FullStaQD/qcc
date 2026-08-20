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
          QCCJaspDialect
          QCCAuxDialect
          # Passes
          MLIRMemRefTransforms
          MLIRArithTransforms
          MLIRFuncTransforms
          MLIRLinalgTransforms
          MLIRTensorTransforms
          MLIRBufferizationTransforms
          QCCJaspToQC
          MLIRFuncToLLVM
          QCCToHiSEPQ
          QCCToQIR
          QCCAuxOutputRecording
          QCCAffineRaise
          # Extensions/Interfaces
          MLIRFuncInlinerExtension
          MLIRTransformUtils
          MLIRQCDialect)
