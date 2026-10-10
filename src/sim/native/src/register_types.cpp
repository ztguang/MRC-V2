#include "auto_aim_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_sp_vision_sim(ModuleInitializationLevel level)
{
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
    ClassDB::register_class<sp_sim::AutoAimBridge>();
  }
}

void uninitialize_sp_vision_sim(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT sp_vision_sim_init(
  GDExtensionInterfaceGetProcAddress get_proc_address,
  const GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization)
{
  GDExtensionBinding::InitObject init_obj(get_proc_address, library, initialization);
  init_obj.register_initializer(initialize_sp_vision_sim);
  init_obj.register_terminator(uninitialize_sp_vision_sim);
  init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return init_obj.init();
}
}

