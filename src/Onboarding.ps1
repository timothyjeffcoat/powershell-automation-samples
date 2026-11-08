<#
.SYNOPSIS
    Creates user accounts from an HR new-hire csv.
.EXAMPLE
    ./src/Onboarding.ps1 -CsvPath ./data/new-hires.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CsvPath = (Join-Path $PSScriptRoot '..\data\new-hires.csv'),

    [string]$DirectoryPath = (Join-Path $PSScriptRoot '..\data\directory.json'),
    [string]$LogDir = (Join-Path $PSScriptRoot '..\logs')
)

$ErrorActionPreference = 'Stop'

$CsvPath = [System.IO.Path]::GetFullPath($CsvPath)
$DirectoryPath = [System.IO.Path]::GetFullPath($DirectoryPath)
$LogDir = [System.IO.Path]::GetFullPath($LogDir)

$DepartmentGroups = @{
    'Finance' = @('GRP-Finance', 'GRP-AllStaff')
    'IT' = @('GRP-IT', 'GRP-AllStaff')
    'Parks' = @('GRP-Parks', 'GRP-AllStaff')
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp [$Level] $Message"
    Write-Host $logMessage
    if ($script:WriteToLogFile) {
        Add-Content -LiteralPath $script:LogFilePath -Value $logMessage
    }
}

function Test-NewHireRow {
    param(
        [PSCustomObject]$Row
    )
    $errors = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Row) {
        $errors.Add('Row cannot be null.')
        return ,$errors.ToArray()
    }

    foreach ($field in @('FirstName', 'LastName', 'Department', 'StartDate')) {
        $property = $Row.PSObject.Properties[$field]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $errors.Add("$field is required.")
        }
    }

    $departmentProperty = $Row.PSObject.Properties['Department']
    if ($null -ne $departmentProperty -and -not [string]::IsNullOrWhiteSpace([string]$departmentProperty.Value)) {
        $department = ([string]$departmentProperty.Value).Trim()
        if (-not $DepartmentGroups.ContainsKey($department)) {
            $allowedDepartments = ($DepartmentGroups.Keys | Sort-Object) -join ', '
            $errors.Add("Department '$department' is not recognized. Allowed values: $allowedDepartments.")
        }
    }

    $startDateProperty = $Row.PSObject.Properties['StartDate']
    if ($null -ne $startDateProperty -and -not [string]::IsNullOrWhiteSpace([string]$startDateProperty.Value)) {
        $parsedDate = [datetime]::MinValue
        $dateIsValid = [datetime]::TryParse(
            ([string]$startDateProperty.Value).Trim(),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsedDate
        )
        if (-not $dateIsValid) {
            $errors.Add('StartDate must be a valid date.')
        }
    }

    return ,$errors.ToArray()
}

function New-Username {
    param(
        [string]$FirstName,
        [string]$LastName,
        [System.Collections.Generic.HashSet[string]]$ExistingUsernames
    )
    $baseUsername = ($FirstName.Trim().Substring(0, 1) + $LastName.Trim()).ToLowerInvariant()
    $username = $baseUsername
    $counter = 2

    while ($ExistingUsernames.Contains($username)) {
        $username = "$baseUsername$counter"
        $counter++
    }

    return $username
}

$script:LogFilePath = Join-Path $LogDir ("onboarding_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$script:WriteToLogFile = $PSCmdlet.ShouldProcess($script:LogFilePath, 'Create timestamped onboarding log')
if ($script:WriteToLogFile) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    New-Item -ItemType File -Path $script:LogFilePath -Force | Out-Null
}

$directoryUsers = @()
if (Test-Path -LiteralPath $DirectoryPath -PathType Leaf) {
    $directoryJson = Get-Content -LiteralPath $DirectoryPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($directoryJson)) {
        $parsedDirectory = ConvertFrom-Json -InputObject $directoryJson -AsHashtable
        if ($null -eq $parsedDirectory) {
            $directoryUsers = @()
        } elseif ($parsedDirectory -is [array]) {
            $directoryUsers = @($parsedDirectory)
        } elseif ($parsedDirectory -is [System.Collections.IDictionary]) {
            $directoryUsers = @($parsedDirectory)
        } else {
            throw 'The directory JSON must contain a user object or an array of user objects.'
        }
    }
}

$existingUsernames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($user in $directoryUsers) {
    if (-not [string]::IsNullOrWhiteSpace([string]$user.Username)) {
        [void]$existingUsernames.Add([string]$user.Username)
    }
}

$created = 0
$skipped = 0
$failed = 0
$wouldCreate = 0
$pendingUsers = [System.Collections.Generic.List[object]]::new()
$rows = @(Import-Csv -LiteralPath $CsvPath)

for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
    $row = $rows[$rowIndex]
    try {
        $validationErrors = Test-NewHireRow -Row $row
        if ($validationErrors.Count -gt 0) {
            $skipped++
            Write-Log -Level 'WARN' -Message "Row $($rowIndex + 1) skipped: $($validationErrors -join ' ')"
            continue
        }

        $username = New-Username -FirstName $row.FirstName -LastName $row.LastName -ExistingUsernames $existingUsernames
        $newUser = [PSCustomObject]@{
            FirstName  = $row.FirstName.Trim()
            LastName   = $row.LastName.Trim()
            Username   = $username
            Email      = "$username@example.gov"
            Department = $row.Department.Trim()
            Title      = $row.Title
            StartDate  = $row.StartDate.Trim()
            Groups     = [string[]]$DepartmentGroups[$row.Department.Trim()]
        }
        $pendingUsers.Add($newUser)
        [void]$existingUsernames.Add($username)
        Write-Log -Message "Prepared user '$username' for $($row.FirstName) $($row.LastName)."
    } catch {
        $failed++
        Write-Log -Level 'ERROR' -Message "Row $($rowIndex + 1) failed: $($_.Exception.Message)"
    }
}

if ($pendingUsers.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($DirectoryPath, "Add $($pendingUsers.Count) user(s) to directory")) {
        $temporaryPath = "$DirectoryPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $directoryParent = Split-Path -Parent $DirectoryPath
            if (-not (Test-Path -LiteralPath $directoryParent -PathType Container)) {
                New-Item -ItemType Directory -Path $directoryParent -Force | Out-Null
            }
            $updatedDirectory = @($directoryUsers) + $pendingUsers.ToArray()
            $updatedJson = ConvertTo-Json -InputObject $updatedDirectory -Depth 10
            Set-Content -LiteralPath $temporaryPath -Value $updatedJson -Encoding utf8
            Move-Item -LiteralPath $temporaryPath -Destination $DirectoryPath -Force
            $created = $pendingUsers.Count
            Write-Log -Message "Added $created user(s) to '$DirectoryPath'."
        } catch {
            $failed += $pendingUsers.Count
            Write-Log -Level 'ERROR' -Message "Could not update directory '$DirectoryPath': $($_.Exception.Message)"
        } finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    } elseif ($WhatIfPreference) {
        $wouldCreate = $pendingUsers.Count
    } else {
        $skipped += $pendingUsers.Count
        Write-Log -Level 'WARN' -Message 'Directory update was declined; prepared users were skipped.'
    }
}

Write-Host ''
Write-Host 'Onboarding summary'
Write-Host "Created: $created"
if ($WhatIfPreference) {
    Write-Host "Would create: $wouldCreate"
}
Write-Host "Skipped: $skipped"
Write-Host "Failed: $failed"
if ($script:WriteToLogFile) {
    Write-Host "Log: $script:LogFilePath"
} else {
    Write-Host 'Log: not written (WhatIf or declined)'
}