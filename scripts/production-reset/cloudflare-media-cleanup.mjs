#!/usr/bin/env node
/*
 * Captro Cloudflare media cleanup.
 *
 * Dry-run by default. It reads Supabase app_media_assets and deletes matching
 * Cloudflare Images / Stream assets only when EXECUTE_DELETE=true and
 * CONFIRM_PRODUCTION_RESET=CONFIRM_PRODUCTION_RESET.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   CLOUDFLARE_ACCOUNT_ID
 *   CLOUDFLARE_API_TOKEN
 *
 * Optional:
 *   EXECUTE_DELETE=true
 *   CLOUDFLARE_MEDIA_ASSETS_FILE=/path/to/wrangler-d1-media-assets.json
 */

const required = [
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'CLOUDFLARE_ACCOUNT_ID',
  'CLOUDFLARE_API_TOKEN',
];

for (const key of required) {
  if (!process.env[key]) {
    console.error(`${key} is required.`);
    process.exit(1);
  }
}

const executeDelete = process.env.EXECUTE_DELETE === 'true';
if (executeDelete && process.env.CONFIRM_PRODUCTION_RESET !== 'CONFIRM_PRODUCTION_RESET') {
  console.error('Refusing delete: CONFIRM_PRODUCTION_RESET=CONFIRM_PRODUCTION_RESET is required.');
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL.replace(/\/$/, '');
const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
const authHeaders = {
  Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,
  'Content-Type': 'application/json',
};

async function fetchAssets() {
  const assets = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const url = `${supabaseUrl}/rest/v1/app_media_assets?select=id,storage_provider,storage_key,media_type,public_url,metadata&limit=${limit}&offset=${offset}`;
    const res = await fetch(url, {
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    });
    if (!res.ok) throw new Error(`Supabase asset fetch failed: ${res.status} ${await res.text()}`);
    const page = await res.json();
    assets.push(...page);
    if (page.length < limit) break;
    offset += limit;
  }

  return assets;
}

async function fetchLegacyAssetsFromFile() {
  const filePath = process.env.CLOUDFLARE_MEDIA_ASSETS_FILE;
  if (!filePath) return [];
  const fs = await import('node:fs/promises');
  const buffer = await fs.readFile(filePath);
  const raw = buffer[0] === 0xff && buffer[1] === 0xfe
    ? buffer.toString('utf16le').replace(/^\uFEFF/, '')
    : buffer.toString('utf8').replace(/^\uFEFF/, '');
  const parsed = JSON.parse(raw);
  const commandResults = Array.isArray(parsed) ? parsed : [];
  return commandResults
    .flatMap((entry) => Array.isArray(entry?.results) ? entry.results : [])
    .map((row) => ({
      id: row.id,
      storage_provider: row.storage_provider,
      storage_key: row.storage_key,
      media_type: row.media_type,
      public_url: row.public_url,
      source: 'legacy_d1',
    }))
    .filter((asset) => asset.storage_provider && asset.storage_key);
}

function normalizeProvider(provider = '') {
  return String(provider).toLowerCase().replace(/^cloudflare_/, '');
}

async function deleteCloudflareImage(asset) {
  const imageId = asset.storage_key;
  if (!imageId) return { skipped: true, reason: 'missing storage_key' };
  if (!executeDelete) return { dryRun: true, id: imageId };

  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v1/${encodeURIComponent(imageId)}`, {
    method: 'DELETE',
    headers: authHeaders,
  });
  return { ok: res.ok, status: res.status, body: await res.text() };
}

async function deleteCloudflareStream(asset) {
  const uid = asset.storage_key;
  if (!uid) return { skipped: true, reason: 'missing storage_key' };
  if (!executeDelete) return { dryRun: true, id: uid };

  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${encodeURIComponent(uid)}`, {
    method: 'DELETE',
    headers: authHeaders,
  });
  return { ok: res.ok, status: res.status, body: await res.text() };
}

const supabaseAssets = await fetchAssets();
const legacyAssets = await fetchLegacyAssetsFromFile();
const uniqueAssets = new Map();
for (const asset of [...supabaseAssets, ...legacyAssets]) {
  const key = `${normalizeProvider(asset.storage_provider)}:${asset.storage_key}`;
  if (!uniqueAssets.has(key)) uniqueAssets.set(key, asset);
}
const assets = Array.from(uniqueAssets.values());
const summary = {
  executeDelete,
  total: assets.length,
  supabaseAssets: supabaseAssets.length,
  legacyAssets: legacyAssets.length,
  images: 0,
  stream: 0,
  r2OrUnknown: 0,
  deletedOrWouldDelete: 0,
  failures: 0,
};

for (const asset of assets) {
  const provider = normalizeProvider(asset.storage_provider);
  let result;

  if (provider === 'images' || provider === 'image') {
    summary.images += 1;
    result = await deleteCloudflareImage(asset);
  } else if (provider === 'stream') {
    summary.stream += 1;
    result = await deleteCloudflareStream(asset);
  } else {
    summary.r2OrUnknown += 1;
    result = { skipped: true, reason: `manual R2 cleanup or unknown provider: ${asset.storage_provider}` };
  }

  if (result.ok || result.dryRun) summary.deletedOrWouldDelete += 1;
  if (result.ok === false) summary.failures += 1;
  console.log(JSON.stringify({ asset_id: asset.id, provider: asset.storage_provider, storage_key: asset.storage_key, result }));
}

console.log(JSON.stringify(summary, null, 2));
