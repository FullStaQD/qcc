add_mlir_library(
  QCCTargetQIR
  QIRTarget.cpp
  DEPENDS
  AuxOutputRecordingIncGen
  QCCToQIRIncGen
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
  MLIRQCToQIR
  QCCAuxOutputRecording
  QCCToQIR)
