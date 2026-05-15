#include "flames_core.h"

#include <algorithm>
#include <cmath>

namespace {

double clamp01(double value) {
    return std::max(0.0, std::min(1.0, value));
}

double wilson_lower_bound(double positive, double total) {
    if (total <= 0.0) return 0.0;

    constexpr double z = 1.281551565545;
    const double p_hat = positive / total;
    const double z2 = z * z;
    const double denom = 1.0 + z2 / total;
    const double center = p_hat + z2 / (2.0 * total);
    const double margin = z * std::sqrt((p_hat * (1.0 - p_hat) + z2 / (4.0 * total)) / total);

    return clamp01((center - margin) / denom);
}

}  // namespace

extern "C" double flames_cpp_engagement_score(
    double likes,
    double comments,
    double shares,
    double saves,
    double impressions
) {
    const double weighted = likes + comments * 2.0 + shares * 3.0 + saves * 2.5;
    const double total = std::max(impressions, weighted + 20.0);
    const double quality = wilson_lower_bound(std::min(weighted, total), total);
    const double depth = clamp01(std::log10(1.0 + weighted) / 3.0);

    return clamp01(quality * 0.72 + depth * 0.28);
}
