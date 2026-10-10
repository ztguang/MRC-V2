cmake_minimum_required(VERSION 3.20)
project(sp_vision_sim LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(SP_VISION_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../sp_vision_25" CACHE PATH "sp_vision_25 source")
set(GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/godot-cpp" CACHE PATH "godot-cpp source")
set(SP_LOCAL_SYSROOT "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sysroot" CACHE PATH "optional local dependency prefix")

if(EXISTS "${SP_LOCAL_SYSROOT}/usr" AND NOT DEFINED OpenVINO_DIR)
  list(PREPEND CMAKE_PREFIX_PATH "${SP_LOCAL_SYSROOT}/usr")
endif()

find_package(OpenCV REQUIRED)
find_package(OpenVINO CONFIG REQUIRED COMPONENTS Runtime)
find_package(Eigen3 REQUIRED)
find_package(fmt REQUIRED)
find_package(spdlog REQUIRED)
find_package(yaml-cpp REQUIRED)

if(NOT EXISTS "${GODOT_CPP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "godot-cpp was not found at ${GODOT_CPP_DIR}")
endif()
set(GODOTCPP_USE_STATIC_CPP ON CACHE BOOL "Keep the thin Godot extension self-contained" FORCE)
add_subdirectory("${GODOT_CPP_DIR}" godot-cpp EXCLUDE_FROM_ALL)

set(SP_CORE_SOURCES
  ${SP_VISION_ROOT}/tools/extended_kalman_filter.cpp
  ${SP_VISION_ROOT}/tools/img_tools.cpp
  ${SP_VISION_ROOT}/tools/logger.cpp
  ${SP_VISION_ROOT}/tools/math_tools.cpp
  ${SP_VISION_ROOT}/tools/trajectory.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/aimer.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/armor.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/classifier.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/detector.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/planner/planner.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/planner/tinympc/admm.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/planner/tinympc/codegen.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/planner/tinympc/rho_benchmark.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/planner/tinympc/tiny_api.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/shooter.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/solver.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/target.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/tracker.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/voter.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/yolo.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/yolos/yolov5.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/yolos/yolov8.cpp
  ${SP_VISION_ROOT}/tasks/auto_aim/yolos/yolo11.cpp
)

add_library(sp_vision_core STATIC ${SP_CORE_SOURCES})
target_include_directories(sp_vision_core PUBLIC ${SP_VISION_ROOT})
target_link_libraries(sp_vision_core PUBLIC
  ${OpenCV_LIBS}
  openvino::runtime
  Eigen3::Eigen fmt::fmt spdlog::spdlog yaml-cpp
)

if(BUILD_TESTING)
  add_executable(sp_vision_ekf_test tests/extended_kalman_filter_test.cpp)
  target_link_libraries(sp_vision_ekf_test PRIVATE sp_vision_core)
  add_test(NAME sp_vision_ekf_test COMMAND sp_vision_ekf_test)
endif()

add_library(sp_vision_engine SHARED
  src/adaptive_lock_tuner.cpp
  src/engine.cpp
  src/shared_target_board.cpp
  src/sim_detector.cpp
)
target_include_directories(sp_vision_engine PRIVATE src ${SP_VISION_ROOT})
target_link_libraries(sp_vision_engine PRIVATE sp_vision_core)
set_target_properties(sp_vision_engine PROPERTIES
  OUTPUT_NAME sp_vision_engine
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../godot/bin/linux-x86_64"
  BUILD_WITH_INSTALL_RPATH ON
  BUILD_RPATH "$ORIGIN/runtime"
  INSTALL_RPATH "$ORIGIN/runtime"
)

add_executable(sp_vision_worker src/worker_main.cpp)
target_include_directories(sp_vision_worker PRIVATE src)
target_link_libraries(sp_vision_worker PRIVATE sp_vision_engine yaml-cpp)
set_target_properties(sp_vision_worker PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../godot/bin/linux-x86_64"
  BUILD_RPATH "$ORIGIN;$ORIGIN/runtime"
  INSTALL_RPATH "$ORIGIN;$ORIGIN/runtime"
)

add_library(sp_vision_sim SHARED
  src/auto_aim_bridge.cpp
  src/register_types.cpp
)
target_include_directories(sp_vision_sim PRIVATE src ${SP_VISION_ROOT})
target_link_libraries(sp_vision_sim PRIVATE godot-cpp dl)
set_target_properties(sp_vision_sim PROPERTIES
  OUTPUT_NAME sp_vision_sim
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../godot/bin/linux-x86_64"
  BUILD_RPATH "$ORIGIN;$ORIGIN/runtime"
  INSTALL_RPATH "$ORIGIN;$ORIGIN/runtime"
)

# Bundle the OpenVINO + yaml-cpp shared libraries the engine links against into
# bin/linux-x86_64/runtime so RPATH=$ORIGIN/runtime resolves without a system install.
get_target_property(SP_OPENVINO_LIB openvino::runtime IMPORTED_LOCATION_RELEASE)
if(NOT SP_OPENVINO_LIB)
  get_target_property(SP_OPENVINO_LIB openvino::runtime IMPORTED_LOCATION)
endif()
if(SP_OPENVINO_LIB)
  get_filename_component(SP_OPENVINO_LIB_DIR "${SP_OPENVINO_LIB}" DIRECTORY)
  file(GLOB SP_RUNTIME_LIBS
    "${SP_OPENVINO_LIB_DIR}/libopenvino.so*"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_ir_frontend.so*"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_onnx_frontend.so*"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_intel_cpu_plugin.so"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_auto_plugin.so"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_hetero_plugin.so"
    "${SP_OPENVINO_LIB_DIR}/libopenvino_auto_batch_plugin.so"
    "${SP_OPENVINO_LIB_DIR}/libtbb.so*"
    "${SP_OPENVINO_LIB_DIR}/../../3rdparty/tbb/lib/libtbb.so*"
  )
  add_custom_command(TARGET sp_vision_engine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
      "$<TARGET_FILE_DIR:sp_vision_engine>/runtime"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SP_RUNTIME_LIBS}
      "$<TARGET_FILE_DIR:sp_vision_engine>/runtime"
  )
endif()
