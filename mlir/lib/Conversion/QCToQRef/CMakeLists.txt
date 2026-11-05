add_mlir_conversion_library(
  QCCQCToQRef
  ConvertQCToQRef.cpp
  DEPENDS
  QCCQCToQRefIncGen
  QCCQccDialectIncGen
  QCCQccInterfacesIncGen
  QCCQccTypesIncGen
  QCCQccAttrsIncGen
  QCCQccOpsIncGen
  QCCQRefDialectIncGen
  QCCQRefOpsIncGen
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRFuncDialect
  MLIRQCDialect
  QCCQccDialect
  QCCQRefDialect
  # Conversion infra
  MLIRTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
