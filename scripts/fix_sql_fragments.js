/**
 * Fix broken SQL fragments in dashboard JSON files introduced by task-110 migration.
 * These fragments were appended after statement-terminating semicolons or in wrong
 * SQL clause positions, making queries invalid.
 */
const fs = require('fs');
const path = require('path');
const dashDir = path.join(__dirname, '..', 'grafana', 'provisioning', 'dashboards');

const files = fs.readdirSync(dashDir).filter(f => f.endsWith('.json'));
let totalFixes = 0;

// In the raw JSON files, \n is stored as the 2-byte sequence: backslash (0x5C) + n (0x6E).
// Regex /;[\x5C]n/ matches: semicolon + literal-backslash + n.
const BSLASH_N = '\x5Cn'; // literal backslash + n as they appear in JSON file

const patterns = [
  // After semicolon: statement already terminated, dangling AND
  ';' + BSLASH_N + "AND budget_year_month <= TO_CHAR(date_trunc('month', NOW()), 'YYYY-MM')",
  ';' + BSLASH_N + 'AND dashboard_month <= date_trunc(\'month\', NOW())',
  ';' + BSLASH_N + 'AND year_month <= date_trunc(\'month\', NOW())',
  ';' + BSLASH_N + 'AND comparison_year <= EXTRACT(YEAR FROM NOW())::int',
  // Without semicolon: in HAVING or FROM clause - budget_year_month not in GROUP BY
  BSLASH_N + "AND budget_year_month <= TO_CHAR(date_trunc('month', NOW()), 'YYYY-MM')",
];

for (const file of files) {
  const fp = path.join(dashDir, file);
  const orig = fs.readFileSync(fp, 'utf8');
  let text = orig;

  for (const pat of patterns) {
    while (text.includes(pat)) {
      text = text.replace(pat, '');
      console.log(file + ': removed fragment: ' + JSON.stringify(pat).substring(0, 80));
      totalFixes++;
    }
  }

  if (text !== orig) {
    fs.writeFileSync(fp, text);
    console.log('  -> wrote ' + file);
  }
}
console.log('\nTotal fixes:', totalFixes);
