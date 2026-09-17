# Loaded by CMAKE_PROJECT_INCLUDE. Application CMakeLists.txt stays untouched.
include_guard(GLOBAL)
get_filename_component(_hpm_project_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
file(SHA256 "${_hpm_project_root}/hpm-lock.json" _hpm_lock_hash)
set(_hpm_stamp "${_hpm_project_root}/.hpm/synced-lock.sha256")
if(NOT EXISTS "${_hpm_stamp}")
  message(FATAL_ERROR "Local environment missing. Rerun the project's one-line installer.")
endif()
file(READ "${_hpm_stamp}" _hpm_synced_hash)
string(STRIP "${_hpm_synced_hash}" _hpm_synced_hash)
if(NOT _hpm_synced_hash STREQUAL _hpm_lock_hash)
  message(FATAL_ERROR "Dependency lock changed. Rerun the one-line installer, then configure with --fresh.")
endif()
set_property(DIRECTORY "${CMAKE_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${_hpm_project_root}/hpm-lock.json")
# SDK versions may call project() before finishing their own target setup.
# Apply the compatibility adapter after the application's configure has finished.
set_property(GLOBAL PROPERTY HPM_CMAKE_COMPAT_FILE "${CMAKE_CURRENT_LIST_DIR}/hpm-sdk-compat.cmake")
function(_hpm_cmake_finalize)
  get_property(_hpm_compat GLOBAL PROPERTY HPM_CMAKE_COMPAT_FILE)
  include("${_hpm_compat}")
endfunction()
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL _hpm_cmake_finalize)
