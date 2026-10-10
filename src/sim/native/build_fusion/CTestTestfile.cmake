# CMake generated Testfile for 
# Source directory: /root/lunwen/sim/native
# Build directory: /root/lunwen/sim/native/build_fusion
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test([=[sp_vision_ekf_test]=] "/root/lunwen/sim/native/build_fusion/sp_vision_ekf_test")
set_tests_properties([=[sp_vision_ekf_test]=] PROPERTIES  _BACKTRACE_TRIPLES "/root/lunwen/sim/native/CMakeLists.txt;68;add_test;/root/lunwen/sim/native/CMakeLists.txt;0;")
subdirs("godot-cpp")
