#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t mira_rust_hash_bytes(const uint8_t* bytes, size_t length);
uint32_t mira_rust_link_risk_score(const char* url);
uint32_t mira_rust_text_spam_score(const char* text);

/*
 * Wallet FFI (see rust/mira_core/src/wallet_ffi.rs for the full contract). None of these
 * functions ever return a private key or seed once a wallet handle exists -- only the
 * one-time mnemonic backup produced by mira_wallet_create/mira_wallet_restore_from_mnemonic
 * exposes key material, and only as an explicit out-parameter the caller must display once and
 * not persist itself. `network` is 0 (mainnet), 1 (testnet), or 2 (devnet) everywhere below.
 *
 * Every `void*` handle here is opaque: never dereference it, only pass it back into these
 * functions. Every returned `char*` (including the out-parameters) must be released with
 * mira_free_string exactly once. Wallet handles must be released with mira_wallet_free exactly
 * once. Freed handles/strings must never be reused.
 */

/* Frees a string this module returned. Safe to call with NULL. */
void mira_free_string(char* ptr);

/* Generates a new wallet. On success returns a non-NULL handle and writes a 24-word BIP39
 * backup phrase into *out_mnemonic. On failure returns NULL and writes an error message into
 * *out_mnemonic instead -- check the handle, not the message, to detect failure. */
void* mira_wallet_create(uint8_t network, char** out_mnemonic);

/* Restores a wallet from its 24-word BIP39 recovery phrase. On success returns a non-NULL
 * handle and leaves *out_error untouched. On failure returns NULL and writes an error message
 * into *out_error. */
void* mira_wallet_restore_from_mnemonic(const char* mnemonic, uint8_t network, char** out_error);

/* Releases a wallet handle and zeroizes its private key material. Safe to call with NULL. */
void mira_wallet_free(void* handle);

/* Returns {"ok":true,"data":{"network":...,"address":...,"publicKeyHex":...}} (or an
 * {"ok":false,"error":...} envelope) describing the wallet's public identity. Never includes
 * private key material. */
char* mira_wallet_identity_json(void* handle);

/* Encrypts and atomically saves the wallet at `path` using Aura's versioned Argon2id +
 * XChaCha20-Poly1305 wallet envelope. The password is not retained. Returns a JSON envelope
 * describing the save result; release it with mira_free_string. */
char* mira_wallet_save_json(void* handle, const char* path, const char* password);

/* Loads and authenticates an encrypted Aura wallet file. On failure returns NULL and writes an
 * error string into *out_error. The password is not retained. */
void* mira_wallet_load(const char* path, const char* password, char** out_error);

/* Returns 1 if `address` is a well-formed, checksum-valid Aura address, 0 otherwise (including
 * for NULL). */
int32_t mira_aura_validate_address(const char* address);

/* Builds an unsigned Aura PoW Devnet v2 transfer body from a JSON object with fields: network
 * (int), chainIdHashHex, senderAddress, recipientAddress, amountAtoms, feeAtoms, nonce,
 * validUntilHeight (all six of the last as decimal-integer strings, to avoid JSON-number
 * precision loss). Returns {"ok":true,"data":{"unsignedBodyHex":...,"signingHashHex":...}} or
 * an {"ok":false,"error":...} envelope. Performs no signing and touches no wallet handle. */
char* mira_aura_build_unsigned_transfer_v2_json(const char* params_json);

/* Signs an unsigned body (as hex, from mira_aura_build_unsigned_transfer_v2_json) with the
 * given wallet's private key entirely inside this process. Returns
 * {"ok":true,"data":{"signedTransferHex":...,"witnessIdHex":...,"intentIdHex":...}} or an
 * {"ok":false,"error":...} envelope (for example if the body's sender is not this wallet's
 * address). */
char* mira_wallet_sign_transfer_v2_json(void* handle, const char* unsigned_body_hex);
char* mira_wallet_sign_purchase_proof_v2_json(void* handle, const char* request_json);
char* mira_wallet_authorize_feedback_v1_json(void* handle, const char* request_json);

#ifdef __cplusplus
}
#endif
