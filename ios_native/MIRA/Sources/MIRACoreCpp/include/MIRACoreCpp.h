#pragma once

#include <stdint.h>
#include <stddef.h>

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

/* Small deterministic Rust call used to prove the statically linked mobile bridge is available.
 * It accepts public diagnostic bytes only and returns no sensitive material. */
uint64_t mira_rust_hash_bytes(const uint8_t* bytes, size_t length);

/* Rust Aura wallet FFI. These declarations are surfaced through this Clang module so Swift can
 * call the existing `aura-wallet` implementation. Handles are opaque, returned strings must be
 * freed exactly once, and no function exposes a raw private key. */
void mira_free_string(char* ptr);
void* mira_wallet_create(uint8_t network, char** out_mnemonic);
void* mira_wallet_restore_from_mnemonic(const char* mnemonic, uint8_t network, char** out_error);
void mira_wallet_free(void* handle);
char* mira_wallet_identity_json(void* handle);
char* mira_wallet_save_json(void* handle, const char* path, const char* password);
void* mira_wallet_load(const char* path, const char* password, char** out_error);
int32_t mira_aura_validate_address(const char* address);
char* mira_aura_build_unsigned_transfer_v2_json(const char* params_json);
char* mira_wallet_sign_transfer_v2_json(void* handle, const char* unsigned_body_hex);

#ifdef __cplusplus
}
#endif
