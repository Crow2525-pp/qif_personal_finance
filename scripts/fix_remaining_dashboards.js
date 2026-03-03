const fs = require('fs');
const path = require('path');
const DASH_DIR = 'grafana/provisioning/dashboards';

function readDash(name) {
  return JSON.parse(fs.readFileSync(path.join(DASH_DIR, name), 'utf8'));
}
function writeDash(name, d) {
  fs.writeFileSync(path.join(DASH_DIR, name), JSON.stringify(d, null, 2));
}
function walkPanels(panels, fn) {
  for (const p of panels) {
    if (p.panels) walkPanels(p.panels, fn);
    fn(p);
  }
}

// ── Fix 1: cash-flow-analysis-dashboard.json ──────────────────────────────────
// Remove dangling "AND transaction_date BETWEEN..." fragment appended after JOIN ON
{
  const d = readDash('cash-flow-analysis-dashboard.json');
  let changes = 0;
  walkPanels(d.panels || [], (p) => {
    for (const t of (p.targets || [])) {
      if (!t.rawSql) continue;
      const before = t.rawSql;
      // Remove: "\nAND transaction_date BETWEEN (NOW() - INTERVAL '12 months') AND NOW()\n"
      // that was appended after the LEFT JOIN line
      t.rawSql = t.rawSql.replace(
        /\nAND transaction_date BETWEEN \(NOW\(\) - INTERVAL '12 months'\) AND NOW\(\)\n/g,
        '\n'
      );
      if (t.rawSql !== before) changes++;
    }
  });
  writeDash('cash-flow-analysis-dashboard.json', d);
  console.log('cash-flow-analysis-dashboard.json: ' + changes + ' fixes');
}

// ── Fix 2: 01-executive-overview-mobile.json ──────────────────────────────────
// Health Scores: dashboard_month (TEXT) <= date_trunc(...) → use TO_CHAR comparison
{
  const d = readDash('01-executive-overview-mobile.json');
  let changes = 0;
  walkPanels(d.panels || [], (p) => {
    for (const t of (p.targets || [])) {
      if (!t.rawSql) continue;
      const before = t.rawSql;
      // Fix: "dashboard_month <= date_trunc('month', NOW())" -> "dashboard_month <= TO_CHAR(date_trunc('month', NOW()), 'YYYY-MM')"
      t.rawSql = t.rawSql.replace(
        /dashboard_month <= date_trunc\('month', NOW\(\)\)/g,
        "dashboard_month <= TO_CHAR(date_trunc('month', NOW()), 'YYYY-MM')"
      );
      if (t.rawSql !== before) changes++;
    }
  });
  writeDash('01-executive-overview-mobile.json', d);
  console.log('01-executive-overview-mobile.json: ' + changes + ' fixes');
}

// ── Fix 3: transaction-analysis-dashboard.json ────────────────────────────────
// viz.viz_transaction_anomalies -> reporting.viz_transaction_anomalies
// viz.viz_transactions_needs_review_queue -> reporting.viz_transactions_needs_review_queue
{
  const d = readDash('transaction-analysis-dashboard.json');
  let changes = 0;
  walkPanels(d.panels || [], (p) => {
    for (const t of (p.targets || [])) {
      if (!t.rawSql) continue;
      const before = t.rawSql;
      t.rawSql = t.rawSql
        .replace(/\bviz\.viz_transaction_anomalies\b/g, 'reporting.viz_transaction_anomalies')
        .replace(/\bviz\.viz_transactions_needs_review_queue\b/g, 'reporting.viz_transactions_needs_review_queue');
      if (t.rawSql !== before) changes++;
    }
  });
  writeDash('transaction-analysis-dashboard.json', d);
  console.log('transaction-analysis-dashboard.json: ' + changes + ' fixes');
}

// ── Fix 4: outflows-insights-dashboard.json ───────────────────────────────────
// Top 5 Transactions panels: fix column names (merchant_name/amount/category_l1
// don't exist in reporting.fct_transactions; use transaction_memo/transaction_amount_abs
// + JOIN dim_categories for level_1_category)
{
  const d = readDash('outflows-insights-dashboard.json');
  let changes = 0;
  walkPanels(d.panels || [], (p) => {
    if (!p.title) return;
    for (const t of (p.targets || [])) {
      if (!t.rawSql) continue;
      const before = t.rawSql;
      if (p.title === 'Top 5 Transactions - Highest Variance Category' ||
          p.title === 'Top 5 Transactions - Highest Variance Category (YoY)') {
        // Fix column references: merchant_name -> transaction_memo,
        // f.amount -> f.transaction_amount_abs, f.category_l1 -> dc.level_1_category
        // Also add JOIN to dim_categories
        t.rawSql = t.rawSql
          .replace(/f\.merchant_name as merchant/g, 'f.transaction_memo as merchant')
          .replace(/ABS\(f\.amount\) as amount/g, 'f.transaction_amount_abs as amount')
          .replace(/f\.category_l1 as category/g, 'dc.level_1_category as category')
          .replace(/FROM reporting\.fct_transactions f(\s+WHERE)/g,
            'FROM reporting.fct_transactions f\n  LEFT JOIN reporting.dim_categories dc ON dc.category_key = f.category_key$1')
          .replace(/WHERE f\.category_l1/g, 'WHERE dc.level_1_category')
          .replace(/ORDER BY ABS\(f\.amount\) DESC/g, 'ORDER BY f.transaction_amount_abs DESC');
        if (t.rawSql !== before) changes++;
      }
    }
  });
  writeDash('outflows-insights-dashboard.json', d);
  console.log('outflows-insights-dashboard.json (top5 column fixes): ' + changes + ' fixes');
}

console.log('All done.');
