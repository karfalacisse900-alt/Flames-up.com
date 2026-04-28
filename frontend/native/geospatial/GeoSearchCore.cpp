#include "GeoSearchCore.h"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <map>
#include <sstream>

namespace {

constexpr double kEarthRadiusKm = 6371.0;
constexpr double kPi = 3.14159265358979323846;
constexpr double kWorldExtentMeters = 20037508.34;

double ToRad(double value) {
  return value * (kPi / 180.0);
}

double Clamp(double value, double low, double high) {
  return std::max(low, std::min(value, high));
}

double CellSizeMetersForZoom(int zoomLevel, double baseAtZoom14) {
  const int bounded = std::max(4, std::min(20, zoomLevel));
  const double scale = std::pow(2.0, 14.0 - static_cast<double>(bounded));
  return std::max(40.0, baseAtZoom14 * scale);
}

std::pair<double, double> ToMercator(double lat, double lng) {
  const double x = (lng * kWorldExtentMeters) / 180.0;
  const double y = (std::log(std::tan(((90.0 + lat) * kPi) / 360.0)) / (kPi / 180.0)) *
                   (kWorldExtentMeters / 180.0);
  return {x, y};
}

std::pair<double, double> FromMercator(double x, double y) {
  const double lng = (x / kWorldExtentMeters) * 180.0;
  const double lat =
      (180.0 / kPi) * (2.0 * std::atan(std::exp((y / kWorldExtentMeters) * kPi)) - kPi / 2.0);
  return {lat, lng};
}

}  // namespace

namespace flames {

double GeoSearchCore::HaversineKm(double lat1, double lng1, double lat2, double lng2) {
  const double dLat = ToRad(lat2 - lat1);
  const double dLng = ToRad(lng2 - lng1);
  const double a = std::sin(dLat / 2.0) * std::sin(dLat / 2.0) +
                   std::cos(ToRad(lat1)) * std::cos(ToRad(lat2)) *
                       std::sin(dLng / 2.0) * std::sin(dLng / 2.0);
  const double c = 2.0 * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
  return kEarthRadiusKm * c;
}

std::string GeoSearchCore::Normalize(std::string value) {
  for (char& c : value) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (c == ',' || c == '.' || c == '-') c = ' ';
  }
  return value;
}

std::unordered_set<std::string> GeoSearchCore::Tokens(const std::string& value) {
  std::unordered_set<std::string> out;
  std::stringstream ss(Normalize(value));
  std::string token;
  while (ss >> token) {
    out.insert(token);
  }
  return out;
}

std::vector<PlacePoint> GeoSearchCore::RankQuery(
    const std::vector<PlacePoint>& places,
    const std::string& query,
    double userLat,
    double userLng,
    int limit) {
  if (places.empty()) return {};
  if (limit <= 0) limit = 120;

  const std::string normalizedQuery = Normalize(query);
  if (normalizedQuery.empty()) {
    return std::vector<PlacePoint>(places.begin(), places.begin() + std::min<int>(limit, places.size()));
  }

  const auto queryTokens = Tokens(normalizedQuery);
  struct ScoredPlace {
    PlacePoint place;
    double score;
  };
  std::vector<ScoredPlace> scored;
  scored.reserve(places.size());

  for (const auto& place : places) {
    const std::string name = Normalize(place.name);
    const std::string vicinity = Normalize(place.vicinity);
    std::string typeText;
    for (const auto& t : place.types) {
      if (!typeText.empty()) typeText += " ";
      typeText += Normalize(t);
    }
    const std::string haystack = name + " " + vicinity + " " + typeText;

    double textScore = 0.0;
    if (name.rfind(normalizedQuery, 0) == 0) textScore += 80.0;
    if (name.find(normalizedQuery) != std::string::npos) textScore += 55.0;
    if (vicinity.find(normalizedQuery) != std::string::npos) textScore += 30.0;
    if (typeText.find(normalizedQuery) != std::string::npos) textScore += 24.0;

    for (const auto& token : queryTokens) {
      if (name.find(token) != std::string::npos) textScore += 18.0;
      else if (haystack.find(token) != std::string::npos) textScore += 10.0;
    }

    const double qualityScore = std::max(0.0, place.rating * 5.0) + std::log10(1.0 + place.ratingsTotal) * 5.0;
    const double distanceKm = HaversineKm(userLat, userLng, place.lat, place.lng);
    const double proximityScore = std::max(0.0, 30.0 - (distanceKm * 2.2));

    const double total = textScore + qualityScore + proximityScore;
    if (total > 0.0) scored.push_back({place, total});
  }

  std::sort(scored.begin(), scored.end(), [](const ScoredPlace& a, const ScoredPlace& b) {
    return a.score > b.score;
  });

  std::vector<PlacePoint> out;
  out.reserve(std::min<int>(limit, scored.size()));
  for (int i = 0; i < static_cast<int>(scored.size()) && i < limit; ++i) {
    out.push_back(scored[i].place);
  }
  return out;
}

std::vector<ClusterPoint> GeoSearchCore::ClusterByGrid(
    const std::vector<PlacePoint>& places,
    int zoomLevel,
    double baseRadiusMeters) {
  if (places.empty()) return {};
  const double cellSizeMeters = CellSizeMetersForZoom(zoomLevel, baseRadiusMeters);

  std::map<std::pair<int, int>, std::vector<PlacePoint>> buckets;
  for (const auto& place : places) {
    auto [x, y] = ToMercator(place.lat, place.lng);
    const int gx = static_cast<int>(std::floor(x / cellSizeMeters));
    const int gy = static_cast<int>(std::floor(y / cellSizeMeters));
    buckets[{gx, gy}].push_back(place);
  }

  std::vector<ClusterPoint> clusters;
  clusters.reserve(buckets.size());
  int index = 0;
  for (const auto& entry : buckets) {
    const auto& bucketPlaces = entry.second;
    double xTotal = 0.0;
    double yTotal = 0.0;
    for (const auto& place : bucketPlaces) {
      auto [x, y] = ToMercator(place.lat, place.lng);
      xTotal += x;
      yTotal += y;
    }

    auto [centerLat, centerLng] =
        FromMercator(xTotal / static_cast<double>(bucketPlaces.size()),
                     yTotal / static_cast<double>(bucketPlaces.size()));

    ClusterPoint cluster;
    cluster.id = "cluster-" + std::to_string(index++);
    cluster.lat = centerLat;
    cluster.lng = centerLng;
    cluster.count = static_cast<int>(bucketPlaces.size());
    cluster.places = bucketPlaces;
    clusters.push_back(cluster);
  }

  std::sort(clusters.begin(), clusters.end(), [](const ClusterPoint& a, const ClusterPoint& b) {
    return a.count > b.count;
  });
  return clusters;
}

}  // namespace flames

