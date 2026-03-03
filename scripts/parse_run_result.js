const d = JSON.parse(require('fs').readFileSync('C:/Users/p_pat/AppData/Local/Temp/run_result.json','utf8'));
const mats = d.data.runOrError.assetMaterializations;
const qa = mats.find(m => m.assetKey.path[0] === 'dashboard_quality_gate');
if (!qa) { console.log('dashboard_quality_gate not found'); process.exit(1); }
const detail = qa.metadataEntries.find(e => e.label === 'failing_panels_detail');
if (!detail || !detail.jsonString) {
  console.log('No jsonString in detail:', JSON.stringify(qa.metadataEntries));
  process.exit(0);
}
const panels = JSON.parse(detail.jsonString);
const byError = {};
panels.forEach(p => {
  const key = p.error || p.status || 'empty';
  if (!byError[key]) byError[key] = [];
  byError[key].push((p.dashboard || '') + ' | ' + (p.panel || ''));
});
Object.entries(byError).forEach(([err, items]) => {
  console.log('\n=== ' + err.slice(0, 100) + ' ===');
  items.forEach(i => console.log('  ' + i));
});
console.log('\nTotal:', panels.length);
