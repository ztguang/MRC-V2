#include "sim_detector.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace sp_sim {
namespace {

struct Blob {
  cv::Point2f center;
  float height = 0.0f;
  float width = 0.0f;
  float top_y = 0.0f;
  float bottom_y = 0.0f;
};

std::vector<Blob> find_color_blobs(const cv::Mat & bgr, bool want_blue)
{
  cv::Mat hsv;
  cv::cvtColor(bgr, hsv, cv::COLOR_BGR2HSV);
  cv::Mat mask;
  if (want_blue) {
    cv::inRange(hsv, cv::Scalar(90, 60, 80), cv::Scalar(140, 255, 255), mask);
  } else {
    cv::Mat m1, m2;
    cv::inRange(hsv, cv::Scalar(0, 70, 80), cv::Scalar(12, 255, 255), m1);
    cv::inRange(hsv, cv::Scalar(165, 70, 80), cv::Scalar(180, 255, 255), m2);
    mask = m1 | m2;
  }
  // Also accept pure high-value unshaded emission (low saturation possible).
  cv::Mat vchan;
  std::vector<cv::Mat> ch;
  cv::split(hsv, ch);
  cv::Mat bright;
  if (want_blue) {
    cv::inRange(bgr, cv::Scalar(120, 0, 0), cv::Scalar(255, 120, 120), bright);
  } else {
    cv::inRange(bgr, cv::Scalar(0, 0, 120), cv::Scalar(120, 120, 255), bright);
  }
  mask |= bright;
  cv::morphologyEx(
    mask, mask, cv::MORPH_CLOSE,
    cv::getStructuringElement(cv::MORPH_RECT, {3, 7}), {-1, -1}, 1);

  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
  std::vector<Blob> blobs;
  for (const auto & c : contours) {
    const auto rect = cv::boundingRect(c);
    if (rect.height < 4 || rect.width < 1) continue;
    if (rect.height < rect.width * 1.2f) continue;  // prefer vertical
    if (static_cast<float>(rect.area()) < 12.0f) continue;
    Blob b;
    b.center = cv::Point2f(
      rect.x + rect.width * 0.5f, rect.y + rect.height * 0.5f);
    b.height = static_cast<float>(rect.height);
    b.width = static_cast<float>(rect.width);
    b.top_y = static_cast<float>(rect.y);
    b.bottom_y = static_cast<float>(rect.y + rect.height);
    blobs.push_back(b);
  }
  std::sort(blobs.begin(), blobs.end(), [](const Blob & a, const Blob & b) {
    return a.center.x < b.center.x;
  });
  return blobs;
}

auto_aim::Armor make_armor_from_pair(
  const Blob & left, const Blob & right, auto_aim::Color color, float confidence)
{
  const cv::Point2f lt(left.center.x, left.top_y);
  const cv::Point2f lb(left.center.x, left.bottom_y);
  const cv::Point2f rt(right.center.x, right.top_y);
  const cv::Point2f rb(right.center.x, right.bottom_y);
  std::vector<cv::Point2f> pts{lt, rt, rb, lb};
  const float min_x = std::min(lt.x, rt.x) - 2.0f;
  const float max_x = std::max(lb.x, rb.x) + 2.0f;
  const float min_y = std::min(lt.y, rt.y) - 2.0f;
  const float max_y = std::max(lb.y, rb.y) + 2.0f;
  const cv::Rect box(
    static_cast<int>(min_x), static_cast<int>(min_y),
    std::max(1, static_cast<int>(max_x - min_x)),
    std::max(1, static_cast<int>(max_y - min_y)));
  // color_id: 0=blue, 1=red in YOLO-style ctor used below; num_id=1 (infantry one)
  const int color_id = (color == auto_aim::Color::blue) ? 0 : 1;
  return auto_aim::Armor(color_id, /*num_id=*/2, confidence, box, pts);  // infantry small
}

}  // namespace

std::list<auto_aim::Armor> detect_sim_armors(
  const cv::Mat & bgr, const std::string & enemy_color, double min_confidence)
{
  std::list<auto_aim::Armor> out;
  if (bgr.empty()) return out;
  const bool want_blue = enemy_color != "red";  // hunt blue when enemy is blue
  const auto color = want_blue ? auto_aim::Color::blue : auto_aim::Color::red;
  auto blobs = find_color_blobs(bgr, want_blue);
  if (blobs.size() < 2) return out;

  // Pair neighboring vertical blobs with similar height and close lateral spacing.
  for (std::size_t i = 0; i + 1 < blobs.size(); ++i) {
    for (std::size_t j = i + 1; j < blobs.size() && j < i + 4; ++j) {
      const auto & a = blobs[i];
      const auto & b = blobs[j];
      const float dx = std::abs(b.center.x - a.center.x);
      const float dy = std::abs(b.center.y - a.center.y);
      const float h = 0.5f * (a.height + b.height);
      if (dx < h * 0.4f || dx > h * 4.5f) continue;
      if (dy > h * 0.85f) continue;
      const float hr = std::max(a.height, b.height) / std::max(1.0f, std::min(a.height, b.height));
      if (hr > 2.5f) continue;
      const float conf = std::clamp(0.55f + 0.1f * (3.0f - hr), 0.35f, 0.95f);
      if (conf < static_cast<float>(min_confidence) * 0.5f) continue;
      const Blob & left = (a.center.x <= b.center.x) ? a : b;
      const Blob & right = (a.center.x <= b.center.x) ? b : a;
      out.push_back(make_armor_from_pair(left, right, color, conf));
    }
  }
  return out;
}

}  // namespace sp_sim
