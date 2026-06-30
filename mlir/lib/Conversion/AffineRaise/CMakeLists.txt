file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCAffineRaise
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCAffineRaiseIncGen
  LINK_LIBS
  MLIRAffineDialect
  MLIRArithDialect
  MLIRSCFDialect
  MLIRIR
  MLIRPass
  MLIRTransforms)

mqt_mlir_target_use_project_options(QCCAffineRaise)
