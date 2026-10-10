#pragma once

#include <list>
#include <opencv2/opencv.hpp>
#include <string>

#include "tasks/auto_aim/armor.hpp"

namespace sp_sim {

// Lightweight simulation armor detector for Godot-rendered lightbars.
// Used when real YOLO (trained on physical RM images) finds nothing.
// Detects bright red/blue vertical strip pairs approximating infantry armor.
std::list<auto_aim::Armor> detect_sim_armors(
  const cv::Mat & bgr, const std::string & enemy_color, double min_confidence = 0.35);

}  // namespace sp_sim
