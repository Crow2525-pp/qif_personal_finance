param(
  [Parameter(Mandatory = $true)]
  [int]$Iterations
)

for ($i = 1; $i -le $Iterations; $i++) {
  Write-Host "Iteration $i"
  Write-Host "--------------------------------"

  $prompt = Get-Content -Raw -Path "PROMPT.md"
  try {
    $result = $prompt | & codex exec - 2>&1
  } catch {
    # Swallow errors to match `|| true` behavior
    $result = $_.Exception.Message
  }

  Write-Output $result

  if ($result -match '(?m)^<promise>COMPLETE</promise>$') {
    Write-Host "All tasks complete after $i iterations."
    exit 0
  }

  Write-Host ""
  Write-Host "--- End of iteration $i ---"
  Write-Host ""
}

Write-Host "Reached max iterations ($Iterations)"
exit 1
