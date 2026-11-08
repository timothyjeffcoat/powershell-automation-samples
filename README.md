# HR Onboarding Automation

A PowerShell script that reads new-hire rows from `data/new-hires.csv`, validates each row, generates unique usernames and `@example.gov` email addresses, maps departments to security groups, and adds valid users to `data/directory.json`. Invalid rows are logged and skipped so processing can continue. Each run prints a created, skipped, and failed summary and writes a timestamped log.

## Run

From the project directory, preview changes without writing to the directory or creating a log:

```powershell
.\src\Onboarding.ps1 -WhatIf
```

Run the onboarding process:

```powershell
.\src\Onboarding.ps1
```

## Tests

Run the Pester tests from the project directory:

```powershell
Invoke-Pester -Path .\tests -CI
```

GitHub Actions runs the same tests on pushes and pull requests to `main`.