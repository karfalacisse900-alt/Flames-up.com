import { Hono } from 'hono';

export interface AuraWorkerEnv {
  KV?: KVNamespace;
  AURA_MOBILE_GATEWAY_URL?: string;
  AURA_MOBILE_GATEWAY_URLS?: string;
  AURA_MOBILE_GATEWAY_TOKEN?: string;
  VERYFI_CLIENT_ID?: string;
  VERYFI_CLIENT_SECRET?: string;
  VERYFI_USERNAME?: string;
  VERYFI_API_KEY?: string;
  VERYFI_BASE_URL?: string;
  AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64?: string;
  AURA_PROOF_NULLIFIER_KEY_BASE64?: string;
}

type AuthMiddleware = (c: any, next: () => Promise<void>) => Promise<Response | void>;
type RateLimiter = (
  c: any,
  scope: string,
  userId: string,
  limit: number,
  seconds: number,
) => Promise<Response | null>;

const MAX_DOCUMENT_BYTES = 12 * 1024 * 1024;
const MAX_PROVIDER_RESPONSE_BYTES = 8 * 1024 * 1024;
const MAX_GATEWAY_RESPONSE_BYTES = 1024 * 1024;
const MAX_GATEWAY_ORIGINS = 3;
const VERYFI_DOCUMENTS_PATH = '/api/v8/partner/documents';
const ALLOWED_GATEWAY_PATH = /^\/(network|chain\/status|fees|address\/[a-zA-Z0-9]+\/(balance|nonce|transactions)|transactions\/broadcast|proofs\/broadcast|transaction\/[a-fA-F0-9]+|proof\/[a-fA-F0-9]+(?:\/(?:feedback-eligibility|feedback))?)$/;
const EXPECTED_AURA_NETWORK = Object.freeze({
  protocolVersion: '2',
  network: 'devnet',
  chainId: 'aura-devnet-pow-v2-proof1',
  chainIdHash: 'f2d47ba05f05c086e8e5507ef7be2fa764effaefacab13bd613543e4163575b9',
  genesisHash: '75b26958bc3414b7f32370179c077710b7f35e1c05df21d0f8038d363ecc8c24',
  mainnetAvailable: false,
});
const AURA_DEVNET_NETWORK_ID = 0x41555203;
const AURA_PURCHASE_PROOF_VERSION = 1;
const AURA_PURCHASE_PROOF_TYPE = 1;
const AURA_PURCHASE_VERIFIER_PUBLIC_KEY_HEX = '6f13ffdfb47b0ef1affcbdc0b9152189b47b6978cd260d7994bcf7df36a20de1';

function boundedText(value: unknown, maximum = 1024): string | null {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text ? text.slice(0, maximum) : null;
}

function nested(source: any, path: string): any {
  return path.split('.').reduce((current, key) => current?.[key], source);
}

function first(source: any, paths: string[]): any {
  for (const path of paths) {
    const value = nested(source, path);
    if (value !== null && value !== undefined && value !== '') return value;
  }
  return null;
}

function firstBool(source: any, paths: string[]): boolean | null {
  const value = first(source, paths);
  if (typeof value === 'boolean') return value;
  if (value === 1 || value === '1' || String(value).toLowerCase() === 'true') return true;
  if (value === 0 || value === '0' || String(value).toLowerCase() === 'false') return false;
  return null;
}

function exactDecimal(value: unknown): string | null {
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : null;
  const text = boundedText(value, 128);
  return text && /^-?\d+(?:\.\d+)?$/.test(text) ? text : null;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function arrayBufferToBase64(value: ArrayBuffer): string {
  return bytesToBase64(new Uint8Array(value));
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value.trim());
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  return base64ToBytes(padded);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(value: string, expectedBytes: number): Uint8Array {
  if (!new RegExp(`^[a-fA-F0-9]{${expectedBytes * 2}}$`).test(value)) throw new Error('INVALID_HEX');
  return Uint8Array.from(value.match(/../g)!, (byte) => Number.parseInt(byte, 16));
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const output = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function littleEndian(value: bigint, bytes: number): Uint8Array {
  const output = new Uint8Array(bytes);
  let remaining = value;
  for (let index = 0; index < bytes; index += 1) {
    output[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  if (remaining !== 0n) throw new Error('INTEGER_OVERFLOW');
  return output;
}

async function taggedHash(tag: string, parts: Uint8Array[]): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const tagBytes = encoder.encode(tag);
  const framed = [
    encoder.encode('AURA\0'),
    littleEndian(BigInt(tagBytes.length), 8),
    tagBytes,
    ...parts.flatMap((part) => [littleEndian(BigInt(part.length), 8), part]),
  ];
  return new Uint8Array(await crypto.subtle.digest('SHA-256', concatBytes(...framed)));
}

async function hmacCommitment(keyBytes: Uint8Array, domain: string, fields: unknown[]): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const payload = new TextEncoder().encode(JSON.stringify([domain, ...fields]));
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, payload));
}

function normalizedCommitmentText(value: unknown): string {
  return String(value ?? '').normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' ').slice(0, 1024);
}

async function purchaseProofAttestation(
  env: AuraWorkerEnv,
  userId: string,
  ownerPublicKeyHex: string,
  document: any,
  normalized: any,
): Promise<any> {
  const privateKeyBytes = base64ToBytes(env.AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64 || '');
  const nullifierKey = base64ToBytes(env.AURA_PROOF_NULLIFIER_KEY_BASE64 || '');
  if (privateKeyBytes.length < 48 || nullifierKey.length < 32) throw new Error('PROOF_CONFIGURATION_INVALID');
  const ownerPublicKey = hexToBytes(ownerPublicKeyHex, 32);
  const ownerDigest = await taggedHash('address/ed25519/v1', [ownerPublicKey]);
  const ownerAddress = concatBytes(littleEndian(BigInt(AURA_DEVNET_NETWORK_ID), 4), ownerDigest.slice(0, 20));
  const lineItems = Array.isArray(normalized.lineItems)
    ? normalized.lineItems.map((line: any) => [line.description, line.sku, line.quantity, line.unitPrice, line.total])
    : [];
  const merchant = normalized.merchant || {};
  const subjectCommitment = await hmacCommitment(nullifierKey, 'aura-proof-subject-v1', [userId, ownerPublicKeyHex.toLowerCase()]);
  const businessCommitment = await hmacCommitment(nullifierKey, 'aura-proof-business-v1', [
    normalizedCommitmentText(merchant.name),
    normalizedCommitmentText(merchant.storeNumber),
    normalizedCommitmentText(merchant.address),
  ]);
  const productCommitment = lineItems.length > 0
    ? await hmacCommitment(nullifierKey, 'aura-proof-products-v1', lineItems)
    : new Uint8Array(32);
  const locationCommitment = (merchant.address || merchant.storeNumber)
    ? await hmacCommitment(nullifierKey, 'aura-proof-location-v1', [
      normalizedCommitmentText(merchant.address),
      normalizedCommitmentText(merchant.storeNumber),
    ])
    : new Uint8Array(32);
  const receiptIdentity = [
    normalizedCommitmentText(merchant.name),
    normalizedCommitmentText(merchant.storeNumber),
    normalizedCommitmentText(normalized.receiptNumber),
    normalizedCommitmentText(normalized.date),
    normalizedCommitmentText(normalized.time),
    normalizedCommitmentText(normalized.currency),
    normalizedCommitmentText(normalized.total),
    normalizedCommitmentText(first(document, ['id', 'document_id'])),
  ];
  if (!normalized.receiptNumber) receiptIdentity.push(normalized.rawResponseSha256);
  const receiptNullifier = await hmacCommitment(nullifierKey, 'aura-receipt-nullifier-v1', receiptIdentity);
  const timestampSeconds = BigInt(Math.floor(Date.now() / 1000));
  const verifierPublicKey = hexToBytes(AURA_PURCHASE_VERIFIER_PUBLIC_KEY_HEX, 32);
  const claimBytes = concatBytes(
    littleEndian(BigInt(AURA_PURCHASE_PROOF_VERSION), 2),
    littleEndian(BigInt(AURA_DEVNET_NETWORK_ID), 4),
    hexToBytes(EXPECTED_AURA_NETWORK.chainIdHash, 32),
    Uint8Array.of(AURA_PURCHASE_PROOF_TYPE),
    ownerAddress,
    subjectCommitment,
    businessCommitment,
    productCommitment,
    locationCommitment,
    receiptNullifier,
    Uint8Array.of(normalized.verificationLevel),
    hexToBytes(normalized.rawResponseSha256, 32),
    littleEndian(timestampSeconds, 8),
    verifierPublicKey,
  );
  const privateKey = await crypto.subtle.importKey('pkcs8', privateKeyBytes, { name: 'Ed25519' }, true, ['sign']);
  const jwk = await crypto.subtle.exportKey('jwk', privateKey) as JsonWebKey;
  if (!jwk.x || bytesToHex(base64UrlToBytes(jwk.x)) !== AURA_PURCHASE_VERIFIER_PUBLIC_KEY_HEX) {
    throw new Error('PROOF_VERIFIER_KEY_MISMATCH');
  }
  const signingHash = await taggedHash('proof/purchase/verifier-signing/v1', [claimBytes]);
  const signature = new Uint8Array(await crypto.subtle.sign('Ed25519', privateKey, signingHash));
  const proofId = await taggedHash('proof/purchase/id/v1', [claimBytes]);
  return {
    version: AURA_PURCHASE_PROOF_VERSION,
    proofType: 'PURCHASE',
    proofId: bytesToHex(proofId),
    receiptNullifier: bytesToHex(receiptNullifier),
    verificationLevel: normalized.verificationLevel,
    ownerPublicKeyHex: ownerPublicKeyHex.toLowerCase(),
    attestedProofHex: bytesToHex(concatBytes(claimBytes, signature)),
    timestampSeconds: timestampSeconds.toString(),
  };
}

function detectedDocumentType(bytes: Uint8Array): string | null {
  if (bytes.length >= 5 && String.fromCharCode(...bytes.subarray(0, 5)) === '%PDF-') return 'application/pdf';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value)) return 'image/png';
  if (bytes.length >= 12 && String.fromCharCode(...bytes.subarray(4, 8)) === 'ftyp') {
    const brand = String.fromCharCode(...bytes.subarray(8, 12));
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(brand)) return 'image/heic';
  }
  return null;
}

function safeFilename(name: unknown, mimeType: string): string {
  const fallback = mimeType === 'application/pdf' ? 'aura-document.pdf' : mimeType === 'image/png' ? 'aura-document.png' : mimeType === 'image/heic' ? 'aura-document.heic' : 'aura-document.jpg';
  const clean = String(name || fallback).replace(/[\r\n\0]/g, '').replace(/[^a-zA-Z0-9._ -]/g, '_').slice(0, 160);
  return clean || fallback;
}

function configuredVeryfi(env: AuraWorkerEnv): boolean {
  return Boolean(env.VERYFI_CLIENT_ID?.trim() && env.VERYFI_API_KEY?.trim());
}

function configuredPurchaseProof(env: AuraWorkerEnv): boolean {
  return Boolean(
    env.AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64?.trim()
    && env.AURA_PROOF_NULLIFIER_KEY_BASE64?.trim(),
  );
}

function veryfiEndpoint(env: AuraWorkerEnv): URL {
  const base = new URL(env.VERYFI_BASE_URL?.trim() || 'https://api.veryfi.com');
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) {
    throw new Error('VERYFI_CONFIGURATION_INVALID');
  }
  if (base.hostname !== 'api.veryfi.com') throw new Error('VERYFI_CONFIGURATION_INVALID');
  base.pathname = VERYFI_DOCUMENTS_PATH;
  return base;
}

async function veryfiSignature(secret: string, request: any, timestamp: number): Promise<string> {
  const canonical = `timestamp:${timestamp},file_name:${JSON.stringify(request.file_name)},file_data:"${request.file_data}",document_type:${JSON.stringify(request.document_type)},boost_mode:false,async:false,auto_delete:true,confidence_details:false,allowed_async_enrichments:[]`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return arrayBufferToBase64(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(canonical)));
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function fraudSignals(document: any) {
  const fraud = first(document, ['meta.fraud', 'fraud', 'fraud_info']) || {};
  const types: string[] | null = Array.isArray(fraud?.types)
    ? fraud.types.slice(0, 64).map((value: unknown) => String(value).toLowerCase())
    : null;
  const details = fraud?.details && typeof fraud.details === 'object' ? fraud.details : {};
  const signal = (name: string, explicitPaths: string[] = []): boolean | null => {
    const explicit = firstBool(document, explicitPaths);
    const detailKey = name.replaceAll(' ', '_').toLowerCase();
    if (Object.prototype.hasOwnProperty.call(details, detailKey) || types?.includes(name) || explicit === true) return true;
    if (explicit === false || types !== null) return false;
    return null;
  };
  const pageAIValues = Array.isArray(document?.meta?.pages)
    ? document.meta.pages.map((page: any) => firstBool(page, ['ai_generated.value'])).filter((value: unknown) => value !== null)
    : [];
  const pageAI = pageAIValues.includes(true) ? true : pageAIValues.includes(false) ? false : null;
  const pageScreenshot = Array.isArray(document?.meta?.pages) && document.meta.pages.some((page: any) =>
    ['mobile_screenshot', 'other_screenshot', 'ai_generated'].includes(String(page?.screenshot?.type || '').toLowerCase()),
  ) ? true : null;
  const decision = boundedText(first(document, ['meta.fraud.decision', 'meta.fraud.color', 'fraud.decision', 'fraud.color', 'fraud_info.decision', 'fraud_info.color']), 64);
  return {
    decision,
    score: exactDecimal(first(document, ['meta.fraud.score', 'fraud.score', 'fraud_info.score'])),
    digitalTampering: signal('digital tampering', ['fraud.digital_tampering', 'fraud.digitalTampering', 'fraud_info.digital_tampering']),
    aiGenerated: pageAI === true ? true : (signal('ai generated', ['fraud.ai_generated', 'fraud.aiGenerated', 'fraud.generated_document', 'fraud_info.ai_generated']) ?? pageAI),
    screenshot: pageScreenshot === true ? true : (signal('screenshot', ['fraud.screenshot', 'fraud.is_screenshot', 'fraud_info.screenshot']) ?? pageScreenshot),
    invalidQr: signal('invalid qr data', ['fraud.invalid_qr_data', 'fraud.invalidQrData', 'fraud_info.invalid_qr_data']),
    vendorLayoutMismatch: signal('vendor layout mismatch', ['fraud.vendor_layout_mismatch', 'fraud.vendorLayoutMismatch', 'fraud_info.vendor_layout_mismatch']),
    notADocument: signal('not a document', ['fraud.not_a_document', 'fraud.notADocument', 'fraud_info.not_a_document']),
  };
}

function normalizeLineItems(document: any): any[] {
  const values = Array.isArray(document?.line_items) ? document.line_items : [];
  return values.slice(0, 256).map((line: any) => ({
    description: boundedText(first(line, ['description', 'text', 'full_description']), 512),
    sku: boundedText(first(line, ['sku', 'upc']), 128),
    quantity: exactDecimal(line?.quantity),
    unitPrice: exactDecimal(first(line, ['price', 'unit_price'])),
    total: exactDecimal(first(line, ['total', 'subtotal'])),
  }));
}

function normalizeBarcodes(document: any): any[] {
  const values = Array.isArray(document?.barcodes) ? document.barcodes : [];
  return values.slice(0, 32).map((barcode: any) => ({
    data: boundedText(first(barcode, ['data', 'value']), 512),
    type: boundedText(first(barcode, ['type', 'barcode_type']), 64),
  }));
}

async function normalizeVeryfi(document: any, submittedType: string, rawBytes: Uint8Array): Promise<any> {
  const fraud = fraudSignals(document);
  const duplicate = firstBool(document, ['is_duplicate', 'duplicate.is_duplicate', 'meta.is_duplicate', 'meta.duplicate']);
  const isDocument = firstBool(document, ['is_document', 'document.is_document']);
  const adverse = [
    fraud.digitalTampering,
    fraud.aiGenerated,
    fraud.screenshot,
    fraud.invalidQr,
    fraud.vendorLayoutMismatch,
    fraud.notADocument,
    duplicate,
  ].some((value) => value === true);
  const acceptedDecision = ['green', 'approved', 'pass', 'passed', 'low_risk', 'low risk'].includes(String(fraud.decision || '').toLowerCase());
  const documentVerified = isDocument === true && acceptedDecision && !adverse;
  const parsed = Boolean(first(document, ['id', 'vendor.name', 'merchant.name', 'total', 'date', 'invoice_number']));

  return {
    provider: 'Veryfi',
    providerDocumentId: boundedText(first(document, ['id', 'document_id']), 160),
    submittedType,
    providerDocumentType: boundedText(first(document, ['document_type', 'type']), 80),
    isDocument,
    verificationLevel: documentVerified ? 2 : parsed ? 1 : 0,
    verificationLabel: documentVerified ? 'Document Verified' : parsed ? 'Parsed' : 'Unverified',
    documentVerified,
    transactionCorroborated: false,
    merchantSigned: false,
    proofIssued: false,
    blockchainSubmitted: false,
    independentPurchaseConfirmed: false,
    merchant: {
      name: boundedText(first(document, ['vendor.name', 'merchant.name']), 512),
      address: boundedText(first(document, ['vendor.address', 'merchant.address']), 1024),
      phone: boundedText(first(document, ['vendor.phone_number', 'merchant.phone_number']), 128),
      storeNumber: boundedText(first(document, ['store_number', 'vendor.store_number']), 128),
    },
    date: boundedText(first(document, ['date', 'created_date', 'invoice_date']), 128),
    time: boundedText(first(document, ['time']), 64),
    currency: boundedText(first(document, ['currency_code', 'currency']), 16),
    subtotal: exactDecimal(document?.subtotal),
    tax: exactDecimal(document?.tax),
    discount: exactDecimal(document?.discount),
    total: exactDecimal(document?.total),
    invoiceNumber: boundedText(document?.invoice_number, 160),
    dueDate: boundedText(document?.due_date, 128),
    receiptNumber: boundedText(first(document, ['receipt_number', 'document_reference_number']), 160),
    duplicate,
    fraud,
    lineItems: normalizeLineItems(document),
    barcodes: normalizeBarcodes(document),
    rawResponseSha256: await sha256Hex(rawBytes),
    privacy: {
      storedByAura: false,
      providerAutoDeleteRequested: true,
    },
  };
}

async function readBoundedResponse(response: Response, maximum: number): Promise<Uint8Array> {
  const declared = Number(response.headers.get('content-length') || 0);
  if (Number.isFinite(declared) && declared > maximum) throw new Error('RESPONSE_TOO_LARGE');
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > maximum) throw new Error('RESPONSE_TOO_LARGE');
  return bytes;
}

function validatedGatewayBaseURL(value: string): URL {
  const base = new URL(value);
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) {
    throw new Error('GATEWAY_CONFIGURATION_INVALID');
  }
  base.pathname = base.pathname.replace(/\/+$/, '');
  return base;
}

function gatewayBaseURLs(env: AuraWorkerEnv): URL[] {
  const configured = env.AURA_MOBILE_GATEWAY_URLS?.trim()
    ? env.AURA_MOBILE_GATEWAY_URLS.split(/[\r\n,]+/)
    : [env.AURA_MOBILE_GATEWAY_URL || ''];
  const unique = new Map<string, URL>();
  for (const candidate of configured) {
    const value = candidate.trim();
    if (!value) continue;
    const base = validatedGatewayBaseURL(value);
    unique.set(base.toString(), base);
    if (unique.size >= MAX_GATEWAY_ORIGINS) break;
  }
  if (unique.size === 0) throw new Error('GATEWAY_CONFIGURATION_INVALID');
  return [...unique.values()];
}

function matchesExpectedAuraNetwork(value: any): boolean {
  return value?.protocolVersion === EXPECTED_AURA_NETWORK.protocolVersion
    && value?.network === EXPECTED_AURA_NETWORK.network
    && value?.chainId === EXPECTED_AURA_NETWORK.chainId
    && value?.chainIdHash === EXPECTED_AURA_NETWORK.chainIdHash
    && value?.genesisHash === EXPECTED_AURA_NETWORK.genesisHash
    && value?.mainnetAvailable === EXPECTED_AURA_NETWORK.mainnetAvailable;
}

async function gatewayHasExpectedIdentity(base: URL, token: string, requestId: string): Promise<boolean> {
  const networkURL = new URL('/v1/network', base);
  const response = await fetch(networkURL, {
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${token}`,
      'x-request-id': `${requestId}:identity`,
    },
  });
  if (!response.ok) return false;
  const bytes = await readBoundedResponse(response, 64 * 1024);
  try {
    return matchesExpectedAuraNetwork(JSON.parse(new TextDecoder().decode(bytes)));
  } catch {
    return false;
  }
}

async function proxyGateway(c: any, gatewayPath: string): Promise<Response> {
  if (!ALLOWED_GATEWAY_PATH.test(gatewayPath)) return c.json({ detail: 'Unsupported Aura gateway operation.' }, 404);
  const token = c.env.AURA_MOBILE_GATEWAY_TOKEN?.trim();
  if (!token || token.length < 32 || (!c.env.AURA_MOBILE_GATEWAY_URLS?.trim() && !c.env.AURA_MOBILE_GATEWAY_URL?.trim())) {
    return c.json({ detail: 'Aura Devnet gateway is not configured.', code: 'AURA_GATEWAY_UNAVAILABLE' }, 503);
  }
  let bases: URL[];
  try {
    bases = gatewayBaseURLs(c.env);
  } catch {
    return c.json({ detail: 'Aura Devnet gateway is not configured.', code: 'AURA_GATEWAY_UNAVAILABLE' }, 503);
  }
  const requestId = c.get('requestId') || crypto.randomUUID();
  const headers = new Headers({
    accept: 'application/json',
    authorization: `Bearer ${token}`,
    'x-request-id': requestId,
  });
  const idempotency = c.req.header('Idempotency-Key');
  const requestTimestamp = c.req.header('X-Aura-Request-Timestamp');
  if (idempotency) headers.set('Idempotency-Key', idempotency.slice(0, 160));
  if (requestTimestamp) headers.set('X-Aura-Request-Timestamp', requestTimestamp.slice(0, 32));
  let body: ArrayBuffer | undefined;
  if (c.req.method === 'POST') {
    const declared = Number(c.req.header('content-length') || 0);
    if (declared > 128 * 1024) return c.json({ detail: 'Aura transaction request is too large.' }, 413);
    const requestBody = await c.req.arrayBuffer();
    if (requestBody.byteLength > 128 * 1024) return c.json({ detail: 'Aura transaction request is too large.' }, 413);
    body = requestBody;
    headers.set('content-type', 'application/json');
  }
  for (const base of bases) {
    try {
      if (!await gatewayHasExpectedIdentity(base, token, requestId)) continue;
      const upstream = new URL(`/v1${gatewayPath}`, base);
      upstream.search = new URL(c.req.url).search;
      const response = await fetch(upstream, { method: c.req.method, headers, body });
      const bytes = await readBoundedResponse(response, MAX_GATEWAY_RESPONSE_BYTES);
      if (response.status >= 500) continue;
      return new Response(bytes, {
        status: response.status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        },
      });
    } catch {
      // Try the next independently configured origin. The phone still validates identity too.
    }
  }
  return c.json({ detail: 'Aura Devnet gateway is unavailable.', code: 'AURA_GATEWAY_UNAVAILABLE' }, 503);
}

export function createAuraRoutes(
  authMiddleware: AuthMiddleware,
  getUserId: (c: any) => string,
  enforceRateLimit: RateLimiter,
) {
  const aura = new Hono<any>();
  aura.use('*', authMiddleware);

  aura.post('/documents/verify', async (c) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'aura_document_verify', userId, 8, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'aura_document_verify_daily', userId, 50, 86400);
    if (dailyLimited) return dailyLimited;
    const submittedType = new URL(c.req.url).searchParams.get('type');
    if (submittedType !== 'receipt' && submittedType !== 'invoice') {
      return c.json({ detail: 'Choose receipt or invoice before verification.' }, 400);
    }
    if (!configuredVeryfi(c.env)) {
      return c.json({ detail: 'Document verification provider is unavailable.', code: 'VERYFI_NOT_CONFIGURED' }, 503);
    }
    const declared = Number(c.req.header('content-length') || 0);
    if (Number.isFinite(declared) && declared > MAX_DOCUMENT_BYTES + 128 * 1024) {
      return c.json({ detail: 'Document must be 12 MiB or smaller.' }, 413);
    }
    try {
      const form = await c.req.raw.formData();
      const file = form.get('file') as File | null;
      if (!file || typeof file.arrayBuffer !== 'function') return c.json({ detail: 'No document was provided.' }, 400);
      const ownerPublicKeyHex = String(form.get('ownerPublicKeyHex') || '').trim();
      if (submittedType === 'receipt' && !/^[a-fA-F0-9]{64}$/.test(ownerPublicKeyHex)) {
        return c.json({ detail: 'Unlock a local Aura wallet before verifying a receipt.', code: 'AURA_WALLET_REQUIRED' }, 409);
      }
      if (submittedType === 'receipt' && !configuredPurchaseProof(c.env)) {
        return c.json({ detail: 'Aura purchase-proof authorization is unavailable.', code: 'AURA_PROOF_UNAVAILABLE' }, 503);
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (bytes.byteLength < 250 || bytes.byteLength > MAX_DOCUMENT_BYTES) {
        return c.json({ detail: 'Document must be between 250 bytes and 12 MiB.' }, 400);
      }
      const mediaType = detectedDocumentType(bytes);
      if (!mediaType) return c.json({ detail: 'Choose a valid JPG, PNG, HEIC/HEIF, or PDF document.' }, 400);
      const fileName = safeFilename(file.name, mediaType);
      const request = {
        file_name: fileName,
        file_data: bytesToBase64(bytes),
        document_type: submittedType,
        boost_mode: false,
        async: false,
        auto_delete: true,
        confidence_details: false,
        allowed_async_enrichments: [],
      };
      const headers = new Headers({
        accept: 'application/json',
        'content-type': 'application/json',
        'client-id': c.env.VERYFI_CLIENT_ID!.trim(),
        authorization: c.env.VERYFI_API_KEY!.trim().startsWith('vrfk_')
          ? `Bearer ${c.env.VERYFI_API_KEY!.trim()}`
          : `apikey ${c.env.VERYFI_USERNAME?.trim() || ''}:${c.env.VERYFI_API_KEY!.trim()}`,
        'user-agent': 'Aura-Mobile-Gateway/1.0.1',
      });
      if (!c.env.VERYFI_API_KEY!.trim().startsWith('vrfk_') && !c.env.VERYFI_USERNAME?.trim()) {
        return c.json({ detail: 'Document verification provider is unavailable.', code: 'VERYFI_NOT_CONFIGURED' }, 503);
      }
      if (c.env.VERYFI_CLIENT_SECRET?.trim()) {
        const timestamp = Date.now();
        headers.set('x-veryfi-request-timestamp', String(timestamp));
        headers.set('x-veryfi-request-signature', await veryfiSignature(c.env.VERYFI_CLIENT_SECRET.trim(), request, timestamp));
      }
      const response = await fetch(veryfiEndpoint(c.env), {
        method: 'POST',
        headers,
        body: JSON.stringify(request),
      });
      const responseBytes = await readBoundedResponse(response, MAX_PROVIDER_RESPONSE_BYTES);
      if (response.status !== 201) {
        if (response.status === 401 || response.status === 403) return c.json({ detail: 'Document provider authentication failed.', code: 'VERYFI_AUTH_FAILED' }, 502);
        if (response.status === 429) return c.json({ detail: 'Document provider rate limit reached. Try again later.', code: 'VERYFI_RATE_LIMITED' }, 429);
        return c.json({ detail: 'Document provider could not process this file.', code: 'VERYFI_REJECTED' }, 502);
      }
      const document = JSON.parse(new TextDecoder().decode(responseBytes));
      const normalized = await normalizeVeryfi(document, submittedType, responseBytes);
      if (submittedType === 'receipt' && normalized.documentVerified && normalized.duplicate !== true) {
        normalized.purchaseProof = await purchaseProofAttestation(
          c.env,
          userId,
          ownerPublicKeyHex,
          document,
          normalized,
        );
        normalized.proofAuthorized = true;
      } else {
        normalized.purchaseProof = null;
        normalized.proofAuthorized = false;
      }
      return c.json(normalized);
    } catch (error: any) {
      const code = String(error?.message || 'VERYFI_UNAVAILABLE');
      if (code === 'RESPONSE_TOO_LARGE') return c.json({ detail: 'Document provider response exceeded the safe limit.' }, 502);
      return c.json({ detail: 'Document provider is temporarily unavailable.', code: 'VERYFI_UNAVAILABLE' }, 503);
    }
  });

  const proxy = async (c: any) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'aura_gateway', userId, 180, 60);
    if (limited) return limited;
    const url = new URL(c.req.url);
    const prefix = '/api/aura';
    return proxyGateway(c, url.pathname.startsWith(prefix) ? url.pathname.slice(prefix.length) : url.pathname);
  };
  aura.get('/network', proxy);
  aura.get('/chain/status', proxy);
  aura.get('/address/:address/balance', proxy);
  aura.get('/address/:address/nonce', proxy);
  aura.get('/address/:address/transactions', proxy);
  aura.get('/fees', proxy);
  aura.post('/transactions/broadcast', proxy);
  aura.post('/proofs/broadcast', proxy);
  aura.get('/transaction/:transactionId', proxy);
  aura.get('/proof/:proofId', proxy);
  aura.get('/proof/:proofId/feedback-eligibility', proxy);
  aura.post('/proof/:proofId/feedback', proxy);
  return aura;
}
