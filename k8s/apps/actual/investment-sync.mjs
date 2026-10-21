import { createHash } from 'node:crypto';

const API_URL = 'https://api.pluggy.ai';
const MARKER = '[pluggy-valuation:';

export function transactionId(key, date) {
  const hex = createHash('sha256').update(`actual-pluggy-valuation:${key}:${date}`).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

export function summarizeInvestments(rows, now = new Date()) {
  if (!rows.length) throw new Error('Empty investment response; refusing to zero an existing portfolio');
  const seen = new Set();
  let total = 0;
  const dates = [];
  let active = 0;
  for (const row of rows) {
    if (!row.id || seen.has(row.id)) throw new Error('Missing or duplicate investment ID');
    seen.add(row.id);
    if (!['ACTIVE', 'PENDING', 'TOTAL_WITHDRAWAL'].includes(row.status)) throw new Error('Unknown investment status');
    if (row.status !== 'ACTIVE') continue;
    if (row.currencyCode !== 'BRL') throw new Error('Non-BRL investment; currency conversion is not supported');
    if (typeof row.balance !== 'number' || !Number.isFinite(row.balance) || row.balance < 0) throw new Error('Invalid investment balance');
    const date = new Date(row.date);
    if (!Number.isFinite(date.getTime()) || date > now || now - date > 45 * 86400000) throw new Error('Invalid or stale investment valuation date');
    total += Math.round(row.balance * 100);
    dates.push(date.toISOString().slice(0, 10));
    active++;
  }
  if (!Number.isSafeInteger(total)) throw new Error('Investment total exceeds safe integer range');
  dates.sort();
  return { total, active, records: rows.length, oldest: dates[0] ?? null, newest: dates.at(-1) ?? null };
}

export async function fetchSnapshots({ clientId, clientSecret, sources, now = new Date(), fetchImpl = fetch }) {
  if (!clientId || !clientSecret || !Array.isArray(sources) || !sources.length) throw new Error('Missing investment sync configuration');
  if (new Set(sources.map(s => s.key)).size !== sources.length) throw new Error('Duplicate investment source key');
  async function request(path, options = {}) {
    const response = await fetchImpl(API_URL + path, { ...options, signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`Pluggy request failed (HTTP ${response.status})`);
    return response.json();
  }
  const { apiKey } = await request('/auth', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ clientId, clientSecret }),
  });
  if (!apiKey) throw new Error('Pluggy authentication did not return an API key');
  const headers = { 'X-API-KEY': apiKey };
  const snapshots = [];
  for (const source of sources) {
    if (!/^[a-z0-9-]+$/.test(source.key) || !source.itemId || !source.accountName) throw new Error('Invalid investment source');
    const item = await request(`/items/${encodeURIComponent(source.itemId)}`, { headers });
    const updated = new Date(item.lastUpdatedAt);
    if (item.status !== 'UPDATED' || item.executionStatus !== 'SUCCESS' || !Number.isFinite(updated.getTime()) || updated > now || now - updated > 7 * 86400000) {
      throw new Error(`Investment source ${source.key} is not successfully refreshed within seven days`);
    }
    const rows = [];
    let page = 1;
    let totalPages = 1;
    let expectedTotal;
    do {
      const result = await request(`/investments?itemId=${encodeURIComponent(source.itemId)}&pageSize=500&page=${page}`, { headers });
      if (!Array.isArray(result.results) || !Number.isInteger(result.total) || !Number.isInteger(result.totalPages) || result.totalPages > 20) throw new Error('Invalid investment pagination');
      expectedTotal ??= result.total;
      if (expectedTotal !== result.total) throw new Error('Investment data changed during pagination');
      rows.push(...result.results);
      totalPages = result.totalPages;
      page++;
    } while (page <= totalPages);
    if (rows.length !== expectedTotal) throw new Error('Incomplete investment response');
    const summary = summarizeInvestments(rows, now);
    const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Fortaleza', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
    let cash;
    if (source.providerCashAccountId) {
      const account = await request(`/accounts/${encodeURIComponent(source.providerCashAccountId)}`, { headers });
      if (account.itemId !== source.itemId || account.type !== 'BANK' || account.currencyCode !== 'BRL' || !Number.isFinite(account.balance)) throw new Error('Unexpected brokerage cash account');
      cash = Math.round(account.balance * 100);
    }
    let creditDebt;
    if (source.creditRemainder) {
      const account = await request(`/accounts/${encodeURIComponent(source.creditRemainder.providerAccountId)}`, { headers });
      if (account.itemId !== source.itemId || account.type !== 'CREDIT' || account.subtype !== 'CREDIT_CARD' || account.currencyCode !== 'BRL' || !Number.isFinite(account.balance) || account.balance < 0) throw new Error('Invalid credit liability snapshot');
      creditDebt = Math.round(account.balance * 100);
      if (!Number.isSafeInteger(creditDebt)) throw new Error('Invalid credit liability amount');
    }
    snapshots.push({ source, ...summary, date, cash, creditDebt, refreshedAt: item.lastUpdatedAt });
  }
  return snapshots;
}

export async function setValuation(api, { accountId, key, total, date, notes }) {
  if (!Number.isSafeInteger(total)) throw new Error('Valuation must be integer cents');
  const account = (await api.getAccounts()).find(a => a.id === accountId);
  if (!account?.offbudget || account.closed) throw new Error('Valuation target must be an open off-budget account');
  const transactions = await api.getTransactions(accountId, '1900-01-01', '9999-12-31');
  const marker = `${MARKER}${key}]`;
  if (transactions.some(t => t.notes?.startsWith(marker) && t.date > date)) throw new Error('Refusing an older valuation after a newer snapshot');
  const id = transactionId(key, date);
  const existing = transactions.find(t => t.id === id);
  const prior = transactions.filter(t => t.id !== id && t.date <= date).reduce((sum, t) => sum + t.amount, 0);
  const amount = total - prior;
  if (!Number.isSafeInteger(amount)) throw new Error('Invalid valuation adjustment');
  const text = `${marker} ${notes}`;
  if (existing) {
    if (existing.amount === amount && existing.notes === text) return { changed: false, amount: 0 };
    await api.updateTransaction(id, { amount, notes: text });
  } else {
    if (amount === 0) return { changed: false, amount: 0 };
    const payeeName = 'Atualização de patrimônio (Pluggy)';
    const payees = await api.getPayees();
    const payee = payees.find(p => p.name === payeeName)?.id ?? await api.createPayee({ name: payeeName });
    await api.addTransactions(accountId, [{ id, date, amount, payee, notes: text, cleared: true }]);
  }
  const balance = await api.getAccountBalance(accountId, new Date(date + 'T23:59:59.999Z'));
  if (balance !== total) throw new Error('Post-write investment balance verification failed');
  return { changed: true, amount };
}

export async function syncValuations(api, snapshots) {
  // Validate every target before writing any valuation.
  const accounts = await api.getAccounts();
  const ids = snapshots.flatMap(s => [s.source.accountId, ...(s.source.creditRemainder ? [s.source.creditRemainder.accountId] : [])]);
  if (new Set(ids).size !== ids.length || ids.some(id => !id)) throw new Error('Missing or duplicate investment target account');
  for (const id of ids) {
    const a = accounts.find(a => a.id === id);
    if (!a?.offbudget || a.closed) throw new Error('Investment target must be open and off-budget');
  }
  const creditTargets = new Map();
  for (const snapshot of snapshots.filter(s => s.source.creditRemainder)) {
    const config = snapshot.source.creditRemainder;
    const ledger = accounts.find(a => a.id === config.ledgerAccountId);
    if (!ledger || ledger.closed || ledger.offbudget || !Number.isSafeInteger(snapshot.creditDebt) || snapshot.creditDebt < 0) throw new Error('Invalid credit ledger or amount');
    const booked = await api.getAccountBalance(ledger.id);
    const remainder = -snapshot.creditDebt - booked;
    if (!Number.isSafeInteger(booked) || booked > 0 || !Number.isSafeInteger(remainder) || remainder > 0) throw new Error('Booked card debt exceeds provider total; reconcile the card before updating its remainder');
    creditTargets.set(snapshot.source.key, remainder);
  }
  const results = [];
  for (const snapshot of snapshots) {
    const notes = `Saldo agregado BRL; ${snapshot.active} posições ativas; avaliações ${snapshot.oldest ?? 'nenhuma'} a ${snapshot.newest ?? 'nenhuma'}; coleta ${snapshot.refreshedAt}. Ajuste de patrimônio, não rendimento puro.`;
    results.push({ key: snapshot.source.key, ...await setValuation(api, {
      accountId: snapshot.source.accountId, key: snapshot.source.key, total: snapshot.total, date: snapshot.date, notes,
    }) });
    if (snapshot.source.creditRemainder) {
      results.push({ key: snapshot.source.key + '-credit-remainder', ...await setValuation(api, {
        accountId: snapshot.source.creditRemainder.accountId, key: snapshot.source.key + '-credit-remainder',
        total: creditTargets.get(snapshot.source.key), date: snapshot.date,
        notes: `Passivo complementar: limite utilizado BRL ${snapshot.creditDebt / 100} menos dívida já registrada no cartão. Inclui parcelas futuras e movimentos ainda não detalhados; não é despesa nem receita. Coleta ${snapshot.refreshedAt}.`,
      }) });
    }
  }
  return results;
}

export async function setupInvestmentAccounts(api, snapshots) {
  const original = await api.getAccounts();
  const protectedBalances = new Map();
  for (const a of original.filter(a => !a.offbudget)) protectedBalances.set(a.id, await api.getAccountBalance(a.id));
  const configured = [];
  for (const snapshot of snapshots) {
    const source = { ...snapshot.source };
    const matches = (await api.getAccounts()).filter(a => a.name === source.accountName);
    if (matches.length > 1 || matches.some(a => !a.offbudget || a.closed)) throw new Error('Ambiguous investment account name');
    source.accountId = matches[0]?.id ?? await api.createAccount({ name: source.accountName, offbudget: true });
    for (const id of source.legacyAccountIds ?? []) {
      const legacy = (await api.getAccounts()).find(a => a.id === id);
      if (!legacy?.offbudget || id === source.accountId) throw new Error('Invalid legacy investment account');
      if (!legacy.closed) await api.closeAccount(id, source.accountId);
    }
    if (source.cashAccountId) {
      const cashAccount = (await api.getAccounts()).find(a => a.id === source.cashAccountId);
      if (!cashAccount?.offbudget || cashAccount.closed || !Number.isSafeInteger(snapshot.cash)) throw new Error('Invalid brokerage cash setup');
      await api.updateAccount(source.cashAccountId, { name: source.cashAccountName });
      await setValuation(api, { accountId: source.cashAccountId, key: source.key + '-cash-baseline', total: snapshot.cash, date: snapshot.date,
        notes: 'Conciliação inicial do saldo de caixa informado pela corretora; carteira de ativos passa a conta separada. Preserva histórico importado; não representa perda de investimento.' });
    }
    configured.push({ ...snapshot, source });
  }
  await syncValuations(api, configured);
  for (const [id, balance] of protectedBalances) {
    if (await api.getAccountBalance(id) !== balance) throw new Error('Setup unexpectedly changed an on-budget account');
  }
  return configured;
}
