add_subdirectory(IR)
add_subdirectory(Transforms)

add_mlir_library(
  QCCHiSEPQHardware
  HiSEPQHardware.cpp
  LINK_LIBS
  PRIVATE
  MLIRIR
  MLIRSupport
  MLIRDataLayoutInterfaces
  MLIRDLTIDialect)
