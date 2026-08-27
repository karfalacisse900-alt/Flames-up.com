import { createPrivateKey, sign } from 'node:crypto';

const API_BASE = 'https://api.appstoreconnect.apple.com';
const bundleID = process.env.APP_STORE_BUNDLE_ID || 'com.captro.app';
const productID = process.env.CAPTRO_SCAN_PRODUCT_ID || 'com.captro.scan.credits.10';
const issuerID = required('APP_STORE_CONNECT_API_ISSUER_ID');
const keyID = required('APP_STORE_CONNECT_API_KEY_ID');
const keyBase64 = required('APP_STORE_CONNECT_API_KEY_BASE64');

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function base64url(value) {
  return Buffer.from(value).toString('base64url');
}

function appStoreToken() {
  const privateKey = createPrivateKey(Buffer.from(keyBase64, 'base64').toString('utf8'));
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyID, typ: 'JWT' }));
  const payload = base64url(JSON.stringify({ iss: issuerID, iat: now, exp: now + 1_000, aud: 'appstoreconnect-v1' }));
  const input = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(input), { key: privateKey, dsaEncoding: 'ieee-p1363' });
  return `${input}.${signature.toString('base64url')}`;
}

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${appStoreToken()}`,
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...options.headers,
    },
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  return { response, body };
}

async function expect(path, options = {}, expected = [200]) {
  const result = await request(path, options);
  if (!expected.includes(result.response.status)) {
    throw new Error(`${options.method || 'GET'} ${path} failed (${result.response.status}): ${JSON.stringify(result.body)}`);
  }
  return result.body;
}

async function findApp() {
  const query = new URLSearchParams({ 'filter[bundleId]': bundleID, limit: '1' });
  const body = await expect(`/v1/apps?${query}`);
  const app = body?.data?.[0];
  if (!app?.id) throw new Error(`No App Store Connect app found for ${bundleID}.`);
  return app.id;
}

async function findPurchase(appID) {
  const query = new URLSearchParams({ 'filter[productId]': productID, limit: '1' });
  const body = await expect(`/v1/apps/${appID}/inAppPurchasesV2?${query}`);
  return body?.data?.[0] || null;
}

async function createPurchase(appID) {
  const payload = {
    data: {
      type: 'inAppPurchases',
      attributes: {
        name: 'Captro Scan Credits 10',
        productId: productID,
        inAppPurchaseType: 'CONSUMABLE',
      },
      relationships: {
        app: { data: { type: 'apps', id: appID } },
      },
    },
  };
  const body = await expect('/v2/inAppPurchases', { method: 'POST', body: JSON.stringify(payload) }, [201]);
  return body.data;
}

async function ensureAvailability(purchaseID) {
  const existing = await request(`/v2/inAppPurchases/${purchaseID}/inAppPurchaseAvailability`);
  if (existing.response.ok && existing.body?.data?.id) {
    console.log(`Availability already exists: ${existing.body.data.id}`);
    return;
  }
  if (existing.response.status !== 404) {
    throw new Error(`Could not read availability (${existing.response.status}): ${JSON.stringify(existing.body)}`);
  }

  const territories = await expect('/v1/territories?limit=200');
  const availableTerritories = (territories?.data || [])
    .filter((territory) => territory?.id)
    .map((territory) => ({ type: 'territories', id: territory.id }));
  if (!availableTerritories.length) {
    throw new Error('Apple did not return any App Store territories.');
  }

  const payload = {
    data: {
      type: 'inAppPurchaseAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        availableTerritories: { data: availableTerritories },
        inAppPurchase: { data: { type: 'inAppPurchases', id: purchaseID } },
      },
    },
  };
  const body = await expect('/v1/inAppPurchaseAvailabilities', {
    method: 'POST',
    body: JSON.stringify(payload),
  }, [201]);
  console.log(`Created availability for ${availableTerritories.length} territories (${body.data.id}).`);
}

async function ensureLocalization(purchaseID) {
  const existing = await expect(`/v2/inAppPurchases/${purchaseID}/inAppPurchaseLocalizations?limit=50`);
  if (existing?.data?.some((entry) => entry.attributes?.locale === 'en-US')) return;
  const payload = {
    data: {
      type: 'inAppPurchaseLocalizations',
      attributes: {
        locale: 'en-US',
        name: '10 Scan Verifications',
        description: 'Verify 10 receipts or invoices with Captro Scan.',
      },
      relationships: {
        inAppPurchaseV2: { data: { type: 'inAppPurchases', id: purchaseID } },
      },
    },
  };
  await expect('/v1/inAppPurchaseLocalizations', { method: 'POST', body: JSON.stringify(payload) }, [201]);
}

async function currentPriceSchedule(purchaseID) {
  const result = await request(`/v2/inAppPurchases/${purchaseID}/iapPriceSchedule?include=baseTerritory,manualPrices`);
  if (result.response.status === 404) return null;
  if (!result.response.ok) {
    throw new Error(`Could not read price schedule (${result.response.status}): ${JSON.stringify(result.body)}`);
  }
  return result.body?.data || null;
}

async function findUSPricePoint(purchaseID) {
  const query = new URLSearchParams({
    'filter[territory]': 'USA',
    'fields[inAppPurchasePricePoints]': 'customerPrice,territory',
    limit: '200',
  });
  const body = await expect(`/v2/inAppPurchases/${purchaseID}/pricePoints?${query}`);
  const point = body?.data?.find((entry) => Number(entry.attributes?.customerPrice) === 0.99);
  if (!point?.id) throw new Error('Apple did not return a $0.99 USA price point for this purchase.');
  return point.id;
}

async function ensurePrice(purchaseID) {
  const schedule = await currentPriceSchedule(purchaseID);
  if (schedule?.id) {
    console.log(`Price schedule already exists: ${schedule.id}`);
    return;
  }
  const pricePointID = await findUSPricePoint(purchaseID);
  const temporaryPriceID = 'captro-scan-initial-price';
  const payload = {
    data: {
      type: 'inAppPurchasePriceSchedules',
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: purchaseID } },
        baseTerritory: { data: { type: 'territories', id: 'USA' } },
        manualPrices: { data: [{ type: 'inAppPurchasePrices', id: temporaryPriceID }] },
      },
    },
    included: [{
      type: 'inAppPurchasePrices',
      id: temporaryPriceID,
      attributes: { startDate: null },
      relationships: {
        inAppPurchaseV2: { data: { type: 'inAppPurchases', id: purchaseID } },
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: pricePointID } },
      },
    }],
  };
  await expect('/v1/inAppPurchasePriceSchedules', { method: 'POST', body: JSON.stringify(payload) }, [201]);
}

const appID = await findApp();
let purchase = await findPurchase(appID);
if (!purchase) {
  purchase = await createPurchase(appID);
  console.log(`Created ${productID} (${purchase.id}).`);
} else {
  console.log(`Using existing ${productID} (${purchase.id}).`);
}
await ensureAvailability(purchase.id);
await ensureLocalization(purchase.id);
await ensurePrice(purchase.id);
const finalPurchase = await expect(`/v2/inAppPurchases/${purchase.id}`);
console.log(JSON.stringify({
  appID,
  purchaseID: purchase.id,
  productID,
  state: finalPurchase?.data?.attributes?.state,
}, null, 2));
