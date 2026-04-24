const fs = require('fs');
const path = require('path');
const dashDir = 'platform/grafana/provisioning/dashboards';

const files = [
  '01-executive-overview-mobile.json',
  'outflows-reconciliation-dashboard.json',
];

const search = "GROUP BY domain AND period_date <= date_trunc('month', NOW())";
const replace = 'GROUP BY domain';

for (const file of files) {
  const fp = path.join(dashDir, file);
  const orig = fs.readFileSync(fp, 'utf8');
  if (orig.includes(search)) {
    const count = orig.split(search).length - 1;
    const text = orig.split(search).join(replace);
    fs.writeFileSync(fp, text);
    console.log('FIXED ' + file + ' (' + count + 'x): removed AND from GROUP BY');
  } else {
    console.log('NOT FOUND in ' + file);
  }
}
