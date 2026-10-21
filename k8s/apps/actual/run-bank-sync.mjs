import { mkdtempSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { fetchSnapshots, syncValuations } from './investment-sync.mjs';

const require = createRequire(import.meta.url);
const serverURL = process.env.ACTUAL_SERVER_URL;
const sessionToken = process.env.ACTUAL_SESSION_TOKEN;
const budgetIdEnv = process.env.ACTUAL_BUDGET_SYNC_ID;
if (!serverURL || !sessionToken || !budgetIdEnv) { console.error('missing env'); process.exit(1); }
const dryRun = process.env.ACTUAL_SYNC_DRY_RUN === 'true';
// Keep this aligned with the Actual deployment; older clients cannot open newer migrations.
const apiVersion = '26.10.0';

const work = mkdtempSync(join(tmpdir(), 'aas-'));
mkdirSync(work, { recursive: true });
console.log('npm_install_start', new Date().toISOString());
execSync(`npm install --omit=dev --no-fund --no-audit @actual-app/api@${apiVersion}`, {
  cwd: work, stdio: 'inherit',
  env: { ...process.env, npm_config_cache: join(work, '.npm'), NODE_OPTIONS: '' },
});
console.log('npm_install_ok', new Date().toISOString());

const api = require(join(work, 'node_modules/@actual-app/api'));
const dataDir = join(work, 'data');
mkdirSync(dataDir, { recursive: true });

await api.init({ dataDir, serverURL, sessionToken });
console.log('init_ok', new Date().toISOString());

// Never fall back to another budget when the configured file cannot be opened.
// downloadBudget can resolve after a migration error, so getAccounts is the load check.
try {
  await api.downloadBudget(budgetIdEnv);
  const accounts = await api.getAccounts();
  console.log('budget_open_ok', 'accounts=' + accounts.length, 'api=' + apiVersion);
} catch (e) {
  console.error('budget_open_error', e?.message || String(e));
  await api.shutdown();
  process.exit(2);
}

if (dryRun) {
  console.log('dry_run_ok', 'budget opened; bank sync skipped');
  await api.shutdown();
  process.exit(0);
}

console.log('bank_sync_start', new Date().toISOString());
try {
  await api.runBankSync();
  console.log('bank_sync_ok', new Date().toISOString());
} catch (e) {
  console.log('bank_sync_error', e?.message || String(e), 'code', e?.code || null);
  process.exitCode = 3;
}
if (process.env.ACTUAL_INVESTMENTS_ENABLED === 'true') {
  try {
    const snapshots = await fetchSnapshots({
      clientId: process.env.PLUGGY_CLIENT_ID,
      clientSecret: process.env.PLUGGY_CLIENT_SECRET,
      sources: JSON.parse(process.env.ACTUAL_INVESTMENT_SOURCES || 'null'),
    });
    const results = await syncValuations(api, snapshots);
    console.log('investment_sync_ok', 'sources=' + results.length, 'changed=' + results.filter(r => r.changed).length);
  } catch (e) {
    console.error('investment_sync_error', e?.message || String(e));
    process.exitCode = 5;
  }
}
try {
  await api.sync();
  console.log('crdt_sync_ok', new Date().toISOString());
} catch (e) {
  console.log('crdt_sync_error', e?.message || String(e));
  process.exitCode = 4;
}
await api.shutdown();
console.log('done', new Date().toISOString());
