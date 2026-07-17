configure_file(${CMAKE_CURRENT_SOURCE_DIR}/Config/Config.h.in ${CMAKE_CURRENT_BINARY_DIR}/Config/Config.h)

add_subdirectory(Dialect)
add_subdirectory(Conversion)
