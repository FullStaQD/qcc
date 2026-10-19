add_subdirectory(Magic)

add_mlir_library(
  QCCQuantumDevice
  QuantumDeviceRegistry.cpp
  LINK_LIBS
  MLIRIR
  MLIRPass
  QCCMagicExport
  QCCQuantumDeviceMagic)
