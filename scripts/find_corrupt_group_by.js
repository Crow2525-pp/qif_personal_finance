const fs = require('fs');
const path = require('path');
const dashDir = 'platform/grafana/provisioning/dashboards';
const BSLASH_N = '\x5Cn';

const files = fs.readdirSync(dashDir).filter(f => f.endsWith('.json'));
for (const file of files) {
  const text = fs.readFileSync(path.join(dashDir, file), 'utf8');
  let idx = 0;
  while ((idx = text.indexOf('GROUP BY', idx)) >= 0) {
    const lineEnd = text.indexOf(BSLASH_N, idx);
    const groupByLine = lineEnd > idx ? text.substring(idx, lineEnd) : text.substring(idx, idx + 200);
    if (groupByLine.includes(' AND ')) {
      console.log(file + ': ' + JSON.stringify(groupByLine.substring(0, 150)));
    }
    idx++;
  }
}
