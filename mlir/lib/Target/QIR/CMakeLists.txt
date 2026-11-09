add_mlir_library(
  QCCTargetQIR
  QIRTarget.cpp
  LINK_LIBS
  MLIRPass
  MLIRTransforms
  # Dialects
  MLIRFuncDialect
  MLIRArithDialect
  QCCAuxDialect
  MLIRQCDialect
  # Passes
  MLIRArithTransforms
  QCCAuxOutputRecording
  QCCToQIR)
