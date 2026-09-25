cmake_minimum_required(VERSION 3.14)
project(flutter_video_thumbnail_plus LANGUAGES CXX)

set(PLUGIN_NAME "flutter_video_thumbnail_plus_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_video_thumbnail_plus_plugin.cpp"
  "flutter_video_thumbnail_plus_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin mfplat mfreadwrite mfuuid windowscodecs shlwapi)

set(flutter_video_thumbnail_plus_bundled_libraries
  ""
  PARENT_SCOPE
)
