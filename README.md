# HR Onboarding Automation

[![CI](https://github.com/timothyjeffcoat/powershell-automation-samples/actions/workflows/ci.yml/badge.svg)](https://github.com/timothyjeffcoat/powershell-automation-samples/actions/workflows/ci.yml)

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

## Quality Checks

Install the tools for local checks:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
```

Lint the scripts. Any analyzer finding causes the CI lint step to fail:

```powershell
$issues = Invoke-ScriptAnalyzer -Path ./src -Recurse
$issues | Format-Table
if ($issues) { exit 1 }
```

Run the Pester tests from the project directory:

```powershell
Invoke-Pester ./tests -CI
```

## Continuous Integration

The GitHub Actions workflow in `.github/workflows/ci.yml` runs on pushes and pull requests. On `windows-latest`, it installs PSScriptAnalyzer and Pester, lints the scripts, and runs the test suite. The workflow fails if lint findings are reported or any tests fail.