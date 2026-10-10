#include <Eigen/Dense>

#include <cmath>
#include <iostream>

#include "tools/extended_kalman_filter.hpp"

namespace
{
tools::ExtendedKalmanFilter make_filter()
{
  return tools::ExtendedKalmanFilter(Eigen::Vector4d::Zero(), Eigen::Matrix4d::Identity());
}

bool near(double lhs, double rhs, double tolerance = 1e-9)
{
  return std::abs(lhs - rhs) <= tolerance;
}
}  // namespace

int main()
{
  const Eigen::Matrix4d H = Eigen::Matrix4d::Identity();
  const Eigen::Matrix4d R = Eigen::Matrix4d::Identity();

  auto accepted = make_filter();
  accepted.update(Eigen::Vector4d{4.0, 0.0, 0.0, 0.0}, H, R);
  if (!near(accepted.last_nis, 8.0) || accepted.recent_nis_failures.size() != 1 ||
      accepted.recent_nis_failures.back() != 0 || accepted.data.at("nis_fail") != 0.0) {
    std::cerr << "NIS below the df=4 95% limit was rejected\n";
    return 1;
  }

  auto rejected = make_filter();
  rejected.update(Eigen::Vector4d{5.0, 0.0, 0.0, 0.0}, H, R);
  if (!near(rejected.last_nis, 12.5) || rejected.recent_nis_failures.size() != 1 ||
      rejected.recent_nis_failures.back() != 1 || rejected.data.at("nis_fail") != 1.0) {
    std::cerr << "NIS above the df=4 95% limit was accepted\n";
    return 1;
  }

  for (std::size_t i = 0; i < rejected.window_size + 10; ++i) {
    rejected.update(Eigen::Vector4d::Zero(), H, R);
  }
  if (rejected.recent_nis_failures.size() != rejected.window_size ||
      rejected.data.at("nis_fail") != 0.0) {
    std::cerr << "NIS rolling window or per-update failure state is incorrect\n";
    return 1;
  }

  return 0;
}
