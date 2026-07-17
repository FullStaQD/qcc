# TODO: The HiSEP-Q backend is the only component that may depend on the HiSEP-Q
# LLVM fork. Add the fork-only headers/libraries here (e.g. via
# target_link_libraries) when the actual pipeline lands.
add_mlir_library(QCCTargetHiSEPQ HiSEPQTarget.cpp LINK_LIBS MLIRPass)
