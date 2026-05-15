import api from './client';

export type StripeConfig = {
  connected: boolean;
  publishable_key: string;
  default_price_configured: boolean;
};

export type StripeAccountStatus = {
  connected: boolean;
  account_id?: string;
  business_name?: string;
  country?: string;
  default_currency?: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
};

export type StripeCheckoutSession = {
  id: string;
  url: string;
  mode?: string;
  status?: string;
};

export async function getStripeConfig(): Promise<StripeConfig> {
  const response = await api.get('/stripe/config');
  return response.data;
}

export async function getStripeAccountStatus(): Promise<StripeAccountStatus> {
  const response = await api.get('/stripe/account');
  return response.data;
}

export async function createStripeCheckoutSession(input: {
  price_id?: string;
  mode?: 'payment' | 'subscription';
  quantity?: number;
  success_url?: string;
  cancel_url?: string;
  client_request_id?: string;
}): Promise<StripeCheckoutSession> {
  const response = await api.post('/stripe/checkout/sessions', input);
  return response.data;
}
