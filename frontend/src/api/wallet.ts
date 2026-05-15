import api from './client';

export type CoinPackage = {
  id: string;
  label: string;
  coins: number;
  amount_cents: number;
  price: string;
};

export type CoinTransaction = {
  id: string;
  type: string;
  amount: number;
  balance_after: number;
  status: string;
  related_user_id?: string;
  related_id?: string;
  stripe_session_id?: string;
  stripe_payment_intent_id?: string;
  metadata?: Record<string, unknown>;
  created_at: string;
};

export type WalletState = {
  balance: number;
  lifetime_purchased: number;
  lifetime_spent: number;
  updated_at: string;
  packages: CoinPackage[];
  custom_purchase: {
    min_coins: number;
    max_coins: number;
    cents_per_coin: number;
  };
  stripe_connected: boolean;
  transactions: CoinTransaction[];
};

export type CoinCheckoutSession = {
  id: string;
  url: string;
  mode?: string;
  status?: string;
  order_id: string;
  coins: number;
  amount_cents: number;
};

export async function getWallet(): Promise<WalletState> {
  const response = await api.get('/wallet');
  return response.data;
}

export async function getCoinTransactions(limit = 50): Promise<CoinTransaction[]> {
  const response = await api.get('/wallet/transactions', { params: { limit } });
  return response.data.transactions || [];
}

export async function createCoinCheckout(input: {
  package_id?: string;
  coins?: number;
  success_url?: string;
  cancel_url?: string;
  client_request_id?: string;
}): Promise<CoinCheckoutSession> {
  const response = await api.post('/wallet/checkout', input);
  return response.data;
}

export async function spendCoins(input: {
  coins: number;
  purpose?: 'spend' | 'boost';
  related_id?: string;
  client_request_id?: string;
}) {
  const response = await api.post('/wallet/spend', input);
  return response.data;
}

export async function sendCoinGift(input: {
  to_user_id: string;
  coins: number;
  note?: string;
  post_id?: string;
  gift_type?: string;
  client_request_id?: string;
}) {
  const response = await api.post('/wallet/gifts', input);
  return response.data;
}
