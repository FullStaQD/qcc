set(LLVM_LINK_COMPONENTS Object Support)

add_llvm_executable(hisepq-elf2mem hisepq-elf2mem.cpp DEPENDS QCCTargetHiSEPQMem)

target_link_libraries(hisepq-elf2mem PRIVATE QCCTargetHiSEPQMem)

llvm_update_compile_flags(hisepq-elf2mem)
