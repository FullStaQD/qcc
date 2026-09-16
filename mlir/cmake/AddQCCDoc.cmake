# Umbrella target that collects all qcc-generated (dialect/pass) documentation.
add_custom_target(qcc-doc COMMENT "Generating qcc dialect/pass documentation")
set_target_properties(qcc-doc PROPERTIES FOLDER "QCC/Docs")

# Mirrors add_mlir_doc()'s signature: doc_filename, output_file, output_directory, command (e.g. -gen-pass-doc), plus
# any extra tablegen arguments. We cannot use `add_mlir_doc` directly as it hardcodes the output path to
# `${MLIR_BINARY_DIR}/docs/` which collapses to `/docs/` out-of-tree (e.g. for us).
function(add_qcc_doc doc_filename output_file output_directory command)
  # implementation almost identical to `add_mlir_doc`.
  set(LLVM_TARGET_DEFINITIONS ${doc_filename}.td)
  # The MLIR docs use Hugo, so we allow Hugo specific features here, matching add_mlir_doc.
  tablegen(MLIR ${output_file}.md ${command} -allow-hugo-specific-features ${ARGN})
  set(GEN_DOC_FILE ${PROJECT_BINARY_DIR}/docs/${output_directory}${output_file}.md)
  add_custom_command(
    OUTPUT ${GEN_DOC_FILE}
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/${output_file}.md ${GEN_DOC_FILE}
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${output_file}.md)
  add_custom_target(${output_file}DocGen DEPENDS ${GEN_DOC_FILE})
  set_target_properties(${output_file}DocGen PROPERTIES FOLDER "QCC/Docs")
  add_dependencies(qcc-doc ${output_file}DocGen)
endfunction()

# Renders the markdown collected by `qcc-doc` into a static HTML site via Hugo, using the (theme-less) site scaffold in
# docs/hugo/.
find_program(HUGO_EXECUTABLE hugo)
if(HUGO_EXECUTABLE)
  add_custom_target(
    qcc-doc-html
    COMMAND ${HUGO_EXECUTABLE} --source ${PROJECT_SOURCE_DIR}/docs/hugo --contentDir ${PROJECT_BINARY_DIR}/docs
            --destination ${PROJECT_BINARY_DIR}/docs-html --noBuildLock # don't drop a .hugo_build.lock file into the
                                                                        # (checked-in) source scaffold
    DEPENDS qcc-doc
    COMMENT "Rendering qcc docs to HTML (${PROJECT_BINARY_DIR}/docs-html/index.html)"
    VERBATIM)
  set_target_properties(qcc-doc-html PROPERTIES FOLDER "QCC/Docs")
else()
  message(STATUS "hugo not found -- the 'qcc-doc-html' target will not be available "
                 "('qcc-doc' still generates the markdown on its own)")
endif()
