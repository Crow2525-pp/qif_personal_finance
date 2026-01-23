@plan.md @activity.md

First read activity.md to see what was recently accomplished.

Start the site locally with python3 -m http.server. If port is taken, try another port.

Environment checks:
- Determine whether you are on local dev or production. If the OS is Windows, treat it as local dev.
- The source of truth for production is http://192.168.1.103. Use that for any production comparisons or validations.

Open plan.md and choose the single highest priority task where passes is false.

Work on exactly ONE task: implement the change.

After implementing, use Playwright to:
1. Navigate to the local server URL
2. Take a screenshot and save it as screenshots/[task-name].png

Append a dated progress entry to activity.md describing what you changed and the screenshot filename.

Update that task's passes in plan.md from false to true.

Create a new git branch for your work, make one commit for that task only with a clear message, and push the branch to the remote.

Do not git init, do not change remotes.

ONLY WORK ON A SINGLE TASK.

When ALL tasks have passes true, output <promise>COMPLETE</promise>
