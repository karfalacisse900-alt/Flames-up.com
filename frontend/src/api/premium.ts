import api from './client';

export type PremiumStatus = {
  is_premium: boolean;
  plan: string;
  status: string;
  premium_until?: string;
  monthly_price: string;
  amount_cents: number;
  currency: string;
  interval: string;
  anonymous_notes_used_today: number;
  anonymous_notes_remaining_today: number;
  features: string[];
  stripe_connected: boolean;
  price_configured?: boolean;
};

export type PremiumCheckoutSession = {
  id: string;
  url: string;
  mode?: string;
  status?: string;
  plan: string;
  amount_cents: number;
};

export async function getPremiumStatus(): Promise<PremiumStatus> {
  const response = await api.get('/premium');
  return response.data;
}

export async function createPremiumCheckout(input: {
  success_url?: string;
  cancel_url?: string;
  client_request_id?: string;
}): Promise<PremiumCheckoutSession> {
  const response = await api.post('/premium/checkout', input);
  return response.data;
}
