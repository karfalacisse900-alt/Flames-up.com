#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char* mira_plan_media_json(
  const char* uri,
  const char* mime_type,
  const char* file_name,
  double file_size,
  double width,
  double height,
  const char* preset
);

double mira_score_feed_item(
  double likes,
  double comments,
  double saves,
  double shares,
  double views,
  double age_hours,
  int is_followed,
  int is_video
);

uint64_t mira_stable_hash64(const char* value);

const char* mira_native_design_profile_json(void);

#ifdef __cplusplus
}
#endif
