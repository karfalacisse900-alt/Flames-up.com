#pragma once

#include <string>
#include <unordered_set>
#include <vector>

namespace flames {

struct PlacePoint {
  std::string id;
  std::string name;
  std::string vicinity;
  std::vector<std::string> types;
  double lat = 0.0;
  double lng = 0.0;
  double rating = 0.0;
  int ratingsTotal = 0;
};

struct ClusterPoint {
  std::string id;
  double lat = 0.0;
  double lng = 0.0;
  int count = 0;
  std::vector<PlacePoint> places;
};

class GeoSearchCore {
 public:
  static std::vector<PlacePoint> RankQuery(
      const std::vector<PlacePoint>& places,
      const std::string& query,
      double userLat,
      double userLng,
      int limit);

  static std::vector<ClusterPoint> ClusterByGrid(
      const std::vector<PlacePoint>& places,
      int zoomLevel,
      double baseRadiusMeters = 180.0);

 private:
  static double HaversineKm(double lat1, double lng1, double lat2, double lng2);
  static std::string Normalize(std::string value);
  static std::unordered_set<std::string> Tokens(const std::string& value);
};

}  // namespace flames

