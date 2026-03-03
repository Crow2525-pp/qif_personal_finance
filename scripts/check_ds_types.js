const fs = require('fs');
const dash = JSON.parse(fs.readFileSync('grafana/provisioning/dashboards/executive-dashboard.json', 'utf8'));
const types = new Set();
function scan(obj) {
  if (!obj || typeof obj !== 'object') return;
  if (obj.datasource && obj.datasource.type) types.add(obj.datasource.type);
  Object.values(obj).forEach(v => { if (typeof v === 'object') scan(v); });
}
scan(dash);
console.log([...types]);
