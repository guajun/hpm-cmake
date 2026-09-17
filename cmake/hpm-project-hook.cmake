# Loaded locally through CMakeUserPresets.json; no application file is modified.
include_guard(GLOBAL)
set_property(GLOBAL PROPERTY HPM_CMAKE_COMPAT_FILE "${CMAKE_CURRENT_LIST_DIR}/hpm-sdk-compat.cmake")
function(_hpm_cmake_finalize)
  get_property(_hpm_compat GLOBAL PROPERTY HPM_CMAKE_COMPAT_FILE)
  include("${_hpm_compat}")
endfunction()
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL _hpm_cmake_finalize)
