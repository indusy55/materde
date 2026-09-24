cmake_minimum_required(VERSION 3.10)

# Generates a wayland-scanner client header + private code pair.
#
# PATCH_NS_KEYWORD (optional):
#   wayland-scanner names the last argument of wlr-layer-shell's
#   get_layer_surface "namespace", which is a reserved keyword in C++. Because
#   the generated header is included from C++ sources, rename the parameter to
#   "ns" right after generation.
function(generate_wayland_client_protocol)
  cmake_parse_arguments(ARGS "PATCH_NS_KEYWORD" "PROTOCOL_FILE" "CODE_FILE;HEADER_FILE" ${ARGN})

  find_program(WaylandScannerExec NAMES wayland-scanner)

  get_filename_component(_xml_file ${ARGS_PROTOCOL_FILE} ABSOLUTE)
  set_source_files_properties(${ARGS_HEADER_FILE} GENERATED)
  set_source_files_properties(${ARGS_CODE_FILE} GENERATED)

  # Keep this as a CMake list without ";" inside the sed expressions: every
  # element of the list becomes one argv of the generated build rule.
  set(_header_patch_commands "")
  if(ARGS_PATCH_NS_KEYWORD)
    set(_header_patch_commands
      COMMAND sed -i
              -e "s/\\*namespace)/\\*ns)/"
              -e "s/, namespace)/, ns)/"
              ${ARGS_HEADER_FILE})
  endif()

  add_custom_command(
    OUTPUT ${ARGS_HEADER_FILE}
    COMMAND ${WaylandScannerExec} client-header ${_xml_file} ${ARGS_HEADER_FILE}
    ${_header_patch_commands}
    DEPENDS ${_xml_file} VERBATIM
  )

  add_custom_command(
    OUTPUT ${ARGS_CODE_FILE}
    COMMAND ${WaylandScannerExec} private-code ${_xml_file} ${ARGS_CODE_FILE}
    DEPENDS ${_xml_file} ${ARGS_HEADER_FILE} VERBATIM
  )
endfunction()
