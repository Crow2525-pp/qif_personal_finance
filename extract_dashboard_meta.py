import json
import os
import sys

results = []
dashboards_dir = "grafana/provisioning/dashboards"

for filename in sorted(os.listdir(dashboards_dir)):
    if filename.endswith(".json"):
        filepath = os.path.join(dashboards_dir, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
                uid = data.get('uid', '')
                title = data.get('title', '')
                timepicker_hidden = str(data.get('timepicker', {}).get('hidden', False)).lower()
                time_from = data.get('time', {}).get('from', '')
                time_to = data.get('time', {}).get('to', '')
                
                results.append({
                    'filename': filename,
                    'uid': uid,
                    'title': title,
                    'timepicker_hidden': timepicker_hidden,
                    'time_from': time_from,
                    'time_to': time_to
                })
        except Exception as e:
            print(f"Error reading {filename}: {e}", file=sys.stderr)

# Print markdown table
print("| Filename | UID | Title | Timepicker Hidden | Time From | Time To |")
print("|----------|-----|-------|-------------------|-----------|---------|")
for row in results:
    print(f"| {row['filename']} | {row['uid']} | {row['title']} | {row['timepicker_hidden']} | {row['time_from']} | {row['time_to']} |")
