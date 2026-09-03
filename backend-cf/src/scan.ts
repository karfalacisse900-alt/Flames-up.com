import { Hono } from 'hono';

export interface CaptroScanEnv {
  KV?: KVNamespace;
  MEDIA_BACKUP?: R2Bucket;
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  VERYFI_CLIENT_ID?: string;
  VERYFI_CLIENT_SECRET?: string;
  VERYFI_USERNAME?: string;
  VERYFI_API_KEY?: string;
  VERYFI_BASE_URL?: string;
  RECEIPT_REWARD_CENTS?: string;
  INVOICE_REWARD_CENTS?: string;
  APP_STORE_CONNECT_API_ISSUER_ID?: string;
  APP_STORE_CONNECT_API_KEY_ID?: string;
  APP_STORE_CONNECT_API_KEY_BASE64?: string;
  APP_STORE_BUNDLE_ID?: string;
}

type AuthMiddleware = (c: any, next: () => Promise<void>) => Promise<Response | void>;
type RateLimiter = (
  c: any,
  scope: string,
  userId: string,
  limit: number,
  seconds: number,
) => Promise<Response | null>;

type VerificationCheck = {
  key: string;
  status: 'passed' | 'failed' | 'unavailable';
  detail: string;
};

const MAX_DOCUMENT_BYTES = 12 * 1024 * 1024;
const MAX_PROVIDER_RESPONSE_BYTES = 8 * 1024 * 1024;
const VERIFY_PRICE_CENTS = 10;
const PRIVATE_RECEIPT_BUCKET = 'captro-private-receipts';
const VERYFI_DOCUMENTS_PATH = '/api/v8/partner/documents';
const DEFAULT_BUNDLE_ID = 'com.captro.app';
const CREDIT_PRODUCTS: Record<string, { creditCents: number; paidCents: number }> = {
  'com.captro.scan.credits.10': { creditCents: 100, paidCents: 99 },
};

function cleanText(value: unknown, maximum = 1024): string {
  if (value === null || value === undefined) return '';
  return String(value).trim().slice(0, maximum);
}

function configuredRewardCents(env: CaptroScanEnv, documentType: 'receipt' | 'invoice' | 'unsupported'): number {
  const raw = documentType === 'invoice' ? env.INVOICE_REWARD_CENTS : env.RECEIPT_REWARD_CENTS;
  if (raw === undefined || cleanText(raw, 20) === '') return 10;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0 || value > 5000) {
    throw new Error('SCAN_REWARD_CONFIGURATION_INVALID');
  }
  return value;
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

function firstText(source: any, paths: string[], maximum = 1024): string {
  const value = first(source, paths);
  return value && typeof value !== 'object' ? cleanText(value, maximum) : '';
}

function firstBool(source: any, paths: string[]): boolean | null {
  const value = first(source, paths);
  if (typeof value === 'boolean') return value;
  if (value === 1 || value === '1' || String(value).toLowerCase() === 'true') return true;
  if (value === 0 || value === '0' || String(value).toLowerCase() === 'false') return false;
  return null;
}

function decimalText(value: unknown): string {
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  const text = cleanText(value, 80).replace(/[$, ]/g, '');
  return /^-?\d+(?:\.\d+)?$/.test(text) ? text : '';
}

function decimalNumber(value: unknown): number | null {
  const text = decimalText(value);
  if (!text) return null;
  const number = Number(text);
  return Number.isFinite(number) ? number : null;
}

function roundedCurrency(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function normalizedDatabaseDate(value: unknown): string | null {
  const text = cleanText(value, 80);
  if (!text) return null;
  const iso = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  const us = text.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  const candidate = iso
    ? `${iso[1]}-${iso[2]}-${iso[3]}`
    : us ? `${us[3]}-${us[1].padStart(2, '0')}-${us[2].padStart(2, '0')}` : '';
  if (!candidate) return null;
  const parsed = new Date(`${candidate}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== candidate ? null : candidate;
}

function normalizedDatabaseTime(value: unknown): string | null {
  const text = cleanText(value, 40).toLowerCase();
  const match = text.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$/);
  if (!match) return null;
  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] || '0');
  if (minute > 59 || second > 59) return null;
  if (match[4]) {
    if (hour < 1 || hour > 12) return null;
    if (match[4] === 'am') hour = hour === 12 ? 0 : hour;
    if (match[4] === 'pm') hour = hour === 12 ? 12 : hour + 12;
  } else if (hour > 23) {
    return null;
  }
  return `${String(hour).padStart(2, '0')}:${match[2]}:${String(second).padStart(2, '0')}`;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replace(/\s+/g, '');
  const binary = atob(normalized);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function decodeBase64UrlJson(value: string): any {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  return JSON.parse(new TextDecoder().decode(base64ToBytes(padded)));
}

async function sha256Hex(value: ArrayBuffer | Uint8Array | string): Promise<string> {
  const input = typeof value === 'string'
    ? new TextEncoder().encode(value)
    : value instanceof Uint8Array ? value : new Uint8Array(value);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', input));
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function detectedContentType(bytes: Uint8Array): string {
  if (bytes.length >= 5 && new TextDecoder().decode(bytes.subarray(0, 5)) === '%PDF-') return 'application/pdf';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return 'image/png';
  if (bytes.length >= 12 && new TextDecoder().decode(bytes.subarray(4, 8)) === 'ftyp') {
    const brand = new TextDecoder().decode(bytes.subarray(8, 12));
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(brand)) return 'image/heic';
  }
  return '';
}

function fileExtension(contentType: string): string {
  if (contentType === 'application/pdf') return 'pdf';
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/heic') return 'heic';
  return 'jpg';
}

function safeFilename(value: unknown, contentType: string): string {
  const base = cleanText(value, 120).replace(/[^a-zA-Z0-9._ -]/g, '_').replace(/\.{2,}/g, '.');
  const fallback = `Captro Document.${fileExtension(contentType)}`;
  return base && !base.startsWith('.') ? base : fallback;
}

function supabaseConfiguration(env: CaptroScanEnv): { url: string; key: string } {
  const url = cleanText(env.SUPABASE_URL, 400).replace(/\/+$/, '');
  const key = cleanText(env.SUPABASE_SERVICE_ROLE_KEY, 4096);
  if (!url || !key) throw new Error('SCAN_DATABASE_UNAVAILABLE');
  return { url, key };
}

function supabaseHeaders(env: CaptroScanEnv, prefer = ''): HeadersInit {
  const { key } = supabaseConfiguration(env);
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    ...(prefer ? { Prefer: prefer } : {}),
  };
}

async function supabaseRpc(env: CaptroScanEnv, functionName: string, body: Record<string, unknown>): Promise<any> {
  const { url } = supabaseConfiguration(env);
  const response = await fetch(`${url}/rest/v1/rpc/${functionName}`, {
    method: 'POST',
    headers: supabaseHeaders(env),
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`SCAN_RPC_FAILED:${functionName}:${response.status}:${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : {};
}

async function selectRows(
  env: CaptroScanEnv,
  table: string,
  filters: Record<string, string>,
  options: { select?: string; order?: string; limit?: number } = {},
): Promise<any[]> {
  const { url } = supabaseConfiguration(env);
  const endpoint = new URL(`${url}/rest/v1/${table}`);
  endpoint.searchParams.set('select', options.select || '*');
  for (const [key, value] of Object.entries(filters)) endpoint.searchParams.set(key, value);
  if (options.order) endpoint.searchParams.set('order', options.order);
  if (options.limit) endpoint.searchParams.set('limit', String(options.limit));
  const response = await fetch(endpoint.toString(), { headers: supabaseHeaders(env) });
  const text = await response.text();
  if (!response.ok) throw new Error(`SCAN_SELECT_FAILED:${table}:${response.status}:${text.slice(0, 500)}`);
  const data = text ? JSON.parse(text) : [];
  return Array.isArray(data) ? data : [];
}

async function patchVerification(env: CaptroScanEnv, id: string, userId: string, patch: Record<string, unknown>): Promise<void> {
  const { url } = supabaseConfiguration(env);
  const endpoint = new URL(`${url}/rest/v1/scan_verifications`);
  endpoint.searchParams.set('id', `eq.${id}`);
  endpoint.searchParams.set('user_id', `eq.${userId}`);
  const response = await fetch(endpoint.toString(), {
    method: 'PATCH',
    headers: supabaseHeaders(env, 'return=minimal'),
    body: JSON.stringify(patch),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SCAN_UPDATE_FAILED:${response.status}:${text.slice(0, 500)}`);
  }
}

async function insertProof(env: CaptroScanEnv, row: Record<string, unknown>): Promise<any> {
  const { url } = supabaseConfiguration(env);
  const endpoint = new URL(`${url}/rest/v1/scan_proofs`);
  endpoint.searchParams.set('select', '*');
  const response = await fetch(endpoint.toString(), {
    method: 'POST',
    headers: supabaseHeaders(env, 'return=representation'),
    body: JSON.stringify(row),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`SCAN_PROOF_INSERT_FAILED:${response.status}:${text.slice(0, 500)}`);
  return (JSON.parse(text) as any[])[0];
}

function veryfiEndpoint(env: CaptroScanEnv): string {
  const base = cleanText(env.VERYFI_BASE_URL, 400).replace(/\/+$/, '') || 'https://api.veryfi.com';
  const url = new URL(base);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
    throw new Error('SCAN_PROVIDER_CONFIGURATION_INVALID');
  }
  return `${url.toString().replace(/\/+$/, '')}${VERYFI_DOCUMENTS_PATH}`;
}

function providerConfigured(env: CaptroScanEnv): boolean {
  const apiKey = cleanText(env.VERYFI_API_KEY, 4096);
  return Boolean(cleanText(env.VERYFI_CLIENT_ID, 300) && apiKey && (apiKey.startsWith('vrfk_') || cleanText(env.VERYFI_USERNAME, 300)));
}

function veryfiSerializeValue(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(veryfiSerializeValue).join(', ')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .map(([key, nestedValue]) => `${key}: ${veryfiSerializeValue(nestedValue)}`)
      .join(', ')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

function veryfiSignaturePayload(request: Record<string, unknown>, timestamp: number): string {
  const serialized = Object.entries(request)
    .map(([key, value]) => `${key}:${veryfiSerializeValue(value)}`)
    .join(',');
  return `timestamp:${timestamp}${serialized ? `,${serialized}` : ''}`;
}

async function veryfiSignature(secret: string, request: Record<string, unknown>, timestamp: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(veryfiSignaturePayload(request, timestamp)),
  ));
  let binary = '';
  for (const byte of signature) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function readBoundedResponse(response: Response): Promise<Uint8Array> {
  const declared = Number(response.headers.get('content-length') || 0);
  if (Number.isFinite(declared) && declared > MAX_PROVIDER_RESPONSE_BYTES) throw new Error('SCAN_PROVIDER_RESPONSE_TOO_LARGE');
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_PROVIDER_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error('SCAN_PROVIDER_RESPONSE_TOO_LARGE');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

function providerDocumentType(document: any): 'receipt' | 'invoice' | 'unsupported' {
  const value = firstText(document, [
    'document_type.value', 'document_type', 'type.value', 'type', 'document_category', 'category',
  ], 80).toLowerCase().replace(/[ -]+/g, '_');
  if (value === 'receipt' || value === 'long_receipt') return 'receipt';
  if (value === 'invoice') return 'invoice';
  return 'unsupported';
}

function normalizedAddress(document: any) {
  const addressValue = first(document, ['vendor.address', 'merchant.address', 'bill_from.address']);
  const parsedAddress = first(document, [
    'vendor.parsed_address', 'merchant.parsed_address', 'bill_from.parsed_address',
  ]);
  const original = typeof addressValue === 'string'
    ? cleanText(addressValue, 1200)
    : firstText(document, ['vendor.address_text', 'merchant.address_text', 'bill_from.address_text'], 1200);
  const source = parsedAddress && typeof parsedAddress === 'object'
    ? parsedAddress
    : addressValue && typeof addressValue === 'object' ? addressValue : {};
  return {
    original,
    street: firstText(source, ['street', 'address_line', 'line1', 'street_address'], 300)
      || firstText(document, ['vendor.street', 'merchant.street', 'bill_from.street'], 300),
    city: firstText(source, ['city'], 160) || firstText(document, ['vendor.city', 'merchant.city', 'bill_from.city'], 160),
    state: firstText(source, ['state', 'region'], 120) || firstText(document, ['vendor.state', 'merchant.state', 'bill_from.state'], 120),
    postalCode: firstText(source, ['postal_code', 'postcode', 'zip', 'zip_code'], 40)
      || firstText(document, ['vendor.zip_code', 'vendor.postal_code', 'merchant.zip_code', 'bill_from.zip_code'], 40),
    country: firstText(source, ['country', 'country_code'], 80)
      || firstText(document, ['vendor.country', 'merchant.country', 'bill_from.country'], 80),
  };
}

function normalizedLineItems(document: any): any[] {
  const values = Array.isArray(document?.line_items) ? document.line_items : [];
  return values.slice(0, 256).map((line: any) => ({
    description: firstText(line, ['description', 'text', 'full_description'], 500) || null,
    sku: firstText(line, ['sku', 'upc', 'product_code'], 120) || null,
    quantity: decimalText(line?.quantity) || null,
    unitPrice: decimalText(first(line, ['price', 'unit_price'])) || null,
    discount: decimalText(first(line, ['discount', 'discount_amount'])) || null,
    total: decimalText(first(line, ['total', 'subtotal', 'line_total'])) || null,
  }));
}

function normalizedBarcodes(document: any): any[] {
  const values = Array.isArray(document?.barcodes) ? document.barcodes : [];
  return values.slice(0, 32).map((barcode: any) => ({
    data: firstText(barcode, ['data', 'value', 'text'], 1000) || null,
    type: firstText(barcode, ['type', 'barcode_type', 'format'], 80) || null,
  })).filter((barcode: any) => barcode.data);
}

function paymentDetails(document: any) {
  const method = firstText(document, ['payment.type', 'payment_method', 'payment.payment_type', 'card.type'], 80);
  const rawCard = firstText(document, ['payment.card_number', 'card.number', 'payment.last_four', 'card.last_four'], 80);
  const digits = rawCard.replace(/\D/g, '');
  return {
    method: method || null,
    lastFour: digits.length >= 4 ? digits.slice(-4) : null,
  };
}

function providerSignals(document: any) {
  const fraud = first(document, ['meta.fraud', 'fraud', 'fraud_info']) || {};
  const details = fraud?.details && typeof fraud.details === 'object' ? fraud.details : {};
  const types = Array.isArray(fraud?.types) ? fraud.types.map((value: unknown) => String(value).toLowerCase()) : null;
  const signal = (label: string, paths: string[]): boolean | null => {
    const explicit = firstBool(document, paths);
    const key = label.replace(/ /g, '_');
    if (explicit === true || details[key] === true || (details[key] && typeof details[key] === 'object')
      || types?.includes(label) || types?.includes(key)) return true;
    if (explicit === false || types !== null) return false;
    return null;
  };
  return {
    decision: firstText(document, ['meta.fraud.decision', 'fraud.decision', 'fraud_info.decision'], 60).toLowerCase(),
    digitalTampering: signal('digital tampering', ['fraud.digital_tampering', 'fraud.digitalTampering']),
    aiGenerated: signal('ai generated', ['fraud.ai_generated', 'fraud.aiGenerated']),
    screenshot: signal('screenshot', ['fraud.screenshot', 'fraud.is_screenshot']),
    invalidQr: signal('invalid qr data', ['fraud.invalid_qr_data', 'fraud.invalidQrData']),
    vendorLayoutMismatch: signal('vendor layout mismatch', ['fraud.vendor_layout_mismatch', 'fraud.vendorLayoutMismatch']),
    notADocument: signal('not a document', ['fraud.not_a_document', 'fraud.notADocument']),
    duplicate: firstBool(document, ['is_duplicate']),
    duplicateOf: firstText(document, ['duplicate_of'], 160) || null,
  };
}

function unwrapProviderFields(value: any): any {
  if (Array.isArray(value)) return value.map(unwrapProviderFields);
  if (!value || typeof value !== 'object') return value;
  if (Object.hasOwn(value, 'value') && (Object.keys(value).length === 1
    || ['score', 'ocr_score', 'bounding_box', 'bounding_region', 'enriched'].some(key => Object.hasOwn(value, key)))) {
    return unwrapProviderFields(value.value);
  }
  return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, unwrapProviderFields(nested)]));
}

function normalizeProviderDocument(providerDocument: any) {
  const document = unwrapProviderFields(providerDocument);
  const type = providerDocumentType(document);
  const address = normalizedAddress(document);
  const items = normalizedLineItems(document);
  const barcodes = normalizedBarcodes(document);
  const payment = paymentDetails(document);
  const signals = providerSignals(document);
  const fees = [
    first(document, ['fees', 'fee']),
    first(document, ['shipping', 'shipping_cost']),
    first(document, ['tip', 'gratuity']),
    first(document, ['service_charge']),
  ].map(decimalNumber).filter((value): value is number => value !== null);
  const feeTotal = fees.length ? roundedCurrency(fees.reduce((sum, value) => sum + value, 0)) : null;
  const businessName = firstText(document, ['vendor.name', 'merchant.name', 'bill_from.name'], 400);
  const documentNumber = type === 'invoice'
    ? firstText(document, ['invoice_number', 'document_reference_number'], 160)
    : firstText(document, ['receipt_number', 'document_reference_number'], 160);
  const transactionReference = firstText(document, ['transaction_number', 'transaction_id', 'reference_number', 'order_number'], 160);
  return {
    type,
    providerRequestId: firstText(document, ['id', 'document_id'], 160),
    isDocument: firstBool(document, ['is_document', 'document.is_document']),
    business: {
      name: businessName || null,
      address,
      phone: firstText(document, ['vendor.phone_number', 'merchant.phone_number', 'bill_from.phone_number'], 80) || null,
      storeNumber: firstText(document, ['store_number', 'vendor.store_number', 'merchant.store_number'], 100) || null,
    },
    customer: {
      name: firstText(document, ['bill_to.name', 'customer.name'], 300) || null,
      address: firstText(document, ['bill_to.address', 'customer.address'], 1000) || null,
    },
    documentNumber: documentNumber || null,
    transactionReference: transactionReference || null,
    registerNumber: firstText(document, ['register_number', 'register'], 100) || null,
    cashier: firstText(document, ['cashier_name', 'cashier'], 200) || null,
    orderNumber: firstText(document, ['purchase_order_number', 'order_number', 'po_number'], 160) || null,
    issueDate: firstText(document, ['date', 'created_date', 'invoice_date'], 80) || null,
    dueDate: firstText(document, ['due_date'], 80) || null,
    time: firstText(document, ['time'], 40)
      || firstText(document, ['date'], 80).match(/[T ](\d{2}:\d{2}(?::\d{2})?)/)?.[1] || null,
    items,
    subtotal: decimalText(document?.subtotal) || null,
    tax: decimalText(document?.tax) || null,
    discount: decimalText(document?.discount) || null,
    fees: feeTotal === null ? null : String(feeTotal),
    total: decimalText(document?.total) || null,
    currency: firstText(document, ['currency_code', 'currency'], 12).toUpperCase() || null,
    payment,
    paymentTerms: firstText(document, ['payment_terms', 'terms'], 500) || null,
    barcodes,
    signals,
  };
}

type PurchaseCategory = 'restaurant_food' | 'product_retail' | 'grocery' | 'service_business' | 'general';

const CATEGORY_QUESTION_KEYS: Record<PurchaseCategory, string[]> = {
  restaurant_food: ['quality', 'cleanliness', 'speed', 'service', 'value', 'overall'],
  product_retail: ['quality', 'expectations', 'value', 'speed', 'organization', 'overall'],
  grocery: ['freshness', 'cleanliness', 'stock', 'speed', 'value', 'overall'],
  service_business: ['professionalism', 'speed', 'result', 'value', 'overall'],
  general: ['quality', 'value', 'service', 'overall'],
};

function purchaseCategory(document: any, extracted: any): PurchaseCategory {
  const source = [
    firstText(document, ['category', 'document_category', 'vendor.category', 'merchant.category', 'expense_category'], 300),
    cleanText(extracted.business?.name, 300),
    ...extracted.items.slice(0, 24).map((item: any) => cleanText(item.description, 180)),
  ].join(' ').toLowerCase();
  const contains = (values: string[]) => values.some((value) => source.includes(value));

  if (contains(['grocery', 'supermarket', 'produce', 'food market', 'whole foods'])) return 'grocery';
  if (contains(['restaurant', 'cafe', 'coffee', 'bakery', 'bar ', 'dining', 'food', 'pizza', 'grill', 'kitchen'])) {
    return 'restaurant_food';
  }
  if (contains(['salon', 'spa', 'repair', 'service', 'consult', 'cleaning', 'plumbing', 'electrician', 'appointment'])) {
    return 'service_business';
  }
  if (contains(['retail', 'clothing', 'apparel', 'electronics', 'pharmacy', 'department store', 'hardware', 'shop'])) {
    return 'product_retail';
  }
  if (extracted.type === 'invoice') return 'service_business';
  return 'general';
}

function receiptAcceptedForFeedback(extracted: any): boolean {
  const checks = buildChecks(extracted);
  const status = (key: string) => checks.find((check) => check.key === key)?.status;
  const arithmeticPassed = status('total_arithmetic') === 'passed' || status('line_item_arithmetic') === 'passed';
  return ['receipt', 'invoice'].includes(extracted.type)
    && status('document_structure') === 'passed'
    && status('provider_document_signal') === 'passed'
    && status('date_validity') === 'passed'
    && arithmeticPassed
    && status('total_arithmetic') !== 'failed'
    && status('line_item_arithmetic') !== 'failed';
}

async function receiptRewardFingerprint(extracted: any): Promise<string | null> {
  const merchant = cleanText(extracted.business?.name, 400).toLowerCase();
  const date = normalizedDatabaseDate(extracted.issueDate);
  const time = normalizedDatabaseTime(extracted.time);
  const total = decimalText(extracted.total);
  const documentNumber = cleanText(extracted.documentNumber, 160).toLowerCase();
  const transactionReference = cleanText(extracted.transactionReference, 160).toLowerCase();
  const address = cleanText(
    extracted.business?.address?.original
      || [extracted.business?.address?.street, extracted.business?.address?.city, extracted.business?.address?.postalCode]
        .filter(Boolean).join(' '),
    1200,
  ).toLowerCase();
  if (!merchant || !date || !total || !(documentNumber || transactionReference || time || address)) return null;
  return sha256Hex(JSON.stringify({
    type: extracted.type,
    merchant,
    address,
    documentNumber,
    transactionReference,
    date,
    time,
    total,
    currency: cleanText(extracted.currency, 12).toUpperCase(),
  }));
}

function arithmeticCheck(extracted: any): VerificationCheck {
  const subtotal = decimalNumber(extracted.subtotal);
  const tax = decimalNumber(extracted.tax);
  const discount = decimalNumber(extracted.discount) ?? 0;
  const fees = decimalNumber(extracted.fees) ?? 0;
  const total = decimalNumber(extracted.total);
  if (subtotal === null || total === null || (tax === null && fees === 0 && discount === 0)) {
    return { key: 'total_arithmetic', status: 'unavailable', detail: 'The document did not contain enough totals to perform this check.' };
  }
  const expected = roundedCurrency(subtotal + (tax ?? 0) + fees - discount);
  const passed = Math.abs(expected - total) <= 0.02;
  return {
    key: 'total_arithmetic',
    status: passed ? 'passed' : 'failed',
    detail: passed ? 'Subtotal, adjustments, tax, and total are consistent.' : 'The printed totals are not arithmetically consistent.',
  };
}

function lineItemCheck(extracted: any): VerificationCheck {
  const totals = extracted.items.map((item: any) => decimalNumber(item.total)).filter((value: number | null): value is number => value !== null);
  const subtotal = decimalNumber(extracted.subtotal);
  if (!totals.length || subtotal === null || totals.length !== extracted.items.length) {
    return { key: 'line_item_arithmetic', status: 'unavailable', detail: 'Not every line item had a usable amount.' };
  }
  const sum = roundedCurrency(totals.reduce((total: number, value: number) => total + value, 0));
  const passed = Math.abs(sum - subtotal) <= 0.02;
  return {
    key: 'line_item_arithmetic',
    status: passed ? 'passed' : 'failed',
    detail: passed ? 'Line-item totals match the subtotal.' : 'Line-item totals do not match the subtotal.',
  };
}

function dateCheck(extracted: any): VerificationCheck {
  const raw = cleanText(extracted.issueDate, 80);
  if (!raw) return { key: 'date_validity', status: 'unavailable', detail: 'No purchase or issue date was available.' };
  const timestamp = Date.parse(raw);
  if (!Number.isFinite(timestamp)) return { key: 'date_validity', status: 'failed', detail: 'The printed date could not be interpreted.' };
  const passed = timestamp <= Date.now() + 24 * 60 * 60 * 1000 && timestamp >= Date.UTC(1990, 0, 1);
  return {
    key: 'date_validity',
    status: passed ? 'passed' : 'failed',
    detail: passed ? 'The document date is within a valid range.' : 'The document date is outside a valid range.',
  };
}

function providerAuthenticityCheck(extracted: any): VerificationCheck {
  const signals = extracted.signals;
  const values = [
    signals.digitalTampering,
    signals.aiGenerated,
    signals.invalidQr,
    signals.vendorLayoutMismatch,
    signals.notADocument,
  ];
  const blocking = values.some((value) => value === true);
  const explicitClear = values.every((value) => value === false);
  const acceptedDecision = ['green', 'accept', 'accepted', 'pass', 'passed', 'verified'].includes(signals.decision);
  const rejectedDecision = ['red', 'declined', 'deny', 'denied', 'fail', 'failed', 'rejected'].includes(signals.decision);
  if (blocking || rejectedDecision) {
    return { key: 'provider_document_signal', status: 'failed', detail: 'The external document check did not accept the submitted file.' };
  }
  if (acceptedDecision || explicitClear) {
    return { key: 'provider_document_signal', status: 'passed', detail: 'The external document check found no blocking inconsistency.' };
  }
  return { key: 'provider_document_signal', status: 'unavailable', detail: 'The provider did not return an authenticity signal.' };
}

function buildChecks(extracted: any, duplicateStatus: VerificationCheck['status'] = 'unavailable'): VerificationCheck[] {
  const structurePassed = extracted.isDocument !== false
    && ['receipt', 'invoice'].includes(extracted.type)
    && Boolean(extracted.business.name && extracted.total && extracted.issueDate);
  const address = extracted.business.address;
  const addressPerformed = Boolean(address.original || address.street || address.city || address.postalCode);
  return [
    { key: 'document_processed', status: extracted.providerRequestId ? 'passed' : 'unavailable', detail: 'Provider document processing result.' },
    { key: 'merchant_extracted', status: extracted.business.name ? 'passed' : 'unavailable', detail: 'Merchant or vendor data extracted.' },
    { key: 'amount_extracted', status: decimalNumber(extracted.total) !== null ? 'passed' : 'unavailable', detail: 'Total amount extracted.' },
    {
      key: 'document_structure',
      status: structurePassed ? 'passed' : 'failed',
      detail: structurePassed ? 'Document structure and core fields are consistent.' : 'Core document structure or fields are missing.',
    },
    providerAuthenticityCheck(extracted),
    dateCheck(extracted),
    arithmeticCheck(extracted),
    lineItemCheck(extracted),
    {
      key: 'business_address',
      status: addressPerformed ? 'passed' : 'unavailable',
      detail: addressPerformed ? 'A merchant or vendor address was extracted.' : 'No merchant or vendor address was available.',
    },
    {
      key: 'document_identifier',
      status: extracted.documentNumber || extracted.transactionReference ? 'passed' : 'unavailable',
      detail: extracted.documentNumber || extracted.transactionReference ? 'A document or transaction identifier was extracted.' : 'No document identifier was available.',
    },
    {
      key: 'barcode_or_qr',
      status: extracted.barcodes.length ? 'passed' : 'unavailable',
      detail: extracted.barcodes.length ? 'Barcode or QR information was read.' : 'No barcode or QR information was available.',
    },
    { key: 'duplicate_check', status: duplicateStatus, detail: duplicateStatus === 'passed'
      ? 'No matching prior submission was found.' : duplicateStatus === 'failed'
        ? 'This document has already been submitted.' : 'A duplicate check has not completed.' },
  ];
}

function verdictFromChecks(checks: VerificationCheck[]): 'verified' | 'couldnt_verify' {
  const status = (key: string) => checks.find((check) => check.key === key)?.status;
  const arithmeticPassed = status('total_arithmetic') === 'passed' || status('line_item_arithmetic') === 'passed';
  const criticalFailed = checks.some((check) => ['document_structure', 'provider_document_signal', 'date_validity', 'total_arithmetic', 'line_item_arithmetic']
    .includes(check.key) && check.status === 'failed');
  return status('document_structure') === 'passed'
    && status('document_processed') === 'passed'
    && status('duplicate_check') === 'passed'
    && status('provider_document_signal') === 'passed'
    && status('date_validity') === 'passed'
    && arithmeticPassed
    && !criticalFailed
    ? 'verified'
    : 'couldnt_verify';
}

async function providerVerify(
  env: CaptroScanEnv,
  bytes: Uint8Array,
  fileName: string,
  externalId: string,
): Promise<any> {
  const mimeType = detectedContentType(bytes);
  console.info(JSON.stringify({ event: 'veryfi_request_started', scanId: externalId,
    documentType: 'auto_receipt_or_invoice', mimeType, fileBytes: bytes.length,
    credentials: { clientId: Boolean(env.VERYFI_CLIENT_ID?.trim()), apiKey: Boolean(env.VERYFI_API_KEY?.trim()),
      username: Boolean(env.VERYFI_USERNAME?.trim()), signingSecret: Boolean(env.VERYFI_CLIENT_SECRET?.trim()) } }));
  if (!providerConfigured(env)) throw new Error('SCAN_PROVIDER_UNAVAILABLE');
  if (!mimeType || bytes.length < 250 || bytes.length > MAX_DOCUMENT_BYTES) throw new Error('SCAN_DOCUMENT_TYPE_INVALID');
  const request = {
    file_name: `${safeFilename(fileName, mimeType).replace(/\.[^.]+$/, '')}.${fileExtension(mimeType)}`,
    file_data: bytesToBase64(bytes),
    external_id: externalId,
    document_type: null,
    boost_mode: false,
    async: false,
    auto_delete: true,
    confidence_details: true,
    parse_address: true,
    allowed_async_enrichments: [],
  };
  const apiKey = cleanText(env.VERYFI_API_KEY, 4096);
  const headers = new Headers({
    accept: 'application/json',
    'content-type': 'application/json',
    'client-id': cleanText(env.VERYFI_CLIENT_ID, 300),
    authorization: apiKey.startsWith('vrfk_') ? `Bearer ${apiKey}` : `apikey ${cleanText(env.VERYFI_USERNAME, 300)}:${apiKey}`,
    'user-agent': 'Captro-Scan/1.0.1',
  });
  const secret = cleanText(env.VERYFI_CLIENT_SECRET, 4096);
  if (secret) {
    const timestamp = Math.floor(Date.now() / 1000) * 1000;
    headers.set('x-veryfi-request-timestamp', String(timestamp));
    headers.set('x-veryfi-request-signature', await veryfiSignature(secret, request, timestamp));
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60_000);
  const started = Date.now();
  try {
    const response = await fetch(veryfiEndpoint(env), {
      method: 'POST', headers, body: JSON.stringify(request), signal: controller.signal, redirect: 'error',
    });
    console.info(JSON.stringify({ event: 'veryfi_response', scanId: externalId, httpStatus: response.status, elapsedMs: Date.now() - started }));
    const responseBytes = await readBoundedResponse(response);
    let document: any;
    try { document = JSON.parse(new TextDecoder().decode(responseBytes)); } catch {
      if (response.ok) throw new Error('SCAN_PROVIDER_MALFORMED_RESPONSE');
    }
    if (!response.ok) {
      console.warn(JSON.stringify({ event: 'veryfi_provider_error', scanId: externalId, httpStatus: response.status,
        providerError: safeProviderError(document, env) }));
      if (response.status === 429) throw new Error('SCAN_PROVIDER_RATE_LIMITED');
      if (response.status === 401 || response.status === 403) throw new Error('SCAN_PROVIDER_AUTH_FAILED');
      throw new Error(`SCAN_PROVIDER_REJECTED:${response.status}`);
    }
    if (!document || Array.isArray(document) || typeof document !== 'object'
      || !firstText(document, ['id', 'document_id'], 160)) throw new Error('SCAN_PROVIDER_MALFORMED_RESPONSE');
    console.info(JSON.stringify({ event: 'veryfi_document_processed', scanId: externalId,
      providerDocumentId: firstText(document, ['id', 'document_id'], 160), documentType: providerDocumentType(document) }));
    return document;
  } catch (error) {
    if (controller.signal.aborted) throw new Error('SCAN_PROVIDER_TIMEOUT');
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function safeProviderError(document: any, env: CaptroScanEnv): string {
  let message = firstText(document, ['error.message', 'message', 'error', 'detail', 'code'], 600) || 'Provider returned no readable error message';
  for (const secret of [env.VERYFI_CLIENT_ID, env.VERYFI_CLIENT_SECRET, env.VERYFI_USERNAME, env.VERYFI_API_KEY]) {
    if (secret?.trim()) message = message.split(secret.trim()).join('[redacted]');
  }
  return message.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[redacted]')
    .replace(/[A-Za-z0-9+/=_-]{40,}/g, '[redacted]').replace(/[\r\n]/g, ' ');
}

async function findSemanticDuplicate(env: CaptroScanEnv, userId: string, currentId: string, extracted: any): Promise<any | null> {
  const rows = await selectRows(env, 'scan_verifications', {
    user_id: `eq.${userId}`,
    status: 'eq.verified',
    document_type: `eq.${extracted.type}`,
  }, { order: 'created_at.desc', limit: 100 });
  const targetName = cleanText(extracted.business.name, 400).toLowerCase();
  const targetNumber = cleanText(extracted.documentNumber, 160).toLowerCase();
  const targetDate = cleanText(extracted.issueDate, 80).slice(0, 10);
  const targetTotal = decimalNumber(extracted.total);
  return rows.find((row) => {
    if (row.id === currentId) return false;
    const sameNumber = targetNumber && cleanText(row.document_number, 160).toLowerCase() === targetNumber;
    const sameDate = targetDate && cleanText(row.document_date, 20).slice(0, 10) === targetDate;
    const sameName = targetName && cleanText(row.normalized_business_name, 400).toLowerCase() === targetName;
    const rowTotal = decimalNumber(row.total_amount);
    const sameTotal = targetTotal !== null && rowTotal !== null && Math.abs(targetTotal - rowTotal) <= 0.01;
    return Boolean((sameNumber && sameTotal) || (sameName && sameDate && sameTotal));
  }) || null;
}

async function restoreCredit(env: CaptroScanEnv, verificationId: string, userId: string, reason: string, state: 'refunded' | 'credited') {
  return supabaseRpc(env, 'captro_restore_scan_credit', {
    p_verification_id: verificationId,
    p_user_id: userId,
    p_reason: reason,
    p_billing_state: state,
  });
}

function rowPayload(row: any) {
  const extracted = row?.extracted_data && typeof row.extracted_data === 'object' ? row.extracted_data : {};
  return {
    verificationId: row.id,
    documentType: row.document_type,
    status: row.status,
    verdict: row.status === 'verified' ? 'Verified' : row.status === 'couldnt_verify' ? 'Unable to Verify' : null,
    business: extracted.business || null,
    customer: extracted.customer || null,
    documentNumber: row.document_number || extracted.documentNumber || null,
    transactionReference: row.transaction_reference || extracted.transactionReference || null,
    issueDate: row.document_date || extracted.issueDate || null,
    dueDate: extracted.dueDate || null,
    time: row.document_time || extracted.time || null,
    items: extracted.items || [],
    subtotal: extracted.subtotal || null,
    tax: extracted.tax || null,
    discount: extracted.discount || null,
    fees: extracted.fees || null,
    total: row.total_amount === null || row.total_amount === undefined ? extracted.total || null : String(row.total_amount),
    currency: row.currency || extracted.currency || null,
    payment: extracted.payment || null,
    paymentTerms: extracted.paymentTerms || null,
    barcodes: extracted.barcodes || [],
    checks: Array.isArray(row.checks) ? row.checks : [],
    duplicateOf: row.duplicate_of || null,
    priceChargedCents: row.billing_state === 'charged' ? row.price_cents : 0,
    billingState: row.billing_state,
    proofId: row.proof_id || null,
    createdAt: row.created_at,
    completedAt: row.completed_at || null,
  };
}

async function patchRows(
  env: CaptroScanEnv,
  table: string,
  filters: Record<string, string>,
  patch: Record<string, unknown>,
): Promise<void> {
  const { url } = supabaseConfiguration(env);
  const endpoint = new URL(`${url}/rest/v1/${table}`);
  for (const [key, value] of Object.entries(filters)) endpoint.searchParams.set(key, value);
  const response = await fetch(endpoint.toString(), {
    method: 'PATCH',
    headers: supabaseHeaders(env, 'return=minimal'),
    body: JSON.stringify(patch),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SCAN_UPDATE_FAILED:${table}:${response.status}:${text.slice(0, 500)}`);
  }
}

async function receiptRow(env: CaptroScanEnv, id: string, userId: string): Promise<any | null> {
  return (await selectRows(env, 'scanned_receipts', {
    id: `eq.${id}`,
    user_id: `eq.${userId}`,
  }, { limit: 1 }))[0] || null;
}

export function receiptReviewPayload(row: any) {
  const extracted = row?.extracted_data && typeof row.extracted_data === 'object' ? row.extracted_data : {};
  return {
    receiptId: row.id,
    documentType: row.receipt_type,
    status: row.status,
    merchantName: row.merchant_name || extracted.business?.name || null,
    category: row.category || 'general',
    business: extracted.business || null,
    documentNumber: extracted.documentNumber || null,
    transactionReference: extracted.transactionReference || null,
    customer: extracted.customer || null,
    dueDate: extracted.dueDate || null,
    paymentTerms: extracted.paymentTerms || null,
    fees: extracted.fees || null,
    discount: extracted.discount || null,
    checks: Array.isArray(row.verification_checks) ? row.verification_checks : [],
    verificationId: row.provider_request_id ? row.id : null,
    providerDocumentId: row.provider_request_id || null,
    purchaseDate: row.purchase_date || extracted.issueDate || null,
    purchaseTime: row.purchase_time || extracted.time || null,
    items: extracted.items || [],
    subtotal: extracted.subtotal || null,
    tax: extracted.tax || null,
    total: row.total_amount === null || row.total_amount === undefined ? extracted.total || null : String(row.total_amount),
    currency: row.currency || extracted.currency || null,
    verdict: row.verification_status === 'verified'
      ? 'Verified'
      : row.verification_status === 'couldnt_verify' ? 'Unable to Verify' : 'Processing',
    rewardEligible: Boolean(row.reward_eligible),
    duplicate: row.status === 'duplicate',
    rewardCents: Math.max(0, Number(row.reward_amount_cents || 0)),
    createdAt: row.created_at,
  };
}

function receiptHistoryPayload(row: any) {
  const extracted = row?.extracted_data && typeof row.extracted_data === 'object' ? row.extracted_data : {};
  const completed = ['completed', 'rewarded'].includes(cleanText(row.status, 40));
  return {
    receiptId: row.id,
    documentType: row.receipt_type,
    status: row.status,
    verdict: row.verification_status === 'verified'
      ? 'Verified'
      : row.verification_status === 'couldnt_verify' ? 'Unable to Verify' : null,
    merchantName: row.merchant_name || extracted.business?.name || null,
    purchaseDate: row.purchase_date || extracted.issueDate || null,
    total: row.total_amount === null || row.total_amount === undefined ? extracted.total || null : String(row.total_amount),
    currency: row.currency || extracted.currency || null,
    earnedCents: completed ? Math.max(0, Number(row.reward_amount_cents || 0)) : 0,
    duplicate: row.status === 'duplicate',
    createdAt: row.created_at,
  };
}

let privateReceiptBucketPromise: Promise<void> | null = null;

async function ensurePrivateReceiptBucket(env: CaptroScanEnv): Promise<void> {
  if (privateReceiptBucketPromise) return privateReceiptBucketPromise;
  privateReceiptBucketPromise = (async () => {
    const { url } = supabaseConfiguration(env);
    const lookup = await fetch(`${url}/storage/v1/bucket/${PRIVATE_RECEIPT_BUCKET}`, {
      headers: supabaseHeaders(env),
    });
    if (lookup.ok) {
      const bucket: any = await lookup.json();
      if (bucket.public !== false) throw new Error('SCAN_PRIVATE_STORAGE_NOT_PRIVATE');
      return;
    }
    const lookupError: any = await lookup.json().catch(() => ({}));
    const missing = lookup.status === 404 || lookupError.code === 'NoSuchBucket'
      || String(lookupError.statusCode) === '404' || lookupError.message === 'Bucket not found';
    if (!missing) {
      throw new Error(`SCAN_PRIVATE_STORAGE_LOOKUP_FAILED:${lookup.status}`);
    }
    const create = await fetch(`${url}/storage/v1/bucket`, {
      method: 'POST',
      headers: supabaseHeaders(env),
      body: JSON.stringify({
        id: PRIVATE_RECEIPT_BUCKET,
        name: PRIVATE_RECEIPT_BUCKET,
        public: false,
        file_size_limit: MAX_DOCUMENT_BYTES,
        allowed_mime_types: ['image/jpeg', 'image/png', 'image/heic', 'application/pdf'],
      }),
    });
    if (!create.ok && create.status !== 409) {
      const text = await create.text().catch(() => '');
      throw new Error(`SCAN_PRIVATE_STORAGE_CREATE_FAILED:${create.status}:${text.slice(0, 300)}`);
    }
  })().catch((error) => {
    privateReceiptBucketPromise = null;
    throw error;
  });
  return privateReceiptBucketPromise;
}

async function storePrivateReceipt(
  env: CaptroScanEnv,
  userId: string,
  receiptId: string,
  contentType: string,
  bytes: Uint8Array,
): Promise<string> {
  await ensurePrivateReceiptBucket(env);
  const { url } = supabaseConfiguration(env);
  const ownerHash = (await sha256Hex(userId)).slice(0, 32);
  const path = `${ownerHash}/${receiptId}/original.${fileExtension(contentType)}`;
  const headers = new Headers(supabaseHeaders(env));
  headers.set('Content-Type', contentType);
  headers.set('x-upsert', 'true');
  const response = await fetch(`${url}/storage/v1/object/${PRIVATE_RECEIPT_BUCKET}/${path}`, {
    method: 'POST',
    headers,
    body: bytes,
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SCAN_PRIVATE_STORAGE_UPLOAD_FAILED:${response.status}:${text.slice(0, 300)}`);
  }
  return path;
}

export async function signedPrivateObjectUrl(env: CaptroScanEnv, storagePath: string, bucket: 'captro-private-receipts' | 'captro-private-tickets' = PRIVATE_RECEIPT_BUCKET): Promise<string> {
  const { url } = supabaseConfiguration(env);
  const encodedPath = storagePath.split('/').map(encodeURIComponent).join('/');
  const response = await fetch(`${url}/storage/v1/object/sign/${bucket}/${encodedPath}`, {
    method: 'POST',
    headers: supabaseHeaders(env),
    body: JSON.stringify({ expiresIn: 300 }),
  });
  const data: any = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`SCAN_PRIVATE_STORAGE_SIGN_FAILED:${response.status}`);
  const signed = cleanText(data?.signedURL || data?.signedUrl || data?.signed_url, 4000);
  if (!signed) throw new Error('SCAN_PRIVATE_STORAGE_SIGN_FAILED');
  if (signed.startsWith('http')) {
    if (new URL(signed).origin !== new URL(url).origin) throw new Error('SCAN_PRIVATE_STORAGE_SIGN_FAILED');
    return signed;
  }
  return `${url}${signed.startsWith('/storage/v1/') ? '' : '/storage/v1'}${signed.startsWith('/') ? '' : '/'}${signed}`;
}

function extractedProviderText(document: any): string | null {
  const text = firstText(document, ['ocr_text', 'raw_text', 'text', 'document_text'], 50_000);
  return text || null;
}

function validRating(value: unknown): number | null {
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 5 ? rating : null;
}

async function verificationRow(env: CaptroScanEnv, id: string, userId: string): Promise<any | null> {
  return (await selectRows(env, 'scan_verifications', { id: `eq.${id}`, user_id: `eq.${userId}` }, { limit: 1 }))[0] || null;
}

async function balanceCents(env: CaptroScanEnv, userId: string): Promise<number> {
  const row = (await selectRows(env, 'scan_credit_accounts', { user_id: `eq.${userId}` }, { select: 'balance_cents', limit: 1 }))[0];
  return Math.max(0, Number(row?.balance_cents || 0));
}

async function appStoreJwt(env: CaptroScanEnv): Promise<string> {
  const issuer = cleanText(env.APP_STORE_CONNECT_API_ISSUER_ID, 200);
  const keyId = cleanText(env.APP_STORE_CONNECT_API_KEY_ID, 200);
  const keyBase64 = cleanText(env.APP_STORE_CONNECT_API_KEY_BASE64, 10000);
  const bundleId = cleanText(env.APP_STORE_BUNDLE_ID, 200) || DEFAULT_BUNDLE_ID;
  if (!issuer || !keyId || !keyBase64) throw new Error('SCAN_STOREKIT_SERVER_UNAVAILABLE');
  const pem = new TextDecoder().decode(base64ToBytes(keyBase64));
  const der = pem.includes('BEGIN PRIVATE KEY')
    ? base64ToBytes(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, ''))
    : base64ToBytes(keyBase64);
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' })));
  const payload = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: issuer,
    iat: nowSeconds,
    exp: nowSeconds + 300,
    aud: 'appstoreconnect-v1',
    bid: bundleId,
  })));
  const signingInput = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  ));
  return `${signingInput}.${base64Url(signature)}`;
}

async function appStoreTransaction(env: CaptroScanEnv, transactionId: string): Promise<{ payload: any; signed: string }> {
  const token = await appStoreJwt(env);
  const path = `/inApps/v1/transactions/${encodeURIComponent(transactionId)}`;
  for (const host of ['https://api.storekit.apple.com', 'https://api.storekit-sandbox.apple.com']) {
    const response = await fetch(`${host}${path}`, { headers: { Authorization: `Bearer ${token}`, accept: 'application/json' } });
    if (response.status === 404) continue;
    const data: any = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(`SCAN_STOREKIT_LOOKUP_FAILED:${response.status}`);
    const signed = cleanText(data?.signedTransactionInfo, 20000);
    const segments = signed.split('.');
    if (segments.length !== 3) throw new Error('SCAN_STOREKIT_RESPONSE_INVALID');
    return { payload: decodeBase64UrlJson(segments[1]), signed };
  }
  throw new Error('SCAN_STOREKIT_TRANSACTION_NOT_FOUND');
}

function errorCode(error: any): string {
  return String(error?.message || 'SCAN_UNAVAILABLE');
}

export const captroScanTestSupport = Object.freeze({
  buildChecks,
  categoryQuestionKeys: CATEGORY_QUESTION_KEYS,
  configuredRewardCents,
  purchaseCategory,
  receiptAcceptedForFeedback,
  receiptRewardFingerprint,
  verdictFromChecks,
  veryfiSignature,
  veryfiSignaturePayload,
  normalizeProviderDocument,
  providerVerify,
  safeProviderError,
  ensurePrivateReceiptBucket,
});

export function createCaptroScanRoutes(
  authMiddleware: AuthMiddleware,
  getUserId: (c: any) => string,
  enforceRateLimit: RateLimiter,
) {
  const scan = new Hono<any>();
  scan.use('*', authMiddleware);

  scan.post('/receipts/review', async (c) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'receipt_review', userId, 6, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'receipt_review_daily', userId, 30, 86400);
    if (dailyLimited) return dailyLimited;
    const declared = Number(c.req.header('content-length') || 0);
    if (Number.isFinite(declared) && declared > MAX_DOCUMENT_BYTES + 160_000) {
      return c.json({ detail: 'Document must be 12 MiB or smaller.', code: 'SCAN_DOCUMENT_TOO_LARGE' }, 413);
    }

    let receiptId = '';
    try {
      const form = await c.req.raw.formData();
      const file = form.get('file') as File | null;
      const idempotencyKey = cleanText(form.get('idempotencyKey'), 180);
      const sourceInput = cleanText(form.get('source'), 40).toLowerCase();
      const source = ['camera', 'photo_library', 'files'].includes(sourceInput) ? sourceInput : 'unknown';
      if (!file || typeof file.arrayBuffer !== 'function') {
        return c.json({ detail: 'No receipt or invoice was provided.', code: 'SCAN_DOCUMENT_MISSING' }, 400);
      }
      if (!/^[a-zA-Z0-9:_-]{16,180}$/.test(idempotencyKey)) {
        return c.json({ detail: 'Receipt review request is invalid.', code: 'SCAN_IDEMPOTENCY_INVALID' }, 400);
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (bytes.byteLength < 250 || bytes.byteLength > MAX_DOCUMENT_BYTES) {
        return c.json({ detail: 'Document must be between 250 bytes and 12 MiB.', code: 'SCAN_DOCUMENT_SIZE_INVALID' }, 400);
      }
      const contentType = detectedContentType(bytes);
      if (!contentType) {
        return c.json({ detail: 'Choose a valid JPG, PNG, HEIC/HEIF, or PDF document.', code: 'SCAN_DOCUMENT_TYPE_INVALID' }, 400);
      }
      const fileName = safeFilename(file.name, contentType);
      const documentSha256 = await sha256Hex(bytes);
      receiptId = crypto.randomUUID();
      const begin = await supabaseRpc(c.env, 'captro_begin_receipt_review', {
        p_receipt_id: receiptId,
        p_user_id: userId,
        p_idempotency_key: idempotencyKey,
        p_document_sha256: documentSha256,
        p_file_name: fileName,
        p_mime_type: contentType,
        p_detected_type: 'unsupported',
        p_source: source,
        p_reward_amount_cents: configuredRewardCents(c.env, 'unsupported'),
      });
      receiptId = cleanText(begin?.receiptId, 80) || receiptId;
      if (!['created', 'retry'].includes(cleanText(begin?.action, 30))) {
        const existing = await receiptRow(c.env, receiptId, userId);
        if (!existing) throw new Error('SCAN_EXISTING_RECEIPT_MISSING');
        return c.json(receiptReviewPayload(existing), existing.status === 'processing' ? 202 : 200);
      }

      const storagePath = await storePrivateReceipt(c.env, userId, receiptId, contentType, bytes);
      await patchRows(c.env, 'scanned_receipts', { id: `eq.${receiptId}`, user_id: `eq.${userId}` }, {
        private_storage_path: storagePath,
        provider: 'Veryfi',
        updated_at: new Date().toISOString(),
      });

      const providerDocument = await providerVerify(c.env, bytes, fileName, receiptId);
      const extracted = normalizeProviderDocument(providerDocument);
      if (extracted.type === 'unsupported') {
        await patchRows(c.env, 'scanned_receipts', { id: `eq.${receiptId}`, user_id: `eq.${userId}` }, {
          receipt_type: 'unsupported',
          status: 'unsupported',
          verification_status: 'couldnt_verify',
          reward_eligible: false,
          provider_request_id: extracted.providerRequestId || null,
          extracted_text: extractedProviderText(providerDocument),
          extracted_data: extracted,
          updated_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
        });
        const unsupported = await receiptRow(c.env, receiptId, userId);
        if (!unsupported) throw new Error('SCAN_RECEIPT_RESULT_MISSING');
        return c.json(receiptReviewPayload(unsupported));
      }

      const category = purchaseCategory(providerDocument, extracted);
      const candidateAccepted = receiptAcceptedForFeedback(extracted) && Boolean(extracted.providerRequestId);
      const rewardAmountCents = configuredRewardCents(c.env, extracted.type);
      let semanticDuplicate = extracted.signals?.duplicate === true || Boolean(extracted.signals?.duplicateOf);
      let duplicateChecked = semanticDuplicate;
      if (!semanticDuplicate) {
        const fingerprint = await receiptRewardFingerprint(extracted);
        if (fingerprint) {
          const claim = await supabaseRpc(c.env, 'captro_claim_receipt_reward_fingerprint', {
            p_receipt_id: receiptId,
            p_user_id: userId,
            p_reward_fingerprint: fingerprint,
          });
          semanticDuplicate = claim?.claimed === false;
          duplicateChecked = typeof claim?.claimed === 'boolean';
        }
      }
      const checks = buildChecks(extracted, semanticDuplicate ? 'failed' : duplicateChecked ? 'passed' : 'unavailable');
      const accepted = candidateAccepted && verdictFromChecks(checks) === 'verified';
      const completedAt = new Date().toISOString();
      await patchRows(c.env, 'scanned_receipts', { id: `eq.${receiptId}`, user_id: `eq.${userId}` }, {
        receipt_type: extracted.type,
        merchant_name: extracted.business.name,
        category,
        extracted_text: extractedProviderText(providerDocument),
        extracted_data: extracted,
        total_amount: extracted.total,
        currency: extracted.currency,
        purchase_date: normalizedDatabaseDate(extracted.issueDate),
        purchase_time: normalizedDatabaseTime(extracted.time),
        provider_request_id: extracted.providerRequestId || null,
        status: semanticDuplicate ? 'duplicate' : accepted ? 'feedback_pending' : 'review_ready',
        verification_status: accepted ? 'verified' : 'couldnt_verify',
        verification_checks: checks,
        failure_code: null,
        reward_amount_cents: rewardAmountCents,
        reward_eligible: accepted && !semanticDuplicate,
        updated_at: completedAt,
        completed_at: completedAt,
      });
      const completed = await receiptRow(c.env, receiptId, userId);
      if (!completed) throw new Error('SCAN_RECEIPT_RESULT_MISSING');
      return c.json(receiptReviewPayload(completed));
    } catch (error: any) {
      const code = errorCode(error).split(':')[0];
      console.warn(JSON.stringify({ event: 'receipt_review_failed', scanId: receiptId || null, code }));
      if (receiptId) {
        await patchRows(c.env, 'scanned_receipts', { id: `eq.${receiptId}`, user_id: `eq.${userId}` }, {
          status: 'failed',
          verification_status: 'couldnt_verify',
          reward_eligible: false,
          failure_code: code,
          updated_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
        }).catch(() => null);
      }
      const unavailable = code.includes('PROVIDER') || code.includes('STORAGE') || code.includes('DATABASE')
        || code.includes('RPC') || code.includes('UPDATE');
      return c.json({
        detail: unavailable ? 'Receipt processing is temporarily unavailable. Please try again.' : 'Captro could not process this document.',
        code,
      }, unavailable ? 503 : 400);
    }
  });

  scan.get('/receipts/history', async (c) => {
    try {
      const rows = await selectRows(c.env, 'scanned_receipts', {
        user_id: `eq.${getUserId(c)}`,
      }, { order: 'created_at.desc', limit: 50 });
      return c.json({ submissions: rows.map(receiptHistoryPayload) });
    } catch {
      return c.json({ detail: 'Receipt history is temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  scan.get('/receipts/:id/original', async (c) => {
    try {
      const row = await receiptRow(c.env, cleanText(c.req.param('id'), 80), getUserId(c));
      if (!row) return c.json({ detail: 'Receipt not found.', code: 'SCAN_RECEIPT_NOT_FOUND' }, 404);
      const storagePath = cleanText(row.private_storage_path, 1200);
      if (!storagePath) return c.json({ detail: 'Original document is unavailable.', code: 'SCAN_ORIGINAL_UNAVAILABLE' }, 404);
      c.header('Cache-Control', 'private, no-store');
      return c.json({ signedUrl: await signedPrivateObjectUrl(c.env, storagePath), expiresIn: 300 });
    } catch {
      return c.json({ detail: 'Original document is temporarily unavailable.', code: 'SCAN_PRIVATE_STORAGE_UNAVAILABLE' }, 503);
    }
  });

  scan.get('/receipts/:id', async (c) => {
    try {
      const row = await receiptRow(c.env, cleanText(c.req.param('id'), 80), getUserId(c));
      if (!row) return c.json({ detail: 'Receipt not found.', code: 'SCAN_RECEIPT_NOT_FOUND' }, 404);
      return c.json(receiptReviewPayload(row));
    } catch {
      return c.json({ detail: 'Receipt review is temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  scan.post('/receipts/:id/feedback', async (c) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'receipt_feedback', userId, 12, 60);
    if (limited) return limited;
    try {
      const receiptId = cleanText(c.req.param('id'), 80);
      const row = await receiptRow(c.env, receiptId, userId);
      if (!row) return c.json({ detail: 'Receipt not found.', code: 'SCAN_RECEIPT_NOT_FOUND' }, 404);
      const body = await c.req.json();
      const idempotencyKey = cleanText(body?.idempotencyKey ?? body?.idempotency_key, 180);
      if (!/^[a-zA-Z0-9:_-]{16,180}$/.test(idempotencyKey)) {
        return c.json({ detail: 'Feedback request is invalid.', code: 'SCAN_IDEMPOTENCY_INVALID' }, 400);
      }
      const ratings = body?.ratings && typeof body.ratings === 'object' ? body.ratings : {};
      const category = (row.category || 'general') as PurchaseCategory;
      const required = CATEGORY_QUESTION_KEYS[category] || CATEGORY_QUESTION_KEYS.general;
      const missing = required.filter((key) => validRating(ratings[key]) === null);
      if (missing.length) {
        return c.json({ detail: 'Answer every purchase question before submitting.', code: 'SCAN_FEEDBACK_INCOMPLETE' }, 400);
      }
      const note = cleanText(body?.note, 801);
      if (note.length > 800) return c.json({ detail: 'The optional note is too long.', code: 'SCAN_FEEDBACK_NOTE_TOO_LONG' }, 400);

      const result = await supabaseRpc(c.env, 'captro_submit_receipt_feedback_reward', {
        p_receipt_id: receiptId,
        p_user_id: userId,
        p_idempotency_key: idempotencyKey,
        p_cleanliness_rating: validRating(ratings.cleanliness),
        p_speed_rating: validRating(ratings.speed),
        p_quality_rating: validRating(ratings.quality),
        p_service_rating: validRating(ratings.service),
        p_value_rating: validRating(ratings.value),
        p_freshness_rating: validRating(ratings.freshness),
        p_organization_rating: validRating(ratings.organization),
        p_professionalism_rating: validRating(ratings.professionalism),
        p_satisfaction_rating: validRating(ratings.satisfaction),
        p_expectations_rating: validRating(ratings.expectations),
        p_stock_rating: validRating(ratings.stock),
        p_result_rating: validRating(ratings.result),
        p_overall_rating: validRating(ratings.overall),
        p_note: note || null,
      });
      return c.json({ ...result, currency: 'USD' });
    } catch (error: any) {
      const code = errorCode(error);
      if (code.includes('NOT_REWARD_ELIGIBLE')) {
        return c.json({ detail: 'This receipt is not eligible for another reward.', code: 'SCAN_RECEIPT_NOT_REWARD_ELIGIBLE' }, 409);
      }
      if (code.includes('OVERALL_RATING_REQUIRED')) {
        return c.json({ detail: 'Answer every purchase question before submitting.', code: 'SCAN_FEEDBACK_INCOMPLETE' }, 400);
      }
      return c.json({ detail: 'Captro could not save your feedback. Please try again.', code: code.split(':')[0] }, 503);
    }
  });

  scan.get('/rewards/balance', async (c) => {
    try {
      const rows = await selectRows(c.env, 'user_reward_balance', {
        user_id: `eq.${getUserId(c)}`,
      }, { limit: 1 });
      const row = rows[0] || {};
      return c.json({
        availableBalanceCents: Math.max(0, Number(row.available_balance_cents || 0)),
        lifetimeEarnedCents: Math.max(0, Number(row.lifetime_earned_cents || 0)),
        lifetimeWithdrawnCents: Math.max(0, Number(row.lifetime_withdrawn_cents || 0)),
        pendingRewardCents: Math.max(0, Number(row.pending_reward_cents || 0)),
        pendingWithdrawalCents: Math.max(0, Number(row.pending_withdrawal_cents || 0)),
        currency: 'USD',
        withdrawalEnabled: false,
      });
    } catch {
      return c.json({ detail: 'Receipt earnings are temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  scan.post('/rewards/withdrawals', (c) => c.json({
    detail: 'Withdrawals are not available yet. Your receipt earnings remain in your private balance.',
    code: 'SCAN_WITHDRAWALS_NOT_AVAILABLE',
  }, 501));

  scan.get('/credits', async (c) => {
    try {
      return c.json({ balanceCents: await balanceCents(c.env, getUserId(c)), verificationPriceCents: VERIFY_PRICE_CENTS });
    } catch {
      return c.json({ detail: 'Verification balance is temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  scan.post('/credits/redeem', async (c) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'scan_storekit_redeem', userId, 20, 60);
    if (limited) return limited;
    try {
      const body = await c.req.json();
      const transactionId = cleanText(body?.transactionId, 160);
      if (!/^\d{6,40}$/.test(transactionId)) return c.json({ detail: 'The App Store transaction is invalid.', code: 'SCAN_STOREKIT_TRANSACTION_INVALID' }, 400);
      const transaction = await appStoreTransaction(c.env, transactionId);
      const productId = cleanText(transaction.payload?.productId, 200);
      const product = CREDIT_PRODUCTS[productId];
      const bundleId = cleanText(transaction.payload?.bundleId, 200);
      if (!product || bundleId !== (cleanText(c.env.APP_STORE_BUNDLE_ID, 200) || DEFAULT_BUNDLE_ID)) {
        return c.json({ detail: 'This purchase is not a Captro Scan credit purchase.', code: 'SCAN_STOREKIT_PRODUCT_INVALID' }, 400);
      }
      if (cleanText(transaction.payload?.transactionId, 160) !== transactionId || transaction.payload?.revocationDate) {
        return c.json({ detail: 'This App Store transaction cannot be credited.', code: 'SCAN_STOREKIT_TRANSACTION_INVALID' }, 409);
      }
      const environment = cleanText(transaction.payload?.environment, 40) === 'Production' ? 'Production' : 'Sandbox';
      const result = await supabaseRpc(c.env, 'captro_credit_storekit_purchase', {
        p_user_id: userId,
        p_transaction_id: transactionId,
        p_original_transaction_id: cleanText(transaction.payload?.originalTransactionId, 160),
        p_product_id: productId,
        p_credit_cents: product.creditCents,
        p_paid_cents: product.paidCents,
        p_currency: cleanText(transaction.payload?.currency, 12) || 'USD',
        p_environment: environment,
        p_purchased_at: transaction.payload?.purchaseDate ? new Date(Number(transaction.payload.purchaseDate)).toISOString() : null,
        p_payload_sha256: await sha256Hex(transaction.signed),
      });
      return c.json({ ...result, verificationPriceCents: VERIFY_PRICE_CENTS });
    } catch (error: any) {
      const code = errorCode(error);
      if (code.includes('OWNED_BY_ANOTHER_USER')) return c.json({ detail: 'This purchase belongs to another account.', code: 'SCAN_STOREKIT_OWNERSHIP_MISMATCH' }, 409);
      if (code.includes('NOT_FOUND')) return c.json({ detail: 'The App Store could not find this purchase.', code: 'SCAN_STOREKIT_TRANSACTION_NOT_FOUND' }, 404);
      return c.json({ detail: 'Captro could not confirm the App Store purchase.', code: code.split(':')[0] }, 503);
    }
  });

  scan.post('/verify', async (c) => {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'scan_verify', userId, 8, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'scan_verify_daily', userId, 50, 86400);
    if (dailyLimited) return dailyLimited;
    const declared = Number(c.req.header('content-length') || 0);
    if (Number.isFinite(declared) && declared > MAX_DOCUMENT_BYTES + 160_000) {
      return c.json({ detail: 'Document must be 12 MiB or smaller.', code: 'SCAN_DOCUMENT_TOO_LARGE' }, 413);
    }

    let verificationId = '';
    let charged = false;
    try {
      const form = await c.req.raw.formData();
      const file = form.get('file') as File | null;
      const idempotencyKey = cleanText(form.get('idempotencyKey'), 180);
      const detectedType = cleanText(form.get('detectedType'), 30).toLowerCase();
      if (!file || typeof file.arrayBuffer !== 'function') return c.json({ detail: 'No document was provided.', code: 'SCAN_DOCUMENT_MISSING' }, 400);
      if (!/^[a-zA-Z0-9:_-]{16,180}$/.test(idempotencyKey)) return c.json({ detail: 'Verification request is invalid.', code: 'SCAN_IDEMPOTENCY_INVALID' }, 400);
      if (!['receipt', 'invoice'].includes(detectedType)) return c.json({ detail: "Captro couldn't recognize this as a receipt or invoice.", code: 'SCAN_DOCUMENT_UNSUPPORTED' }, 422);
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (bytes.byteLength < 250 || bytes.byteLength > MAX_DOCUMENT_BYTES) return c.json({ detail: 'Document must be between 250 bytes and 12 MiB.', code: 'SCAN_DOCUMENT_SIZE_INVALID' }, 400);
      const contentType = detectedContentType(bytes);
      if (!contentType) return c.json({ detail: 'Choose a valid JPG, PNG, HEIC/HEIF, or PDF document.', code: 'SCAN_DOCUMENT_TYPE_INVALID' }, 400);
      const fileName = safeFilename(file.name, contentType);
      const documentSha256 = await sha256Hex(bytes);
      verificationId = crypto.randomUUID();
      const begin = await supabaseRpc(c.env, 'captro_begin_scan_verification', {
        p_verification_id: verificationId,
        p_user_id: userId,
        p_idempotency_key: idempotencyKey,
        p_document_sha256: documentSha256,
        p_file_name: fileName,
        p_mime_type: contentType,
        p_detected_type: detectedType,
        p_price_cents: VERIFY_PRICE_CENTS,
      });
      verificationId = cleanText(begin?.verification_id, 80) || verificationId;
      if (begin?.action === 'existing') {
        const existing = await verificationRow(c.env, verificationId, userId);
        if (!existing) throw new Error('SCAN_EXISTING_RESULT_MISSING');
        return c.json(rowPayload(existing), existing.status === 'processing' ? 202 : 200);
      }
      charged = true;

      if (!c.env.MEDIA_BACKUP) throw new Error('SCAN_PRIVATE_STORAGE_UNAVAILABLE');
      const ownerHash = (await sha256Hex(userId)).slice(0, 32);
      const storageKey = `scan-private/${ownerHash}/${verificationId}/original.${fileExtension(contentType)}`;
      await c.env.MEDIA_BACKUP.put(storageKey, bytes, {
        httpMetadata: { contentType },
        customMetadata: { ownerHash, verificationId, documentSha256, privacy: 'private' },
      });
      await patchVerification(c.env, verificationId, userId, { private_storage_key: storageKey });

      await patchVerification(c.env, verificationId, userId, {
        provider: 'Veryfi',
        provider_attempted_at: new Date().toISOString(),
      });
      const providerDocument = await providerVerify(c.env, bytes, fileName, verificationId);
      const extracted = normalizeProviderDocument(providerDocument);
      if (extracted.type === 'unsupported') {
        await restoreCredit(c.env, verificationId, userId, 'SCAN_DOCUMENT_UNSUPPORTED', 'refunded');
        await patchVerification(c.env, verificationId, userId, { document_type: 'unsupported', status: 'unsupported' });
        return c.json({ detail: "Captro couldn't recognize this as a receipt or invoice.", code: 'SCAN_DOCUMENT_UNSUPPORTED', billingState: 'refunded' }, 422);
      }

      const checks = buildChecks(extracted);
      const semanticDuplicate = await findSemanticDuplicate(c.env, userId, verificationId, extracted);
      const duplicateCheck = checks.find((check) => check.key === 'duplicate_check');
      if (duplicateCheck) duplicateCheck.status = semanticDuplicate ? 'failed' : 'passed';
      if (semanticDuplicate) {
        const duplicateCheck = checks.find((check) => check.key === 'duplicate_check');
        if (duplicateCheck) {
          duplicateCheck.status = 'failed';
          duplicateCheck.detail = 'This document matches a prior verification.';
        }
        await restoreCredit(c.env, verificationId, userId, 'SCAN_DUPLICATE_DOCUMENT', 'credited');
      }
      const status = semanticDuplicate ? semanticDuplicate.status : verdictFromChecks(checks);
      const address = extracted.business.address;
      const completedAt = new Date().toISOString();
      const patch: Record<string, unknown> = {
        document_type: extracted.type,
        status,
        provider_request_id: extracted.providerRequestId || null,
        normalized_business_name: extracted.business.name,
        original_address_text: address.original || null,
        address_street: address.street || null,
        address_city: address.city || null,
        address_state: address.state || null,
        address_postal_code: address.postalCode || null,
        address_country: address.country || null,
        document_number: extracted.documentNumber,
        transaction_reference: extracted.transactionReference,
        document_date: normalizedDatabaseDate(extracted.issueDate),
        document_time: normalizedDatabaseTime(extracted.time),
        total_amount: extracted.total,
        currency: extracted.currency,
        extracted_data: extracted,
        checks,
        duplicate_of: semanticDuplicate?.id || null,
        completed_at: completedAt,
      };
      await patchVerification(c.env, verificationId, userId, patch);

      if (status === 'verified' && !semanticDuplicate) {
        const proofId = crypto.randomUUID();
        await insertProof(c.env, {
          id: proofId,
          user_id: userId,
          verification_id: verificationId,
          document_type: extracted.type,
          public_summary: {
            businessName: extracted.business.name,
            city: address.city || null,
            state: address.state || null,
            documentNumber: extracted.documentNumber,
            issueDate: extracted.issueDate,
            total: extracted.total,
            currency: extracted.currency,
          },
        });
        await patchVerification(c.env, verificationId, userId, { proof_id: proofId });
      }
      const completed = await verificationRow(c.env, verificationId, userId);
      return c.json(rowPayload(completed));
    } catch (error: any) {
      const code = errorCode(error);
      if (code.includes('SCAN_CREDITS_REQUIRED')) {
        return c.json({ detail: 'Add verification credits to continue.', code: 'SCAN_CREDITS_REQUIRED', verificationPriceCents: VERIFY_PRICE_CENTS }, 402);
      }
      if (verificationId && charged) {
        await restoreCredit(c.env, verificationId, userId, code.split(':')[0], 'refunded').catch(() => null);
      }
      const unavailable = code.includes('PROVIDER') || code.includes('STORAGE') || code.includes('DATABASE') || code.includes('RPC') || code.includes('UPDATE');
      return c.json({
        detail: unavailable ? 'Captro could not complete this verification. The verification credit was restored.' : 'Captro could not process this document.',
        code: code.split(':')[0],
        billingState: charged ? 'refunded' : 'not_charged',
      }, unavailable ? 503 : 400);
    }
  });

  scan.get('/verifications/:id', async (c) => {
    try {
      const row = await verificationRow(c.env, cleanText(c.req.param('id'), 80), getUserId(c));
      if (!row) return c.json({ detail: 'Verification not found.', code: 'SCAN_VERIFICATION_NOT_FOUND' }, 404);
      return c.json(rowPayload(row));
    } catch {
      return c.json({ detail: 'Verification is temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  scan.get('/proofs/:id', async (c) => {
    try {
      const rows = await selectRows(c.env, 'scan_proofs', {
        id: `eq.${cleanText(c.req.param('id'), 80)}`,
        user_id: `eq.${getUserId(c)}`,
      }, { limit: 1 });
      if (!rows[0]) return c.json({ detail: 'Proof not found.', code: 'SCAN_PROOF_NOT_FOUND' }, 404);
      return c.json({ proofId: rows[0].id, verificationId: rows[0].verification_id, documentType: rows[0].document_type, summary: rows[0].public_summary, createdAt: rows[0].created_at });
    } catch {
      return c.json({ detail: 'Proof is temporarily unavailable.', code: 'SCAN_DATABASE_UNAVAILABLE' }, 503);
    }
  });

  return scan;
}
