import contract from '../../ios_native/MIRA/Sources/MIRANative/Resources/CaptroCurrencyContract.json' with { type: 'json' };

// Provider charge units, not a universal cents conversion. Unsupported provider
// special cases stay disabled until explicitly modeled and tested.
export function currencyRule(code: unknown) {
  if (typeof code !== 'string' || !Object.hasOwn(contract.currencies, code)) throw new Error('CAPTRO_CURRENCY_UNSUPPORTED');
  return contract.currencies[code as keyof typeof contract.currencies];
}
export function validateCurrencyAmount(amount: unknown, code: string, paid = true): number {
  const rule = currencyRule(code);
  if (typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount < (paid ? rule.minimum : 0) || amount > rule.maximum) {
    throw new Error('CAPTRO_CURRENCY_AMOUNT_INVALID');
  }
  return amount;
}
/** Canonical decimal input uses '.' and no grouping; UI localizes before this boundary. */
export function decimalProviderUnits(value: string, code: string, paid = true): number {
  const rule = currencyRule(code);
  if (!/^\d+(?:\.\d+)?$/.test(value)) throw new Error('CAPTRO_CURRENCY_AMOUNT_INVALID');
  const [whole, fraction = ''] = value.split('.');
  if (fraction.length > rule.exponent) throw new Error('CAPTRO_CURRENCY_PRECISION_INVALID');
  const amount = BigInt(whole) * (10n ** BigInt(rule.exponent)) + BigInt(fraction.padEnd(rule.exponent, '0') || '0');
  return validateCurrencyAmount(Number(amount), code, paid);
}

/** Display integer provider units without binary floating-point scaling. */
export function formatProviderMoney(amount: number, code: string, locale?: string): string {
  if (!Number.isSafeInteger(amount)) return 'Amount unavailable';
  let rule;
  try { rule = currencyRule(code); } catch { return `${code} ${amount} provider units`; }
  const scale = 10n ** BigInt(rule.exponent);
  const value = BigInt(amount), absolute = value < 0 ? -value : value;
  const whole = absolute / scale;
  const fraction = (absolute % scale).toString().padStart(rule.exponent, '0');
  // Use -1 solely to obtain the locale's negative pattern when |amount| < 1.
  const displayWhole = value < 0 ? -(whole || 1n) : whole;
  return new Intl.NumberFormat(locale, {style:'currency', currency:code,
    minimumFractionDigits:rule.exponent, maximumFractionDigits:rule.exponent})
    .formatToParts(displayWhole).map(part => part.type === 'fraction' ? fraction
      : part.type === 'integer' && whole === 0n ? '0' : part.value).join('');
}

export function currencyFeeUnits(env: Record<string, unknown>, currency: string) {
  currencyRule(currency);
  if (currency === 'USD') return {
    fixed: Number(env.CAPTRO_SERVICE_FEE_FIXED_CENTS ?? 30),
    minimum: Number(env.CAPTRO_SERVICE_FEE_MINIMUM_CENTS ?? 0),
  };
  // Do not apply a dollar-denominated fixed fee to another currency or invent
  // an exchange rate. Non-USD enablement requires a reviewed provider-unit fee.
  let config: any;
  try { config = JSON.parse(String(env.CAPTRO_CURRENCY_FEES ?? '{}'))[currency]; } catch {}
  if (!config || !Number.isSafeInteger(config.fixed) || !Number.isSafeInteger(config.minimum)
      || config.fixed < 0 || config.minimum < 0 || config.fixed > 100000 || config.minimum > 100000) {
    throw new Error('CAPTRO_CURRENCY_FEE_NOT_CONFIGURED');
  }
  return { fixed: config.fixed, minimum: config.minimum };
}
