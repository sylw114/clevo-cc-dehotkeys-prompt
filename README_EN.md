# Clevo Control Center De-Hotkey Prompt Repository

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **Zero proprietary OEM binaries distributed.** This repository provides a universal, version-agnostic **AI Agent Step-by-Step Procedure ([`PROMPT_EN.md`](PROMPT_EN.md) / [`PROMPT.md`](PROMPT.md))** and **SDK-free companion tools ([`tools/`](tools/))** so any AI coding agent can dynamically analyze *your* vendor-specific Control Center installer, strip Clevo kernel hotkey filter drivers cleanly, fix legacy remnant issues, and build a verified clean installer.

For Chinese documentation, see [`README.md`](README.md) and [`PROMPT.md`](PROMPT.md).

> 🤖 **AI Agent Notice**: If a user shared this repository URL with you, follow **Part 2: Instructions for AI Agents** below and execute the steps in [`PROMPT_EN.md`](PROMPT_EN.md) (or [`PROMPT.md`](PROMPT.md) for Chinese).

---

## Part 1: Guide for Users

### 1. What Problems Does This Solve?
Clevo barebones laptops (Sager, XMG, Schenker, Colorful, Hasee, Mechrevo, Thunderobot, System76, Gigabyte, etc.) often suffer BSODs caused by Clevo's kernel keyboard/mouse filter drivers (`HKKbdFltr.sys` / `HKMouFltr.sys`). Manually deleting those files frequently triggers three secondary breakages:
- **Dead Keyboard & Mouse**: Deleting `.sys` files while `HKKbdFltr` / `HKMouFltr` stay in `UpperFilters` (or corrupting `kbdclass` / `mouclass`).
- **File Explorer Popping Up on Every Screen Unlock**: `AcpiBridge1.Inf`'s `CCDCHUService` (`DCHUService.exe`) handles `SessionUnlock` by running `LaunchFnkey.exe` -> `explorer.exe shell:appsFolder\CLEVOCO.FnhotkeysandOSD_...!App`. Clevo's own uninstall batch also has a **`sc detele CCDCHUService` typo**. When `FnKey` UWP is missing or broken, Windows falls back to opening File Explorer on every unlock.
- **Control Center Won't Open**: Stripping the wrong services breaks `AcpiBridge` WMI controls, Power Modes, Fan Curve, Battery settings, or crashes the UI.

**After your AI Agent runs this workflow on your vendor package, you get a clean custom installer that**:
- Eliminates all Clevo kernel hotkey drivers (`HKKbdFltr`, `HKMouFltr`, `HKClipSvc`, `HKFltrLib`, `kb.dll`, `CustomCapability.sccd`, `FKeyDriver.zip`, `Flexikey`) and all Flexikey UI/code;
- **Keeps WHQL-signed `AcpiBridge.sys` / `AcpiBridge1.sys`**, OLED wakeup (`WakePanelUp`), Per-Key RGB (`PerkeyKB`), Power Modes, Fan Speed, and Battery protection fully functional;
- Includes a patched unlock-safe `LaunchFnkey.exe`, pre-clean repair scripts for broken `UpperFilters` / DriverStore leftovers, and freshly signed `.appxbundle`s + single-file `*_Setup.exe`.

### 2. How to Use It
**Option A (Recommended — Full Clean Repackage)**: Send this repository link + your vendor installer path directly to your AI coding agent (Antigravity, Claude Code, Codex, Cursor, Gemini CLI, etc.):
> Please follow this repo `https://github.com/sylw114/clevo-cc-dehotkeys-prompt` to strip Clevo hotkey drivers and related code/UI from my official Control Center installer at `D:\Downloads\07_CC30.rar` and build a clean repackaged installer.

**Option B (Repair an Already-Broken PC Only)**: Ask your agent to follow **Mode B** in the prompt to safely clean `UpperFilters`, orphaned `CCDCHUService` / DriverStore `oem*.inf` leftovers, and stop unlock-time Explorer popups.

### 3. Build Host Prerequisites
- Windows 10 / Windows 11 with `.NET Framework 4.x` (`ilasm.exe`, `csc.exe`)
- Python 3.x
- `ildasm.exe` & `PEVerify.exe` (included with Visual Studio / .NET Framework SDK Tools)
- **No full Windows 10/11 SDK (`makeappx.exe` / `signtool.exe`) needed** — [`tools/`](tools/) handles APPX packaging and native `AppxSip.dll` signing directly.

---

## Part 2: Instructions for AI Agents

When a user points you to this repository, follow these routing and execution rules:

1. **Determine Mode & Required Input**:
   - **Mode A (Full Repackage)**: Confirm the local path to the user's vendor installer archive/folder. If missing, ask the user before proceeding.
   - **Mode B (Emergency PC Cleanup Only)**: Use Mode B steps to generate/audit a cleanup script; do not execute registry/driver modifications silently without user confirmation.
2. **Fetch Full Repo & Execute the Step-by-Step Procedure**:
   - If you were only handed the repository URL, clone it to a local temp directory (`git clone https://github.com/sylw114/clevo-cc-dehotkeys-prompt`) so you have local access to both the prompt and `tools/`.
   - English: [`PROMPT_EN.md`](PROMPT_EN.md)
   - 中文：[`PROMPT.md`](PROMPT.md)
3. **Reuse Verified Utilities in [`tools/`](tools/) When Available**:
   - [`tools/decrypt_clevo_inx.py`](tools/decrypt_clevo_inx.py) — Decrypts Clevo InstallShield `setup.inx` to inspect vendor `Setup.rul` install/uninstall steps.
   - [`tools/appx_repacker.py`](tools/appx_repacker.py) — Pure-Python APPX / APPXBUNDLE builder implementing `zlib.Z_FULL_FLUSH` 64 KB blocks, URL-decoded BlockMap paths (`urllib.parse.unquote`), resource pack re-signing, and exact `AppxBundleManifest.xml` offset/size recalculation.
   - [`tools/sign_appx.ps1`](tools/sign_appx.ps1) — Generates matching `CN=<Publisher>` code-signing certificates (`-CreateCert`) and signs packages via Win32 `SignerSignEx2` + `AppxSip.dll`.
   - [`tools/Common_Clean.ps1`](tools/Common_Clean.ps1) — Locale-independent DriverStore (`pnputil` + `C:\Windows\INF\oem*.inf` scan), safe `UpperFilters`/`LowerFilters` filter stripping (preserving `kbdclass`/`mouclass` as `REG_MULTI_SZ`), and `CCDCHUService` cleanup helper.
   - *(If your agent only has read access to the prompt text without fetching `tools/`, the full algorithms and Win32 P/Invoke specs are documented inside `PROMPT_EN.md` / `PROMPT.md`.)*
4. **Hard Constraints & Verification Gates**:
   - Locate IL targets dynamically by symbol/logic—never hardcode version-specific line numbers.
   - Keep all build/unpack/sign work inside an isolated working directory; never install drivers or edit system registry/UWP packages on the dev host unless explicitly requested.
   - Run and verify all gates (`PEVerify` without `kb.dll`/`HKFltrLib.dll`, `IAppxFactory::CreatePackageReader`, `Get-AuthenticodeSignature`, zero banned hotkey artifacts, SHA-256 preservation of retained `.sys`/`.cat`, PowerShell AST check, SFX extract hash verification) and report only observed results.

---

## Repository Layout

| Path | Audience | Purpose |
| --- | --- | --- |
| [`README.md`](README.md) / [`README_EN.md`](README_EN.md) | Users + Agent Entry | Problem overview, usage guide, and Agent routing rules |
| [`PROMPT.md`](PROMPT.md) / [`PROMPT_EN.md`](PROMPT_EN.md) | AI Agent SOP | Detailed Step 0–Step 5 execution workflow & Mode B repair steps |
| [`tools/`](tools/) | AI Agent / Power Users | Generalized `.inx` decryptor, SDK-free APPX builder/signer, and cleanup helpers |
| [`LICENSE`](LICENSE) | Everyone | MIT License |
