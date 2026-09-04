import assert from 'node:assert/strict';
import test from 'node:test';
import { cents, stripeMode, saleAmounts, eligibleDebitCard, instantBalance, payoutQuote } from '../src/stripe-money.ts';

const fees = { basisPoints: 500, fixedAmount: 50, minimumAmount: 0, buyerPaysPlatformFee: true, creatorPaysPlatformFee: false };
const card = { id: 'card_test', object: 'card', funding: 'debit', currency: 'usd', exp_month: 12, exp_year: 2099, available_payout_methods: ['instant'] };
const balance = { instant_available: [{ currency: 'usd', amount: 6500, net_available: [{ destination: card.id, amount: 6500 }] }] };

test('twenty dollar purchase preserves creator proceeds and calculates integer fees', () => {
  assert.deepEqual(saleAmounts(2000, fees), { itemAmount: 2000, serviceFeeAmount: 150, creatorAmount: 2000, platformFeeAmount: 150, taxAmount: 0, buyerTotal: 2150 });
  assert.equal(saleAmounts(999, fees).serviceFeeAmount, 100);
  assert.equal(saleAmounts(0, fees).buyerTotal, 0);
  assert.equal(saleAmounts(2000, { ...fees, buyerPaysPlatformFee: false, creatorPaysPlatformFee: true }).creatorAmount, 1850);
  assert.throws(() => saleAmounts(2000, { ...fees, creatorPaysPlatformFee: true }));
  for (const value of ['2000', 20.50, NaN, Infinity, -1, Number.MAX_SAFE_INTEGER]) assert.throws(() => cents(value));
});

test('Stripe mode must be explicit and both keys must match', () => {
  assert.equal(stripeMode({ STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_PUBLISHABLE_KEY: 'pk_test_fixture' }), 'test');
  assert.throws(() => stripeMode({ STRIPE_SECRET_KEY: 'sk_live_fixture' }));
  assert.throws(() => stripeMode({ STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'sk_live_fixture', STRIPE_PUBLISHABLE_KEY: 'pk_test_fixture' }));
});

test('payout destination must be a currently eligible debit card, never a bank or credit card', () => {
  assert.equal(eligibleDebitCard(card, 'USD'), true);
  for (const change of [{ object: 'bank_account' }, { funding: 'credit' }, { funding: 'unknown' },
    { available_payout_methods: ['standard'] }, { exp_year: 2020 }, { currency: 'eur' }]) {
    assert.equal(eligibleDebitCard({ ...card, ...change }, 'USD'), false);
  }
});

test('withdrawals use Stripe destination-specific net instant balance, not sales or general available', () => {
  assert.equal(instantBalance({ ...balance, available: [{ amount: 10000, currency: 'usd' }] }, card.id, 'USD'), 6500);
  assert.equal(instantBalance(balance, 'card_other', 'USD'), 0);
  assert.equal(instantBalance({ instant_available: [{ amount: 10000, currency: 'usd' }] }, card.id, 'USD'), 0);
  const config = { CAPTRO_PAYOUT_FEE_POLICY: 'platform_absorbs' };
  assert.equal(payoutQuote(5000, balance, card.id, 'USD', config).netAmount, 5000);
  assert.throws(() => payoutQuote(6501, balance, card.id, 'USD', config));
  assert.throws(() => payoutQuote(49, balance, card.id, 'USD', config));
  assert.throws(() => payoutQuote(5000, balance, card.id, 'USD', {}));
  assert.throws(() => payoutQuote(5000, { instant_available: [{ currency: 'usd', amount: 6500,
    net_available: [{ destination: card.id, amount: 6435 }] }] }, card.id, 'USD', config), /PRICING_MISMATCH/);
});
