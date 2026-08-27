add_subdirectory(IR)
add_subdirectory(Transforms)

add_mlir_library(
  QCCQVecMachine
  QVecMachine.cpp
  LINK_LIBS
  PRIVATE
  MLIRIR
  MLIRSupport
  MLIRDataLayoutInterfaces
  MLIRDLTIDialect)
