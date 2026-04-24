const fs = require('fs');
const fp = 'platform/grafana/provisioning/dashboards/outflows-insights-dashboard.json';

let d;
try {
  d = JSON.parse(fs.readFileSync(fp, 'utf8'));
  console.log('Valid JSON: OK');
} catch(e) {
  console.log('INVALID JSON:', e.message);
  process.exit(1);
}

let fixes = { uncategorized: 0, transformation: 0 };
function fix(panels) {
  for (const p of panels) {
    if (p.panels) fix(p.panels);
    for (const t of (p.targets || [])) {
      if (!t.rawSql) continue;
      const b = t.rawSql;
      // Fix: uncategorized column references -> uncategorized_amount
      t.rawSql = t.rawSql
        .replace(/ uncategorized as amount\b/g, ' uncategorized_amount as amount')
        .replace(/\buncategorized as "Uncategorized"/g, 'uncategorized_amount as "Uncategorized"')
        .replace(/\buncategorized as "Uncategorized Amount"/g, 'uncategorized_amount as "Uncategorized Amount"');
      if (t.rawSql !== b) fixes.uncategorized++;
      const b2 = t.rawSql;
      // Fix: transformation.fct_transactions -> reporting.fct_transactions
      t.rawSql = t.rawSql.replace(/transformation\.fct_transactions/g, 'reporting.fct_transactions');
      if (t.rawSql !== b2) fixes.transformation++;
    }
  }
}
fix(d.panels || []);
console.log('Fixes applied:', fixes);
fs.writeFileSync(fp, JSON.stringify(d, null, 2));
console.log('Done - file written');
