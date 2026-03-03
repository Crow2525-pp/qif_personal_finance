/**
 * Push specific dashboard JSON files to Grafana API.
 * Usage: node scripts/push_dashboards.js [file1.json file2.json ...]
 * If no args, pushes all dashboards in the dashboards dir.
 */
const fs = require('fs');
const path = require('path');
const http = require('http');

const GRAFANA_URL = 'http://localhost:3001';
const GRAFANA_AUTH = 'admin:CHANGE_ME_GRAFANA_ADMIN_PASSWORD';
const DASH_DIR = path.join(__dirname, '..', 'grafana', 'provisioning', 'dashboards');

function postJSON(urlPath, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const auth = Buffer.from(GRAFANA_AUTH).toString('base64');
    const options = {
      hostname: 'localhost',
      port: 3001,
      path: urlPath,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ' + auth,
        'Content-Length': Buffer.byteLength(data),
      },
    };
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(body) }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  const args = process.argv.slice(2);
  const files = args.length > 0
    ? args.map(f => path.isAbsolute(f) ? f : path.join(DASH_DIR, f))
    : fs.readdirSync(DASH_DIR).filter(f => f.endsWith('.json')).map(f => path.join(DASH_DIR, f));

  let ok = 0, fail = 0;
  for (const fp of files) {
    const dashboard = JSON.parse(fs.readFileSync(fp, 'utf8'));
    const title = dashboard.title || path.basename(fp);
    delete dashboard.id;
    const result = await postJSON('/api/dashboards/db', { dashboard, overwrite: true, folderId: 0 });
    if (result.status === 200) {
      console.log('OK: ' + title);
      ok++;
    } else {
      console.log('FAIL (' + result.status + '): ' + title + ' - ' + (result.body.message || JSON.stringify(result.body)));
      fail++;
    }
  }
  console.log('\nTotal: ' + ok + ' ok, ' + fail + ' failed');
}

main().catch(e => { console.error(e); process.exit(1); });
