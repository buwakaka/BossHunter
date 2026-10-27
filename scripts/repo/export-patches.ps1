[CmdletBinding()]
param(
	[string]$OutDir = "patches",
	[string]$BaseBranch = "main"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

Push-Location $RepoRoot
try {
	$count = (git rev-list --count "$BaseBranch..HEAD").Trim()
	if ($count -eq "0") {
		Write-Host "当前分支相对 $BaseBranch 没有提交，无需导出。"
		return
	}

	New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
	Get-ChildItem $OutDir -Filter "*.patch" -ErrorAction SilentlyContinue | Remove-Item -Force

	git format-patch "$BaseBranch..HEAD" -o $OutDir
	if ($LASTEXITCODE -ne 0) {
		throw "git format-patch 失败（退出码 $LASTEXITCODE）"
	}

	Write-Host "已导出 $count 个补丁到 $OutDir\"
	Write-Host "应用方式：git am $OutDir\*.patch  或  git apply --3way $OutDir\*.patch"
}
finally {
	Pop-Location
}