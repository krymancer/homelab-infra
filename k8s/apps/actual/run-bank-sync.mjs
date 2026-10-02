import { mkdtempSync, mkdirSync, existsSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { createRequire } from 'module';
import { execSync } from 'child_process';

const require = createRequire(import.meta.url);
const serverURL = process.env.ACTUAL_SERVER_URL;
const sessionToken = process.env.ACTUAL_SESSION_TOKEN;
const budgetIdEnv = process.env.ACTUAL_BUDGET_SYNC_ID;
if (!serverURL || !sessionToken) { console.error('missing env'); process.exit(1); }
console.log('serverURL', serverURL, 'token_len', sessionToken.length, 'budget_env', budgetIdEnv || null);

const work = mkdtempSync(join(tmpdir(), 'aas-'));
mkdirSync(work, { recursive: true });
console.log('npm_install_start', new Date().toISOString());
execSync('npm install --omit=dev --no-fund --no-audit @actual-app/api@26.9.0', {
  cwd: work, stdio: 'inherit',
  env: { ...process.env, npm_config_cache: join(work, '.npm'), NODE_OPTIONS: '' },
});
console.log('npm_install_ok', new Date().toISOString());

const api = require(join(work, 'node_modules/@actual-app/api'));
const dataDir = join(work, 'data');
mkdirSync(dataDir, { recursive: true });

await api.init({ dataDir, serverURL, sessionToken });
console.log('init_ok', new Date().toISOString());

const budgets = await api.getBudgets();
console.log('budgets_summary', JSON.stringify((budgets||[]).map(b => ({
  name: b.name, id: b.id, cloudFileId: b.cloudFileId, groupId: b.groupId, state: b.state,
}))));

const candidates = [];
if (budgetIdEnv) candidates.push(budgetIdEnv);
for (const b of budgets || []) {
  for (const k of ['groupId', 'cloudFileId', 'id']) {
    if (b?.[k] && !candidates.includes(b[k])) candidates.push(b[k]);
  }
}

let opened = null;
for (const id of candidates) {
  try {
    console.log('try_download', id);
    await api.downloadBudget(id);
    opened = id;
    console.log('download_ok', id);
    break;
  } catch (e) {
    console.log('download_fail', id, e?.message || String(e));
  }
}
if (!opened) { await api.shutdown(); process.exit(2); }

const accounts = await api.getAccounts();
console.log('accounts_count', (accounts||[]).length);
for (const a of accounts || []) {
  console.log('account', a.name, 'closed='+a.closed, 'sync='+(a.account_sync_source || a.accountSyncSource || 'none'));
}

console.log('bank_sync_start', new Date().toISOString());
try {
  await api.runBankSync();
  console.log('bank_sync_ok', new Date().toISOString());
} catch (e) {
  console.log('bank_sync_error', e?.message || String(e), 'code', e?.code || null);
  process.exitCode = 3;
}
try {
  await api.sync();
  console.log('crdt_sync_ok', new Date().toISOString());
} catch (e) {
  console.log('crdt_sync_error', e?.message || String(e));
}
await api.shutdown();
console.log('done', new Date().toISOString());
