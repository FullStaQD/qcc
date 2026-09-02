add_mlir_dialect_library(
  QCCPrelimHLEPDialect
  PrelimHLEPDialect.cpp
  # 'HamiltonianAttr.cpp' and 'LinearityChecker.cpp' are textually included by 'PrelimHLEPDialect.cpp' rather than
  # compiled on their own.
  PARTIAL_SOURCES_INTENDED
  DEPENDS
  QCCPrelimHLEPDialectIncGen
  QCCPrelimHLEPTypesIncGen
  QCCPrelimHLEPAttrsIncGen
  QCCPrelimHLEPOpsIncGen
  LINK_LIBS
  PRIVATE
  MLIRIR
  MLIRSupport
  MLIRInferTypeOpInterface
  MLIRSideEffectInterfaces
  MLIRFunctionInterfaces
  MLIRControlFlowInterfaces)
