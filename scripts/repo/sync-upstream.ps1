[CmdletBinding()]
param(
	[switch]$PushFork,
	[switch]$RunTests
)

$ErrorActionPreference = "Stop"
$CustomBranch = "my-custom-patch"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Invoke-Git {
	param([string[]]$Arguments)
	& git @Arguments
	if ($LASTEXITCODE -ne 0) {
		throw ("git {0} 失败（退出码 {1}）" -f ($Arguments -join ' '), $LASTEXITCODE)
	}
}

Push-Location $RepoRoot
try {
	$dirty = git status --porcelain --untracked-files=no
	if ($dirty) {
		throw "工作区有未提交的改动：请先提交或 git stash，再重新运行。"
	}

	Write-Host "[1/5] 拉取官方更新：git fetch upstream --prune"
	Invoke-Git @("fetch", "upstream", "--prune")

	Write-Host "[2/5] 切换 main 并快进到 upstream/main"
	Invoke-Git @("switch", "main")
	Invoke-Git @("merge", "--ff-only", "upstream/main")

	if ($PushFork) {
		Write-Host "[3/5] 推送 main 到 origin"
		Invoke-Git @("push", "origin", "main")
	} else {
		Write-Host "[3/5] 跳过推送（需要时加 -PushFork）"
	}

	Write-Host "[4/5] 切回 $CustomBranch 并 rebase 到 main"
	Invoke-Git @("switch", $CustomBranch)
	Invoke-Git @("rebase", "main")

	if ($RunTests) {
		Write-Host "[5/5] 运行回归测试"
		python -m unittest tests.test_browser_runtime tests.test_browser_runtime_discovery tests.test_browser_diagnostics tests.test_web_preflight
		if ($LASTEXITCODE -ne 0) {
			Write-Warning "测试未全部通过，请检查后再推送。"
		}
	} else {
		Write-Host "[5/5] 跳过测试（需要时加 -RunTests）"
	}

	Write-Host ""
	Write-Host "完成：$(git log --oneline -1)"
	Write-Host "提示：rebase 改写过历史，推送补丁分支时用 git push --force-with-lease origin $CustomBranch"
}
catch {
	Write-Host ""
	Write-Host "同步中断：$($_.Exception.Message)" -ForegroundColor Yellow
	Write-Host "当前状态："
	git status --short
	Write-Host ""
	Write-Host "分支冲突：编辑冲突文件 -> git add <file> -> git rebase --continue"
	Write-Host "放弃本次 rebase：git rebase --abort"
	Write-Host "main 出现分叉（不该发生）：确认 main 上没有需要的提交后，git reset --hard upstream/main"
	throw
}
finally {
	Pop-Location
}