# 本地补丁维护：Fork & Upstream 工作流

> 适用场景：你想继续用官方 BossHunter 的新版本，同时又想保留自己在本机做的修复/定制。
> 本文记录 2026-10-27 实际执行过的配置、当前分支布局、日常开发规则、升级步骤和排障经验。
> 目标读者：在本机维护这套代码的人（你自己）。

---

## 0. 当前状态速查

| 项目 | 值 |
| --- | --- |
| 代码目录 | `C:\Users\71617\BossHunter`（`pip install -e`，实际运行 `src/`） |
| 官方仓库（upstream） | `https://github.com/shengjidaguai-china/BossHunter.git` |
| 你的 fork（origin） | `https://github.com/buwakaka/BossHunter.git`（**截至 2026-10-27 尚未创建**，见 §2） |
| 纯净主分支 | `main`，跟踪 `upstream/main`，当前 `1f4e72d`（与官方一致，无本地改动） |
| 本地补丁分支 | `my-custom-patch`，当前 3 个提交（2 个修复 + 1 个文档/脚本） |
| 本地补丁 | 见 §8 |

> 关于仓库地址：代码里的 `GITHUB_URL` 仍写着 `powerycy/BossHunter`，该地址会被 GitHub
> 重定向到 `shengjidaguai-china/BossHunter`（同一个仓库，id `1248358923`）。
> 统一使用新地址，避免以后地址再次变化时混淆。
>
> 关于 `origin`：用户名来自本机 git 配置
> `55291321+buwakaka@users.noreply.github.com`，即 GitHub 账号 `buwakaka`。
> 如果这不是你的账号，用 `git remote set-url origin <你的 fork 地址>` 改掉即可。

---

## 1. 设计原则

1. **`main` 永远保持纯净**：只用来接收官方更新，绝不在上面提交本地改动。
2. **所有改动都在 `my-custom-patch` 上**，按功能拆成小提交（一个提交只做一件事）。
3. **只从 `upstream/main` 取稳定版**，不拉取他人的 PR 分支或开发分支。
4. **补丁必须可回归**：每个修复尽量带测试，升级后能用测试快速验证。
5. **补丁集保持最小**：官方修了同类问题就删掉自己的补丁（rebase 时 drop）。

这样做的好处：升级时 `main` 永远可以直接快进；冲突只会发生在你自己那几个提交里，
而且因为提交粒度小、提交信息写了根因，冲突很容易判断。

---

## 2. 一次性：在 GitHub 创建 fork 并接通 origin

本机 `gh` 未登录（`gh auth status` 提示未认证），所以这一步需要你手动完成：

1. 打开 <https://github.com/shengjidaguai-china/BossHunter>，点 **Fork**，
   创建到你的账号下（默认名字 `BossHunter`）。
2. 验证 fork 已存在：
   ```powershell
   git ls-remote --heads origin
   ```
   - 能列出分支 = fork 已就绪；
   - `Repository not found` = 还没 fork，或用户名不对。
3. 首次推送（把纯净 main 和补丁分支都传上去）：
   ```powershell
   git push -u origin main
   git push -u origin my-custom-patch
   ```

> 如果想用命令行创建 fork：先 `gh auth login`，再
> `gh repo fork shengjidaguai-china/BossHunter --remote=false`（`--remote=false`
> 表示不要再改本地远程配置，远程已经配好了）。

---

## 3. 日常开发规则

```powershell
cd C:\Users\71617\BossHunter
git switch my-custom-patch      # 开工前一定先切到补丁分支
git status                      # 确认没有意外改动
```

- **不要在 `main` 上 `git commit`**。如果手滑提交了：
  ```powershell
  git switch my-custom-patch
  git cherry-pick main            # 把误提交搬到补丁分支
  git switch main
  git reset --hard upstream/main  # main 恢复到官方状态
  ```
- 提交前跑一遍与改动相关的测试（见 §6）。
- 提交信息建议格式：
  ```
  fix(browser): 一句话说明修了什么

  根因：……
  改动：……
  验证：……
  ```
  升级 rebase 遇到冲突时，这段信息就是判断"这个补丁还要不要"的依据。

---

## 4. 升级官方版本（标准流程）

前提：工作区干净（`git status` 无输出）。有未提交改动先 `git stash` 或提交。

```powershell
git fetch upstream --prune
git switch main
git merge --ff-only upstream/main     # 只接受快进，出现分叉就说明 main 被污染了
git push origin main                  # 可选：同步到你的 fork
git switch my-custom-patch
git rebase main
```

也可以直接用仓库里的辅助脚本（见 §5）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\repo\sync-upstream.ps1 -RunTests
```

### 冲突处理

`rebase` 停在冲突时：

```powershell
git status                       # 看 "both modified" 的文件
# 手动编辑冲突文件，保留官方改动 + 你的补丁意图
git add <冲突文件>
git rebase --continue
```

放弃本次 rebase、回到升级前：

```powershell
git rebase --abort
```

### 冲突高发文件（按经验排序）

| 文件 | 原因 |
| --- | --- |
| `src/bosshunter/browser/runtime/cdp-proxy.mjs` | 浏览器运行时核心，上游经常改 |
| `src/bosshunter/browser/runtime/__init__.py` | 运行时启停/端口逻辑 |
| `src/bosshunter/web/preflight.py` | 预检规则 |
| `tests/test_browser_runtime_discovery.py`、`tests/test_web_preflight.py` | 测试夹具与上游同步演进 |

### rebase 之后必须做

1. 重跑测试（§6）。
2. `bosshunter connect` 必须四项全绿。
3. 如果补丁分支已经推到 fork，需要强推（rebase 改写了历史）：
   ```powershell
   git push --force-with-lease origin my-custom-patch
   ```
   `--force-with-lease` 比 `--force` 安全：别人（或另一台机器）推过新提交时会拒绝。

---

## 5. 辅助脚本

| 脚本 | 作用 |
| --- | --- |
| `scripts/repo/sync-upstream.ps1` | fetch 官方 → main 快进 → 补丁分支 rebase；可选推送 main、跑回归 |
| `scripts/repo/export-patches.ps1` | 把补丁分支相对 main 的提交导出成 `.patch` 文件（应急/迁移用） |

用法：

```powershell
# 同步 + 回归测试（推荐）
powershell -ExecutionPolicy Bypass -File scripts\repo\sync-upstream.ps1 -RunTests

# 同步并把 main 推到你的 fork
powershell -ExecutionPolicy Bypass -File scripts\repo\sync-upstream.ps1 -PushFork

# 导出补丁文件到 patches\
powershell -ExecutionPolicy Bypass -File scripts\repo\export-patches.ps1
```

脚本遇到冲突会停下并打印继续/放弃的命令，不会自动替你解决冲突。

---

## 6. 验证清单

```powershell
cd C:\Users\71617\BossHunter

# 1) 浏览器链路：应输出 4 个 ✓（Node / Runtime / Chrome / BOSS 页面）
bosshunter connect

# 2) AI 配置：需要已填写 API Key
bosshunter ai-status

# 3) 相关单元测试（本机未安装 pytest，用 unittest）
python -m unittest tests.test_browser_runtime tests.test_browser_runtime_discovery `
  tests.test_browser_diagnostics tests.test_web_preflight

# 4) 全量测试（可选，约 2 分钟）
python -m unittest discover -s tests
```

已知的环境性失败（与代码无关，可忽略）：

- `test_macos_launcher`：Windows 上无法断言可执行位；
- `test_resume_pdf_runtime`：临时目录在 D 盘、项目在 C 盘，`relpath` 跨盘报错；
- 依赖 `import pytest` 的测试模块：本机 Python 3.13 环境未装 pytest；
- 部分 BOSS 采集脚本测试：依赖真实的 node/子进程输出。

### 看板预检

工作台的"开始"按钮会调用 `/api/workbench/preflight`。想用命令行核对：

```powershell
# 需工作台正在运行（bosshunter web 默认 8686）
$body = @{ mode = "full" } | ConvertTo-Json
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8686/api/workbench/preflight `
  -Method POST -ContentType "application/json" -Body $body |
  Select-Object -ExpandProperty Content
```

> 修改了 `src/bosshunter/**/*.py` 后，**正在运行的 `bosshunter web` 不会热加载**，
> 需要重启工作台（关掉进程，重新双击桌面快捷方式）才生效。

---

## 7. 备选方案：补丁文件（format-patch）

分支 + rebase 是当前采用的主方案（补丁带测试、提交信息完整、历史清晰）。
如果你只想"带走改动"而不想维护分支，可以导出成补丁文件：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\repo\export-patches.ps1
# 生成 patches\0001-*.patch、0002-*.patch ...
```

在任意版本的官方代码上应用：

```powershell
git switch -c try-patch main
git am patches\*.patch          # 保留提交信息
# 或者：git apply --3way patches\*.patch
```

注意：

- `patches/` 已加入本机 `.git/info/exclude`（不会被误提交），属于本机备份；
- 补丁文件不会自动跟随官方更新，升级后需要重新 `git am` 并解决冲突；
- 想对比 rebase 前后补丁有没有变味：
  ```powershell
  git range-diff main my-custom-patch@{1} my-custom-patch
  ```

**为什么不建议 patch-package / pnpm patch？**
它们适用于 `node_modules` 里的第三方依赖；`cdp-proxy.mjs` 是本项目源码，不适用。
**为什么不建议外部插件/monkey patch？**
这个项目没有插件机制，要注入只能改核心文件；当前两个补丁都集中在 4 个源文件 + 2 个测试，
分支方案成本更低。

---

## 8. 当前补丁清单（2026-10-27）

| 提交 | 范围 | 内容 |
| --- | --- | --- |
| `cb78d6c` | `browser/runtime/cdp-proxy.mjs`、`browser/runtime/__init__.py`、`browser/diagnostics.py`、`tests/test_browser_runtime_discovery.py` | 运行时改为多候选重连；握手 8s 超时；运行日志落盘；诊断打印日志路径；新增"首个候选被拒时回退"回归测试 |
| `9917dde` | `web/preflight.py`、`tests/test_web_preflight.py` | 平台级关键词不再被误报为"未填写搜索关键词" |
| 本文档提交 | `docs/LOCAL_PATCH_WORKFLOW.md`、`scripts/repo/*.ps1` | 记录工作流、脚本与排障经验 |

### 补丁背景（为什么需要它们）

1. **运行时僵死**：`connect` 依赖 `/targets` 成功才判定就绪，而 `ensure_runtime`
   只看 `/health` 就复用已有进程。旧版 `discoverChromePort()` 遇到第一个
   `/json/version` 能通的端口就返回，不再尝试其他候选；该候选的 WebSocket 握手
   可能失败（陈旧 `DevToolsActivePort`、正在退出的浏览器、另一个开启调试的配置），
   于是运行时永久卡在 `connected:false` / `/targets` 500，用户必须手动结束 node。
   修复后会自动降级到下一个候选，并在 `finally` 清理连接状态，不再永久挂起。
2. **关键词误报**：Web UI 把关键词保存在 `platforms.<name>.search.keywords`，
   而旧预检只读全局 `search.keywords`，导致已经配置好的用户仍看到"尚未填写搜索关键词"。

---

## 9. 已知坑与操作建议

1. **Chrome 远程调试**：`chrome.exe --remote-debugging-port=9222` 在 Chrome 已经运行时
   **无效**（新命令只是转发给已有实例，参数被忽略）。正确做法：
   - 用桌面快捷方式 / `scripts\windows\start_bosshunter.ps1`（自动用独立配置目录
     `%LOCALAPPDATA%\BossHunterChrome` 启动 9222）；
   - 或先完全退出 Chrome，再带 `--user-data-dir=...` 启动。
2. **运行时日志**：`%LOCALAPPDATA%\BossHunter\logs\browser-runtime.log`。
   `connect` 失败时先看最后 10 行，比盲目重启高效。
3. **配置不是乱码**：`config.yaml` 是 UTF-8；PowerShell 5.1 默认按 GBK 显示中文会
   出现 `鍖椾含` 之类乱码，用 `Get-Content -Encoding utf8` 或编辑器确认即可。
4. **必填配置项**：`profile.resume_path` 指向的文件必须真实存在；AI 评分/招呼语/
   全流程需要 `ai.api_key`（`bosshunter ai-status` 可检查）。
5. **本地垃圾目录**：仓库根目录的 `Include/`、`Lib/`（约 190 MB）、`share/`、
   `testing/`、`scripts/bottle.py` 是误操作产生的本地文件，已加入
   `.git/info/exclude`（本机生效，不进提交）。确认无用后可删除。
6. **editable 安装**：`pip show bosshunter` 指向 `C:\Users\71617\BossHunter\src`。
   重装/升级依赖一般不会覆盖源码；但如果哪天改成 wheel 安装或重新 clone，
   补丁需要按 §7 重新应用。
7. **PowerShell 5.1 与中文脚本**：Windows PowerShell 5.1 默认按 ANSI(GBK) 读取
   `.ps1`，没有 UTF-8 BOM 的中文脚本会解析失败。本仓库 `scripts/repo/*.ps1`
   已写入 BOM；以后新增含中文的脚本请保存为 **UTF-8 with BOM**，或改用
   PowerShell 7（`pwsh`）执行。

---

## 10. 本次实际执行记录（2026-10-27）

```powershell
# 1) 双远程：官方 -> upstream，自己的 fork -> origin
git remote rename origin upstream
git remote add origin https://github.com/buwakaka/BossHunter.git

# 2) 确认官方版本（当时 upstream/main 与本机 main 相同）
git fetch upstream --prune
git rev-parse main upstream/main        # 均为 1f4e72d

# 3) 建补丁分支，把已有修复按功能提交
git switch -c my-custom-patch
#   cb78d6c fix(browser): 多候选重连 + 运行日志
#   9917dde fix(web): 平台关键词预检
#   docs: 本工作流文档 + 辅助脚本（提交号见 git log）

# 4) 导出补丁备份（patches/ 已在 .git/info/exclude 中排除）
powershell -File scripts\repo\export-patches.ps1
```

补充事实：

- `buwakaka/BossHunter` 当时 `git ls-remote` 返回 `Repository not found`，
  需要你手动 Fork（§2）；本机 `gh` 未登录，无法代建。
- `Include/`、`Lib/`、`share/`、`testing/`、`scripts/bottle.py` 已加入
  `.git/info/exclude`，属于本机文件，不参与提交。
- 本次没有执行 `git push`（fork 尚不存在）。
- `main` 当前与 `upstream/main` 完全一致；等官方发新版本时，§4 的同步流程
  会第一次真正走一遍 rebase。

---

## 11. 命令速查

```powershell
# 看当前布局
git remote -v
git branch -vv
git log --oneline --graph --decorate -10

# 只看本地补丁（相对官方）
git log --oneline upstream/main..my-custom-patch
git diff upstream/main..my-custom-patch --stat

# 同步官方 + rebase 补丁
git fetch upstream --prune
git switch main; git merge --ff-only upstream/main
git switch my-custom-patch; git rebase main

# 冲突时
git status
git add <file>; git rebase --continue
git rebase --abort            # 放弃

# 安全强推
git push --force-with-lease origin my-custom-patch

# 应急：把补丁导出/应用
powershell -File scripts\repo\export-patches.ps1
git am patches\*.patch
```