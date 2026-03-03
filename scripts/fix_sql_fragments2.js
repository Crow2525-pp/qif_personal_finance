/**
 * Fix remaining SQL fragment issues introduced by task-110 migration.
 * These are AND fragments appended to FROM clauses (missing WHERE keyword).
 */
const fs = require('fs');

function applyFix(file, search, replace, description) {
  let text = fs.readFileSync(file, 'utf8');
  if (text.includes(search)) {
    const count = text.split(search).length - 1;
    text = text.split(search).join(replace);
    fs.writeFileSync(file, text);
    console.log('FIXED ' + file + ' (' + count + 'x): ' + description);
  } else {
    console.log('NOT FOUND in ' + file + ': ' + description);
  }
}

const BSLASH_N = '\x5Cn'; // literal backslash+n as in JSON file

// Fix 1: 05-savings-performance-mobile.json
// CTE has "FROM reporting.rpt_savings_analysis\n    AND budget_year_month"
// Should be: "FROM reporting.rpt_savings_analysis\n    WHERE budget_year_month"
applyFix(
  'grafana/provisioning/dashboards/05-savings-performance-mobile.json',
  'reporting.rpt_savings_analysis' + BSLASH_N + '    AND budget_year_month <= TO_CHAR',
  'reporting.rpt_savings_analysis' + BSLASH_N + '    WHERE budget_year_month <= TO_CHAR',
  'AND -> WHERE in CTE (Current Month Savings Breakdown)'
);

// Fix 2: amazon-spending-dashboard.json
// "FROM monthly\nAND date BETWEEN..." should just be "FROM monthly\nORDER BY month_date"
applyFix(
  'grafana/provisioning/dashboards/amazon-spending-dashboard.json',
  BSLASH_N + "AND date BETWEEN date_trunc('month', (NOW() - INTERVAL '12 months')) AND date_trunc('month', NOW())" + BSLASH_N + 'ORDER BY month_date',
  BSLASH_N + 'ORDER BY month_date',
  'Remove AND date BETWEEN after FROM monthly'
);

// Fix 3: cash-flow-analysis-dashboard.json
// "FROM windowed\nAND transaction_date BETWEEN..." should just be "FROM windowed\nORDER BY period_date;"
applyFix(
  'grafana/provisioning/dashboards/cash-flow-analysis-dashboard.json',
  BSLASH_N + "AND transaction_date BETWEEN (NOW() - INTERVAL '12 months') AND NOW()" + BSLASH_N + 'ORDER BY period_date;',
  BSLASH_N + 'ORDER BY period_date;',
  'Remove AND transaction_date BETWEEN after FROM windowed'
);

console.log('\nDone.');
