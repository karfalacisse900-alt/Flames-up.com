import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

function section(source, startNeedle, endNeedle) {
  const start = source.indexOf(startNeedle);
  const end = source.indexOf(endNeedle, start + startNeedle.length);
  assert.ok(start >= 0, `missing section start: ${startNeedle}`);
  assert.ok(end > start, `missing section end: ${endNeedle}`);
  return source.slice(start, end);
}

test('authenticated upload intent enforces real Cloudflare image/video constraints', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const validation = section(worker, 'const CLOUDFLARE_IMAGES_MAX_BYTES', 'function defaultModerationScores');
  const intent = section(worker, "api.post('/media/upload-intent'", "api.post('/media/complete'");

  assert.match(validation, /CLOUDFLARE_IMAGES_MAX_BYTES = 10_000_000/);
  assert.match(validation, /CLOUDFLARE_STREAM_BASIC_UPLOAD_MAX_BYTES = 200_000_000/);
  assert.match(validation, /fileSize <= 0/);
  assert.match(validation, /ALLOWED_IMAGE_TYPES/);
  assert.match(validation, /ALLOWED_VIDEO_TYPES/);
  assert.match(validation, /extensionAllowed/);

  assert.match(intent, /authMiddleware/);
  assert.match(intent, /SUPABASE_SERVICE_ROLE_KEY|supabaseInsertMediaAsset/);
  assert.match(intent, /CLOUDFLARE_IMAGES_TOKEN|cloudflareImagesToken/);
  assert.match(intent, /CLOUDFLARE_STREAM_TOKEN|cloudflareStreamToken/);
  assert.match(intent, /!\/\^\[a-f0-9\]\{64\}\$\/\.test\(sha256Hash\)/);
  assert.match(intent, /userId,\s*mediaId,/s);
  assert.match(intent, /source: 'aura_ios'/);
  assert.match(intent, /creator: userId/);
  assert.match(intent, /supabaseInsertMediaAsset/);
});

test('completion trusts Cloudflare bytes/state, not client assertions', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const providerVerification = section(worker, 'type VerifiedProviderUpload', 'function moderationSampleUrls');
  const complete = section(worker, "api.post('/media/complete'", "api.get('/media/:mediaId/status'");

  assert.match(providerVerification, /images\/v1\/\$\{encodeURIComponent\(storageKey\)\}/);
  assert.match(providerVerification, /images\/v1\/\$\{encodeURIComponent\(storageKey\)\}\/blob/);
  assert.match(providerVerification, /stream\/\$\{encodeURIComponent\(storageKey\)\}/);
  assert.match(providerVerification, /providerMetadataMatchesAsset/);
  assert.match(providerVerification, /cleanText\(video\.creator, 160\) !== userId/);
  assert.doesNotMatch(providerVerification, /actualChecksum !== expectedChecksum/);
  assert.match(providerVerification, /actualSize !== expectedSize/);
  assert.match(providerVerification, /ALLOWED_IMAGE_TYPES\.has\(detectedMimeType\)/);
  assert.match(providerVerification, /durationSeconds > 60\.5/);

  assert.match(complete, /authMiddleware/);
  assert.match(complete, /supabaseReadMediaAsset\(c, mediaId, userId\)/);
  assert.match(complete, /sha256Hash !== expectedChecksum/);
  assert.match(complete, /verifyCloudflareProviderUpload\(c\.env, asset, userId\)/);
  assert.match(complete, /file_size: verifiedUpload\.fileSize/);
  assert.match(complete, /mime_type: verifiedUpload\.mimeType/);
  assert.match(complete, /provider_verified: true/);
  assert.match(complete, /provider_observed_sha256: verifiedUpload\.sha256Hash/);
  assert.match(complete, /client_intent_sha256: expectedChecksum/);
});

test('approved owned image or video asset is attached and persisted authoritatively', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const approval = section(worker, 'async function approvedMediaAssetsForPost', 'async function supabaseAdminDeleteSafe');
  const create = section(worker, "api.post('/posts'", "api.get('/posts/feed'");
  const persistence = section(worker, 'function supabasePrimaryPostCreatePayload', 'async function supabaseExistingPostByClientRequest');

  assert.match(approval, /user_id: postgrestEqFilter\(userId\)/);
  assert.match(approval, /requestedMediaIds\.map\(\(mediaId\) => byId\.get\(mediaId\)\)/);
  assert.match(approval, /moderation_status\) !== 'approved'/);
  assert.match(approval, /upload_status, 40\) !== 'uploaded'/);
  assert.match(approval, /MEDIA_ALREADY_ATTACHED/);
  assert.match(approval, /type === 'image' \? provider !== 'images' : provider !== 'stream'/);

  assert.doesNotMatch(create, /FEED_POSTS_PHOTO_ONLY/);
  assert.match(create, /mediaTypes = mediaApproval\.assets\.map/);
  assert.match(create, /mediaAssetPublicUrl\(c\.env, asset\)/);
  assert.match(create, /legacy_post_id: id/);
  assert.match(create, /user_id: postgrestEqFilter\(userId\)/);

  assert.match(persistence, /media: mediaUrls\.map/);
  assert.match(persistence, /media_asset_ids: parseJsonArray\(input\.mediaAssetIds\)/);
  assert.match(persistence, /type: mediaTypes\[index\]/);
  assert.match(worker, /media_asset_ids: parseJsonArray\(\(metadata as any\)\.media_asset_ids/);
  assert.match(worker, /if \(provider === 'stream'\) return `cfstream:\$\{key\}`/);
});

test('iOS sends authenticated intent/complete requests but no bearer token to one-time provider URL', async () => {
  const [service, client] = await Promise.all([
    read('ios_native/MIRA/Sources/MIRANative/Services/MIRAMediaUploadService.swift'),
    read('ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift'),
  ]);
  const directUpload = section(client, 'public func uploadMultipart<T: Decodable>(\n    to absoluteURL', 'private func multipartBody');

  assert.match(service, /import CryptoKit/);
  assert.match(service, /SHA256\.hash\(data: uploadData\)/);
  assert.match(service, /let sha256Hash: String/);
  assert.match(service, /\/media\/upload-intent/);
  assert.match(service, /\/media\/complete/);
  assert.match(service, /data\.count <= 10_000_000/);
  assert.match(service, /data\.count <= 200_000_000/);
  assert.match(service, /detectedImageMimeType/);
  assert.match(service, /detectedVideoContainer/);

  assert.match(directUpload, /authorize: Bool = false/);
  assert.match(directUpload, /validateDirectUploadURL/);
  assert.match(directUpload, /if authorize, let token/);
  assert.doesNotMatch(service, /SUPABASE_SERVICE_ROLE_KEY|CLOUDFLARE_IMAGES_TOKEN|CLOUDFLARE_STREAM_TOKEN/);
});

test('public health exposes configuration booleans without secret values', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const health = section(worker, "api.get('/health'", "api.get('/database/status'");
  assert.match(health, /cloudflare_images:\s*\{\s*configured:/s);
  assert.match(health, /cloudflare_stream:\s*\{\s*configured:/s);
  assert.doesNotMatch(health, /token:\s*cloudflare|SUPABASE_SERVICE_ROLE_KEY\s*[:,]/);
});
