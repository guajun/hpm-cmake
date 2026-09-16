# The pinned SDK passes map/script paths as raw target_link_libraries flags.
# Move just these two flags to target_link_options, which quotes spaced paths.
# Keep the vendor checkout and all selected linker scripts unchanged.
get_target_property(_hpm_app_links ${APP_ELF_NAME} LINK_LIBRARIES)
set(_hpm_app_links_fixed "")
foreach(_hpm_link IN LISTS _hpm_app_links)
  if(_hpm_link MATCHES "^-Wl,-Map=(.*)$")
    target_link_options(${APP_ELF_NAME} PRIVATE "-Wl,-Map,${CMAKE_MATCH_1}")
  else()
    list(APPEND _hpm_app_links_fixed "${_hpm_link}")
  endif()
endforeach()
set_property(TARGET ${APP_ELF_NAME} PROPERTY LINK_LIBRARIES "${_hpm_app_links_fixed}")

get_target_property(_hpm_sdk_links ${HPM_SDK_LIB_ITF} INTERFACE_LINK_LIBRARIES)
set(_hpm_sdk_links_fixed "")
foreach(_hpm_link IN LISTS _hpm_sdk_links)
  if(_hpm_link MATCHES "^-T (.*)$")
    target_link_options(${HPM_SDK_LIB_ITF} INTERFACE "SHELL:-T \"${CMAKE_MATCH_1}\"")
  else()
    list(APPEND _hpm_sdk_links_fixed "${_hpm_link}")
  endif()
endforeach()
set_property(TARGET ${HPM_SDK_LIB_ITF} PROPERTY INTERFACE_LINK_LIBRARIES "${_hpm_sdk_links_fixed}")
