import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchSnapshots, summarizeInvestments, syncValuations, setValuation } from './investment-sync.mjs';

const now = new Date('2026-10-21T12:00:00Z');
const holding = (id, balance, extra = {}) => ({ id, balance, status: 'ACTIVE', currencyCode: 'BRL', date: '2026-10-20', ...extra });

test('sum active lots in cents, excluding redeemed and unsettled investments', () => {
  assert.equal(summarizeInvestments([holding('a', 10.12), holding('b', 0.13), holding('c', 100, { status: 'TOTAL_WITHDRAWAL' }), holding('d', 50, { status: 'PENDING' })], now).total, 1025);
});

test('reject incomplete, duplicate, foreign-currency and stale valuations', () => {
  for (const rows of [[], [holding('a', 1), holding('a', 2)], [holding('a', 1, { currencyCode: 'USD' })], [holding('a', 1, { date: '2026-01-01' })], [holding('a', -1)]]) {
    assert.throws(() => summarizeInvestments(rows, now));
  }
});

test('fetch all pages before deriving a valuation; do not silently accept truncated pages', async () => {
  const fake = incomplete => async url => ({ ok: true, json: async () => {
    if (url.endsWith('/auth')) return { apiKey: 'test-only' };
    if (url.includes('/items/')) return { status: 'UPDATED', executionStatus: 'SUCCESS', lastUpdatedAt: now.toISOString() };
    return { total: 2, totalPages: 2, results: url.endsWith('page=1') ? [holding('a', 10)] : incomplete ? [] : [holding('b', 20)] };
  } });
  const args = { clientId: 'test-only', clientSecret: 'test-only', sources: [{ key: 'test', itemId: 'test', accountName: 'Portfolio' }], now };
  assert.equal((await fetchSnapshots({ ...args, fetchImpl: fake(false) }))[0].total, 3000);
  await assert.rejects(fetchSnapshots({ ...args, fetchImpl: fake(true) }), /Incomplete/);
});

function budget() {
  const transactions = [{ id: 'deposit', date: '2026-10-01', amount: 10000, notes: 'Contribution already recorded' }];
  let writes = 0;
  return {
    transactions, writes: () => writes,
    getAccounts: async () => [{ id: 'portfolio', offbudget: true, closed: false }, { id: 'checking', offbudget: false }],
    getTransactions: async () => transactions,
    getPayees: async () => [{ id: 'valuation-payee', name: 'Atualização de patrimônio (Pluggy)' }],
    addTransactions: async (id, rows) => { writes++; transactions.push(...rows); },
    updateTransaction: async (id, fields) => { writes++; Object.assign(transactions.find(t => t.id === id), fields); },
    getAccountBalance: async () => transactions.reduce((sum, t) => sum + t.amount, 0),
  };
}

const snapshot = total => ({ source: { key: 'test', accountId: 'portfolio' }, total, date: '2026-10-21', active: 1, oldest: '2026-10-20', newest: '2026-10-20', refreshedAt: now.toISOString() });

test('existing contributions are not counted again; repeated snapshots are idempotent', async () => {
  const api = budget();
  await syncValuations(api, [snapshot(10500)]);
  assert.equal(await api.getAccountBalance(), 10500);
  assert.equal(api.transactions.at(-1).amount, 500);
  const count = api.transactions.length;
  await syncValuations(api, [snapshot(10500)]);
  assert.equal(api.writes(), 1);
  assert.equal(api.transactions.length, count);
  await syncValuations(api, [snapshot(10600)]);
  assert.equal(api.transactions.length, count);
  assert.equal(await api.getAccountBalance(), 10600);
  assert.equal(api.transactions.at(-1).amount, 600);
});

test('a changed later snapshot adjusts only the difference and refuses going backwards', async () => {
  const api = budget();
  await syncValuations(api, [snapshot(10500)]);
  await syncValuations(api, [{ ...snapshot(10400), date: '2026-10-22' }]);
  assert.equal(api.transactions.at(-1).amount, -100);
  await assert.rejects(syncValuations(api, [snapshot(10500)]), /older valuation/);
});

test('never write an investment valuation into a spending account', async () => {
  const api = budget();
  await assert.rejects(setValuation(api, { accountId: 'checking', key: 'test', total: 100, date: '2026-10-21', notes: '' }), /off-budget/);
  assert.equal(api.writes(), 0);
});

test('credit remainder falls when a pending purchase becomes a booked expense, without counting debt twice', async () => {
  const api = budget();
  const byAccount = { portfolio: [], remainder: [] };
  let booked = -50000;
  api.getAccounts = async () => [{ id: 'portfolio', offbudget: true }, { id: 'remainder', offbudget: true }, { id: 'card', offbudget: false }];
  api.getTransactions = async id => byAccount[id];
  api.addTransactions = async (id, rows) => byAccount[id].push(...rows);
  api.updateTransaction = async (id, fields) => Object.assign(Object.values(byAccount).flat().find(t => t.id === id), fields);
  api.getAccountBalance = async id => id === 'card' ? booked : byAccount[id].reduce((s, t) => s + t.amount, 0);
  const s = { ...snapshot(100000), creditDebt: 130000, source: { ...snapshot(0).source, creditRemainder: { ledgerAccountId: 'card', accountId: 'remainder' } } };
  await syncValuations(api, [s]);
  assert.equal(await api.getAccountBalance('remainder'), -80000);
  assert.equal(booked + await api.getAccountBalance('remainder'), -130000);
  const count = byAccount.remainder.length;
  await syncValuations(api, [s]);
  assert.equal(byAccount.remainder.length, count);
  booked -= 10000;
  await syncValuations(api, [s]);
  assert.equal(await api.getAccountBalance('remainder'), -70000);
  assert.equal(booked + await api.getAccountBalance('remainder'), -130000);
  booked = -140000;
  const portfolioBefore = JSON.stringify(byAccount.portfolio);
  await assert.rejects(syncValuations(api, [s]), /exceeds provider/);
  assert.equal(JSON.stringify(byAccount.portfolio), portfolioBefore);
});

test('credit remainder cannot reuse the investment target or consume a closed/off-budget ledger', async () => {
  const api = budget();
  const s = { ...snapshot(1000), creditDebt: 100, source: { ...snapshot(0).source, creditRemainder: { ledgerAccountId: 'checking', accountId: 'portfolio' } } };
  await assert.rejects(syncValuations(api, [s]), /duplicate/);
  assert.equal(api.writes(), 0);
});

test('credit provider must be the configured item, a BRL card, and a finite nonnegative debt', async () => {
  const source = { key: 'test', itemId: 'item', accountName: 'Portfolio', creditRemainder: { providerAccountId: 'card' } };
  const args = { clientId: 'test', clientSecret: 'test', sources: [source], now };
  for (const overrides of [{ itemId: 'wrong' }, { currencyCode: 'USD' }, { balance: -1 }, { balance: null }, { type: 'BANK' }]) {
    const fetchImpl = async url => ({ ok: true, json: async () => {
      if (url.endsWith('/auth')) return { apiKey: 'test' };
      if (url.includes('/items/')) return { status: 'UPDATED', executionStatus: 'SUCCESS', lastUpdatedAt: now.toISOString() };
      if (url.includes('/investments?')) return { total: 1, totalPages: 1, results: [holding('a', 100)] };
      return { itemId: 'item', type: 'CREDIT', subtype: 'CREDIT_CARD', currencyCode: 'BRL', balance: 10, ...overrides };
    } });
    await assert.rejects(fetchSnapshots({ ...args, fetchImpl }), /credit liability/);
  }
});
