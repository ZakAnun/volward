export const PAY_PAGE_COPY = {
  loading: 'Opening secure checkout…',
  missingTransaction: 'Invalid payment link. Return to Volward and try again.',
  missingToken: 'Payment is not configured. Please try again later.',
  loadFailed: 'Could not load payment service. Please try again later.',
  ready: 'Complete payment in the window above.',
  success: 'Payment complete. You can close this tab and return to Volward.',
  retry: 'Try again',
} as const;

export function parsePaddleTransactionId(search: string): string | null {
  const params = new URLSearchParams(search.startsWith('?') ? search : `?${search}`);
  const value = params.get('_ptxn')?.trim();
  return value ? value : null;
}

export function mapPaddleJsEnvironment(env: string): 'sandbox' | 'production' {
  return env.trim().toLowerCase() === 'live' ? 'production' : 'sandbox';
}
