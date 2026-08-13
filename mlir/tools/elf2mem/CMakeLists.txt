set(LLVM_LINK_COMPONENTS Object Support)

add_llvm_executable(elf2mem elf2mem.cpp DEPENDS QCCSupport)

target_link_libraries(elf2mem PRIVATE QCCSupport)

llvm_update_compile_flags(elf2mem)
