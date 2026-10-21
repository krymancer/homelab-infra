import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { fetchSnapshots, setupInvestmentAccounts, syncValuations } from './investment-sync.mjs';
const require = createRequire(import.meta.url);
const mode = process.argv[2] || 'validate';
const work = process.argv[3] || mkdtempSync(join(tmpdir(), 'actual-investment-'));
if (mode !== 'offline') {
  execFileSync('npm', ['install', '--omit=dev', '--no-fund', '--no-audit', '@actual-app/api@26.10.0'], { cwd: work, stdio: 'inherit' });
}
const api = require(join(work, 'node_modules/@actual-app/api'));
let initialized = false;
try {
  let snapshots;
  if (mode === 'offline') {
    snapshots = JSON.parse(readFileSync(join(work, 'snapshots.json'), 'utf8'));
    const offlineDir = join(work, 'offline'); mkdirSync(offlineDir);
    await api.init({ dataDir: offlineDir }); initialized = true;
    await api.importBudget(new Uint8Array(readFileSync(join(work, 'budget.zip'))));
    await api.getAccounts();
    console.log('OFFLINE_COPY_OPENED');
  } else {
    snapshots = await fetchSnapshots({ clientId: process.env.PLUGGY_CLIENT_ID, clientSecret: process.env.PLUGGY_CLIENT_SECRET, sources: JSON.parse(process.env.ACTUAL_INVESTMENT_SOURCES) });
    const dataDir = join(work, 'download'); mkdirSync(dataDir);
    await api.init({ dataDir, serverURL: process.env.ACTUAL_SERVER_URL, sessionToken: process.env.ACTUAL_SESSION_TOKEN }); initialized = true;
    await api.downloadBudget(process.env.ACTUAL_BUDGET_SYNC_ID);
    await api.getAccounts();
    if (mode === 'validate') {
      writeFileSync(join(work, 'budget.zip'), await api.exportBudget(), { mode: 0o600 });
      writeFileSync(join(work, 'snapshots.json'), JSON.stringify(snapshots), { mode: 0o600 });
      await api.shutdown(); initialized = false;
      // New process: no server URL, session, or provider credentials in its environment.
      execFileSync(process.execPath, [fileURLToPath(import.meta.url), 'offline', work], { stdio: 'inherit', env: { PATH: process.env.PATH, HOME: work, NODE_ENV: 'production' } });
      console.log('VALIDATION_PASSED_WITHOUT_PRODUCTION_WRITES');
      process.exit(0);
    }
    assert.equal(mode, 'apply');
  }
  const before = await api.getAccounts();
  const protectedBalances = new Map();
  for (const a of before.filter(a => !a.offbudget)) protectedBalances.set(a.id, await api.getAccountBalance(a.id));
  const configured = await setupInvestmentAccounts(api, snapshots);
  for (const s of configured) {
    assert.equal(await api.getAccountBalance(s.source.accountId), s.total);
    for (const id of s.source.legacyAccountIds || []) {
      assert.equal(await api.getAccountBalance(id), 0);
      assert.equal((await api.getAccounts()).find(a => a.id === id).closed, true);
    }
    if (s.source.cashAccountId) assert.equal(await api.getAccountBalance(s.source.cashAccountId), s.cash);
  }
  const counts = new Map();
  for (const s of configured) counts.set(s.source.accountId, (await api.getTransactions(s.source.accountId, '1900-01-01', '9999-12-31')).length);
  const repeated = await syncValuations(api, configured);
  assert.equal(repeated.filter(r => r.changed).length, 0);
  // Setup itself must also be restart-safe after a partial run.
  const again = await setupInvestmentAccounts(api, configured);
  for (const s of again) {
    assert.equal(await api.getAccountBalance(s.source.accountId), s.total);
    assert.equal((await api.getTransactions(s.source.accountId, '1900-01-01', '9999-12-31')).length, counts.get(s.source.accountId));
  }
  for (const [id, balance] of protectedBalances) assert.equal(await api.getAccountBalance(id), balance);
  console.log('SETUP_AND_REPEAT_VERIFIED', JSON.stringify(configured.map(s => ({ key: s.source.key, total: s.total, cash: s.cash }))));
  if (mode === 'apply') {
    await api.sync();
    console.log('INVESTMENT_SETUP_PUBLISHED');
    console.log('SETUP_ACCOUNT_IDS', JSON.stringify(configured.map(s => ({ key: s.source.key, accountId: s.source.accountId }))));
  }
} catch (error) {
  console.error('SETUP_FAILED', error.message);
  process.exitCode = 1;
} finally {
  if (initialized) await api.shutdown();
}
