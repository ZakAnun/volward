import { describe, expect, it } from 'vitest';
import {
  mapPaddleJsEnvironment,
  parsePaddleTransactionId,
} from '../src/lib/paddle-checkout';

describe('parsePaddleTransactionId', () => {
  it('reads _ptxn from query string', () => {
    expect(parsePaddleTransactionId('?_ptxn=txn_01abc&foo=bar')).toBe('txn_01abc');
  });

  it('returns null when _ptxn missing', () => {
    expect(parsePaddleTransactionId('')).toBeNull();
    expect(parsePaddleTransactionId('?foo=bar')).toBeNull();
  });

  it('returns null when _ptxn empty', () => {
    expect(parsePaddleTransactionId('?_ptxn=')).toBeNull();
    expect(parsePaddleTransactionId('?_ptxn=%20')).toBeNull();
  });
});

describe('mapPaddleJsEnvironment', () => {
  it('maps sandbox', () => {
    expect(mapPaddleJsEnvironment('sandbox')).toBe('sandbox');
  });

  it('maps live to production', () => {
    expect(mapPaddleJsEnvironment('live')).toBe('production');
  });

  it('defaults unknown to sandbox', () => {
    expect(mapPaddleJsEnvironment('')).toBe('sandbox');
    expect(mapPaddleJsEnvironment('staging')).toBe('sandbox');
  });
});
