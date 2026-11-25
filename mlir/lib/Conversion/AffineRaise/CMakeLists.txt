file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCAffineRaise
  ${CONVERSION_SOURCES}
  LINK_LIBS
  MLIRAffineDialect
  MLIRArithDialect
  MLIRSCFDialect
  MLIRIR
  MLIRPass
  MLIRTransforms)
