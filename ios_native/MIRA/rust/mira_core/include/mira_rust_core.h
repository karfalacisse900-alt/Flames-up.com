#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t mira_rust_hash_bytes(const uint8_t* bytes, size_t length);
uint32_t mira_rust_link_risk_score(const char* url);
uint32_t mira_rust_text_spam_score(const char* text);

#ifdef __cplusplus
}
#endif
