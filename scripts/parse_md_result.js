const d = JSON.parse(require('fs').readFileSync('C:/Users/p_pat/AppData/Local/Temp/run_result2.json','utf8'));
const mats = d.data.runOrError.assetMaterializations;
const qa = mats.find(m => m.assetKey.path[0] === 'dashboard_quality_gate');
if (!qa) { console.log('Not found'); process.exit(1); }
const detail = qa.metadataEntries.find(e => e.label === 'failing_panels_detail');
if (!detail) { console.log('No entry'); process.exit(1); }
console.log(JSON.stringify(detail));
if (detail.mdStr) {
  console.log('\n--- Markdown ---\n' + detail.mdStr);
}
