# The commit for --version, as clang does it: VCSRevision.h defines QCC_REVISION, or leaves it undefined outside a git
# checkout. It is regenerated whenever HEAD moves, but only rewritten when the commit changed.
find_first_existing_vc_file("${PROJECT_SOURCE_DIR}" qcc_vc)
set(version_inc "${CMAKE_CURRENT_BINARY_DIR}/VCSRevision.h")
set(generate_vcs_version_script "${LLVM_CMAKE_DIR}/GenerateVersionFromVCS.cmake")
add_custom_command(
  OUTPUT "${version_inc}"
  DEPENDS "${qcc_vc}" "${generate_vcs_version_script}"
  COMMAND ${CMAKE_COMMAND} "-DNAMES=QCC" "-DQCC_SOURCE_DIR=${PROJECT_SOURCE_DIR}" "-DHEADER_FILE=${version_inc}" -P
          "${generate_vcs_version_script}")
set_source_files_properties("${version_inc}" PROPERTIES GENERATED TRUE HEADER_FILE_ONLY TRUE)

include_directories(${CMAKE_CURRENT_BINARY_DIR})

add_mlir_library(QCCSupport Version.cpp ${version_inc} LINK_COMPONENTS Support)
