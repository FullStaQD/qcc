add_mlir_library(
  QCCCompiler
  Compiler.cpp
  DEPENDS
  JaspToQCIncGen
  MojoResidueToStdIncGen
  PrelimHLEPToQCOIncGen
  QCCAffineRaiseIncGen
  QCCPrelimHLEPTransformsIncGen
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
  QCCPrelimHLEPDialect
  # Passes
  MLIRLinalgTransforms
  MLIRSCFTransforms
  MLIRAffineToStandard
  MLIRAffineTransforms
  MLIRTensorTransforms
  MLIRBufferizationTransforms
  QCCAffineRaise
  QCCJaspToQC
  QCCMojoResidueToStd
  QCCPrelimHLEPToQCO
  QCCPrelimHLEPTransforms
  # Extensions/Interfaces
  MLIRTransformUtils)
