Describe 'Onboarding tests' {
BeforeAll {
	$script:OnboardingScriptPath = Join-Path $PSScriptRoot '..\src\Onboarding.ps1'

	function Set-TestCsv {
		param([string[]]$Rows)

		$Rows | Set-Content -LiteralPath $script:CsvPath -Encoding utf8
	}

	function Invoke-OnboardingForTest {
		param([switch]$WhatIf)

		& $script:OnboardingScriptPath `
			-CsvPath $script:CsvPath `
			-DirectoryPath $script:DirectoryPath `
			-LogDir $script:LogDir `
			-WhatIf:$WhatIf 6>$null
	}
}

BeforeEach {
	$script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OnboardingPester_{0}" -f [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $script:TestRoot | Out-Null
	$script:CsvPath = Join-Path $script:TestRoot 'new-hires.csv'
	$script:DirectoryPath = Join-Path $script:TestRoot 'directory.json'
	$script:LogDir = Join-Path $script:TestRoot 'logs'
}

AfterEach {
	if (Test-Path -LiteralPath $script:TestRoot) {
		Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
	}
}

	Context 'Onboarding script' {
	It 'creates a user with an email and department groups' {
		Set-TestCsv @(
			'FirstName,LastName,Department,Title,StartDate',
			'Maria,Lopez,Finance,Accountant,2026-11-16'
		)
		'[]' | Set-Content -LiteralPath $script:DirectoryPath

		Invoke-OnboardingForTest

		$users = @(Get-Content -LiteralPath $script:DirectoryPath -Raw | ConvertFrom-Json)
		$users.Count | Should -Be 1
		$users[0].Username | Should -Be 'mlopez'
		$users[0].Email | Should -Be 'mlopez@example.gov'
		@($users[0].Groups) | Should -Contain 'GRP-Finance'
		@($users[0].Groups) | Should -Contain 'GRP-AllStaff'
	}

	It 'adds numeric suffixes for existing and same-run username collisions' {
		Set-TestCsv @(
			'FirstName,LastName,Department,Title,StartDate',
			'Maria,Lopez,Finance,Accountant,2026-11-16',
			'Maria,Lopez,Finance,Accountant,2026-11-16'
		)
		ConvertTo-Json -InputObject @([PSCustomObject]@{ Username = 'mlopez' }) |
			Set-Content -LiteralPath $script:DirectoryPath

		Invoke-OnboardingForTest

		$users = @(Get-Content -LiteralPath $script:DirectoryPath -Raw | ConvertFrom-Json)
		@($users.Username) | Should -Contain 'mlopez2'
		@($users.Username) | Should -Contain 'mlopez3'
	}

	It 'logs invalid rows and continues processing valid rows' {
		Set-TestCsv @(
			'FirstName,LastName,Department,Title,StartDate',
			'Maria,Lopez,Finance,Accountant,2026-11-16',
			',Smith,Parks,Laborer,2026-11-16',
			'Anna,Berg,Unknown,Clerk,2026-11-16',
			'Bad,Date,IT,Tester,not-a-date'
		)
		'[]' | Set-Content -LiteralPath $script:DirectoryPath

		Invoke-OnboardingForTest

		$users = @(Get-Content -LiteralPath $script:DirectoryPath -Raw | ConvertFrom-Json)
		$users.Count | Should -Be 1
		$logPath = (Get-ChildItem -LiteralPath $script:LogDir -Filter 'onboarding_*.log').FullName
		$log = Get-Content -LiteralPath $logPath -Raw
		$log | Should -Match 'FirstName is required'
		$log | Should -Match "Department 'Unknown' is not recognized"
		$log | Should -Match 'StartDate must be a valid date'
	}

	It 'does not change files or create logs when WhatIf is used' {
		Set-TestCsv @(
			'FirstName,LastName,Department,Title,StartDate',
			'Maria,Lopez,Finance,Accountant,2026-11-16'
		)
		'[]' | Set-Content -LiteralPath $script:DirectoryPath

		Invoke-OnboardingForTest -WhatIf

		(Get-Content -LiteralPath $script:DirectoryPath -Raw).Trim() | Should -Be '[]'
		Test-Path -LiteralPath $script:LogDir | Should -BeFalse
	}
}
}
