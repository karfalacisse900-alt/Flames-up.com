import assert from 'node:assert/strict';
import test from 'node:test';
import { allowedCloudflareDirectUploadUrl } from '../src/media-upload.ts';

test('Stream accepts current and legacy Cloudflare direct-upload hosts only over HTTPS', () => {
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'https://upload.cloudflarestream.com/abc123'), true);
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'https://upload.videodelivery.net/abc123'), true);
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'http://upload.cloudflarestream.com/abc123'), false);
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'https://upload.cloudflarestream.com.attacker.test/abc123'), false);
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'https://attacker.test@upload.cloudflarestream.com/abc123'), false);
  assert.equal(allowedCloudflareDirectUploadUrl('stream', 'https://upload.imagedelivery.net/abc123'), false);
});

test('Images allowlist stays limited to Cloudflare Images', () => {
  assert.equal(allowedCloudflareDirectUploadUrl('images', 'https://upload.imagedelivery.net/abc123'), true);
  assert.equal(allowedCloudflareDirectUploadUrl('images', 'https://upload.cloudflarestream.com/abc123'), false);
  assert.equal(allowedCloudflareDirectUploadUrl('images', 'not-a-url'), false);
});
