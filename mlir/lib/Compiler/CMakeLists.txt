add_mlir_library(
  QCCCompiler
  Compiler.cpp
  LINK_LIBS
  MLIRPass
  MLIRTransforms
  # Dialects
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRAffineDialect
  MLIRTensorDialect
  MLIRLinalgDialect
  MLIRBufferizationDialect
  QCCJaspDialect
  # Passes
  MLIRLinalgTransforms
  MLIRSCFTransforms
  MLIRAffineToStandard
  MLIRAffineTransforms
  MLIRTensorTransforms
  MLIRBufferizationTransforms
  QCCAffineRaise
  QCCJaspToQC
  QCCQccTransforms
  QCCQuantumDevice
  # Extensions/Interfaces
  MLIRTransformUtils)
