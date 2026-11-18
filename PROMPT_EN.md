# AI Agent Step-by-Step Procedure: Universal Clevo Control Center De-Hotkey & Repackaging SOP

> This document is written as an executable procedure for AI coding agents. For user overview and entry routing rules, see [`README_EN.md`](README_EN.md).

---

## Mandatory Guardrails (Read Before Starting)

1. **Never modify retained `.sys` kernel drivers** or root files covered by their `.cat` catalogs (`AcpiBridge.inf/.sys/.cat`, `AcpiBridge1.Inf/.sys/.cat`, and catalog-protected root files next to `AcpiBridge1.Inf`), so Windows Authenticode/WHQL validation succeeds.
2. **Accurately separate kernel hotkey filters (REMOVE) from core laptop controls (KEEP)**:
   - **Remove**: `Driver\` (`HKKbdFltr.sys`, `HKKbdFltr.inf`, `HKMouFltr.sys`, `HKMouFltr.inf`, `hkkbdfltr.cat`, `hkmoufltr.cat`, `HKClipSvc.exe`, `HKFltrInstaller.exe`, `HKFltrLib.dll/.lib/.h`, `HKFltrSetup.bat`), `Flexikey.appxbundle`, `kb.dll`, `HKFltrLib.dll`, `CustomCapability.sccd`, embedded `FKeyDriver.zip`, and `<uap4:CustomCapability Name="Clevo.keyboardMouseFilter_..." />`.
   - **Keep untouched**: `AcpiBridge` (`ACPI\CLV0001` WMI/EC bridge), `AcpiBridge1` (`ACPI\CLV0002` user-mode `CCDCHUService`), user-mode `Windowshook.dll` / `SetWindowsHookEx` features (`WakePanelUp` OLED wakeup, `PerkeyKB` / `perkeyhook` RGB lighting), EC WMI toggles (`PgUpDnKey`, `FnkeyLock`, `WinkeyEnable`), and tray/power/fan/battery controls.
3. **Never hardcode IL line numbers or offsets**: Clevo releases vary by OEM SKU and version. Locate every target dynamically by class, method signature, literal, or WMI bitmask pattern in your disassembled IL.
4. **Protect the build host**: Perform all unpacking, patching, packaging, signing, and verification inside an isolated workspace directory. **Do not install drivers or modify system registry/UWP packages on the dev machine without explicit user permission.**

---

## Mode A: Build Clean De-Hotkey Installer from Vendor Package

### Step 0: Check Inputs & Tooling
1. Confirm the local path to the user's vendor Control Center installer (`.rar`/`.zip`/`.exe`/folder). If omitted, ask before proceeding.
2. Verify availability of `python`, `.NET v4.0.30319` (`ilasm.exe`, `csc.exe`), `ildasm.exe`, and `PEVerify.exe`. If any required disassembly/verification binary is missing, report it to the user.
3. When [`tools/`](tools/) is present in the workspace, reuse `decrypt_clevo_inx.py`, `appx_repacker.py`, `sign_appx.ps1`, and `Common_Clean.ps1`; otherwise implement equivalent logic from the exact specs below.

### Step 1: Unpack & Asset Inventory
1. Extract the vendor archive/installer to a clean workspace (handle `.rar`/`.zip`/`.7z`/MSI/InstallShield `data1.cab`+`data1.hdr`).
   - For InstallShield packages, extract `TARGETDIR\`, `UNKNOWN_DIR*\` (often Intel XTU `.msi`), and root `oem.ini` / `setup.inx`.
   - If an obfuscated `setup.inx` exists, run:
     ```bash
     python tools/decrypt_clevo_inx.py <path/to/setup.inx> <output.bin> --strings
     ```
     (uses Clevo's InstallScript transform `(ror(b ^ 0xf1, 2) - (i % 71)) & 0xff`) to recover exact `Setup.rul` install/uninstall steps (`AppReadiness\FirstLogonDelay`, `EventLogSize.bat`, `PreCC30.exe`, XTU MSI + `Dpint.exe`/`Pnputil.exe`, ACPI INFs, `RunAutoInstall.exe`, `manual.pdf`, `AppSettings`).
2. Extract all `.appxbundle` and inner `_x64.appx` packages. Run `ildasm.exe /nobar /out:...` on every `.NET` EXE/DLL (preserving `.res` and `.mresource` assets) and inspect PE headers (`Machine`, `PE32`/`PE32+`, `Subsystem`, `CorFlags`, strong-name keys).
3. Search across all extracted payloads and IL files for:
   `HKKbdFltr`, `HKMouFltr`, `HKClipSvc`, `HKFltr`, `kb.dll`, `FKeyDriver`, `cfdv`, `Flexikey`, `keyboardMouseFilter`, `shell:appsFolder`, `SessionUnlock`.

### Step 2: Dynamic Analysis & CIL Patching
Locate matching symbols in each relevant assembly and apply stack-safe patches:

1. **Auto-Installer (`RunAutoInstall.exe`)**: Disable the Flexikey bit (typically bit 2 / index 1) in `GetWMIFlag` so `SupportArray[1]` remains `0`; blank `"CLEVOCO.Flexikey"` and `"Flexikey"` in lookup helpers.
2. **Launcher Tile App (`ControlCenter30.exe` in `CC30.appxbundle`)**: Force `APP_Flexikey = false` in `App::GetWMIFlag` (never incrementing `AppCount`); force `BTN_Flexikey` collapsed in `Window_MOUSE::.ctor`; stub `BTN_Flexikey_Click`; blank `"Flexikey"`, `"clevoflexikey:"`, and `ic_flexikey.png` in `AllApp` and `LaunchApp`.
3. **Core Control Hub (`FnKey.appxbundle`: `FnKey.exe`, `CC40.exe`, `cc30wk.exe`, `COUWP.exe`)**:
   - **`FnKey.exe`**: Force `SupportFlexikey = false` in `Features::DoWMIFlag`; stub `FlexikeyInit`, `SetKeybordMouseEnble`, `Set_Filiter_Driver`, `CheckFlexikeyDriver`, `UpdateFlexikeyStatusTimer_Tick`, `FnKey.Flexikey`, and all `"kb.dll"` loaders inside `Set2Driver`; guard `Arg001_GetEvent` lambdas.
   - **`CC40.exe`**: Force `UWP_Flexikey = false` in `InsydeDriver::GetWMIFlag` (ensuring `Thread_Init` removes `BTN_PageFlexikey` / `BTN_PageFlexikey_2` tabs and never constructs `Page_FlexiKey`); guard all `page_flexikey` callers (`BTN_PageFlexiKey_Click`, page switch cases, `ExecEvent`, `FnKeyEvent`, EventLog `"osfd"` handlers); stub `Page_FlexiKey` active methods & all `Set2Driver` `"kb.dll"` wrappers; delete `AssemblyAssociatedContentFileAttribute` entries pointing to `dlls/kb.dll` and `dlls/hkfltrlib.dll`.
   - **`cc30wk.exe`**: Delete the `.mresource` declaration for `FKeyDriver.zip` and omit the zip during reassembly; skip the `-cfdv` branch in `ExecWorkaround` and stub `CheckIfFlexikeyDriverIsLateset` + its predicate lambda.
   - **`COUWP.exe`**: Neutralize `"flexikey"` in `TranslateName`.
4. **Fix Unlock-Screen File Explorer Popup (`DCHU\LaunchFnkey.exe`)**:
   - **Do NOT touch root `LaunchFnkey.exe` next to `AcpiBridge1.Inf`** (catalog-signed by `acpibridge1.cat`).
   - Patch the non-driver copies inside `FnKey\FnKey\DCHU\LaunchFnkey.exe` and `Payload\DCHU\LaunchFnkey.exe` so `LaunchFnKey()` replaces bare `explorer.exe shell:appsFolder\CLEVOCO.FnhotkeysandOSD_...!App` with:
     `if (Get-AppxPackage CLEVOCO.FnhotkeysandOSD* -ErrorAction SilentlyContinue | Where-Object Status -eq Ok) { Start-Process clevofnkey: -ErrorAction SilentlyContinue }`
5. **CIL Assembly Invariants & `PEVerify` Gate**:
   - **Evaluation stack conservation**: Replacing single-operand conditional branches (`brfalse.s target` / `brtrue.s target`) MUST emit `pop` before `br.s target`; replacing two-operand branches (`bne.un.s target` / `beq.s target`) MUST emit `pop; pop` before `br.s target`.
   - **Infinity float bug**: Replace any `ildasm`-emitted `ldc.r8 inf` / `ldc.r4 inf` with IEEE-754 bytes (`ldc.r8 (00 00 00 00 00 00 F0 7F)` / `ldc.r4 (00 00 80 7F)`).
   - Assemble with `ilasm.exe /NOLOGO /QUIET /PE64 /X64 /EXE /RESOURCE=... /OUTPUT=...` (matching original PE flags) from a resource folder excluding `FKeyDriver.zip`.
   - Copy each rebuilt EXE into a verification directory containing all real runtime dependencies **excluding `kb.dll` and `HKFltrLib.dll`**, run `PEVerify.exe`, and require zero new verification errors.

### Step 3: Clean Staged Packages, Rebuild & Sign `.appxbundle`
1. Remove `kb.dll`, `HKFltrLib.dll`, and `CustomCapability.sccd` from staged `FnKey`; remove `<uap4:CustomCapability Name="Clevo.keyboardMouseFilter_..." />` (+ unused `xmlns:uap4` / `IgnorableNamespaces`) from `AppxManifest.xml`; remove `flexikey` and decrement `applicationCount` in `ClevoUWP.json`.
2. Generate a matching code-signing certificate (`PublisherCN` MUST match `<Identity Publisher="..."/>` verbatim; `KeyUsage = DigitalSignature`, `EKU = 1.3.6.1.5.5.7.3.3`, `BasicConstraints = End Entity`):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools/sign_appx.ps1 -CreateCert -PublisherCN "<Publisher_From_Manifest>" -OutDir <cert_dir> -Password "<pwd>"
   ```
3. Rebuild and sign modified `.appxbundle`s (use `makeappx.exe` + `signtool.exe` if installed, OR use [`tools/appx_repacker.py`](tools/appx_repacker.py) + [`tools/sign_appx.ps1`](tools/sign_appx.ps1)):
   - Compress deflated entries in 64 KB chunks using **`zlib.Z_FULL_FLUSH`** per chunk (`Z_FINISH` on final chunk; never `Z_SYNC_FLUSH`); store `.png`/media with `method=0`;
   - Decode percent-encoded ZIP filenames via **`urllib.parse.unquote`** before writing `<File Name="...">` in `AppxBlockMap.xml`;
   - Strip old `AppxSignature.p7x`, `CodeIntegrity.cat`, and their `[Content_Types].xml` overrides; re-sign all inner `scale-*.appx` resource packs with the same certificate; update `Offset` & `Size` in `AppxBundleManifest.xml`; sign outer `.appxbundle` (files must end in `.appx`/`.appxbundle` for `AppxSip.dll`).
4. Update modified `InstallPackage.bat` files (`CC3.0` and `FnKey`) to `/SkipLicense`, remove their mismatched Store `*_License1.xml` files (keep all untouched OEM Store bundles and licenses as-is), and fix Clevo's `sc detele CCDCHUService` typo in `uninstallDCHUService.bat`.

### Step 4: Package Clean Installer & Remnant Repair Scripts
Assemble a transparent folder (`Install.bat`, `Uninstall.bat`, `.cer`, `scripts\`, `Payload\`, `README.txt`) and a UAC-elevating C# SFX `.exe` (`csc.exe`, supporting `--uninstall`, `--silent`, `--extract <dir>`):
1. **Safe Remnant Cleaner (`tools/Common_Clean.ps1` pattern)**:
   - Stop Clevo/hotkey processes;
   - Strip ONLY `HKKbdFltr` / `HKMouFltr` from `UpperFilters` & `LowerFilters` on Keyboard Class `{4d36e96b-e325-11ce-bfc1-08002be10318}`, Mouse Class `{4d36e96f-e325-11ce-bfc1-08002be10318}`, and `HKLM\SYSTEM\CurrentControlSet\Enum\*`, explicitly preserving `kbdclass` and `mouclass` as `[string[]]` (`REG_MULTI_SZ`);
   - Perform locale-independent DriverStore cleanup by parsing `pnputil /enum-drivers` (ASCII & CJK colons) AND scanning `C:\Windows\INF\oem*.inf` content for `HKKbdFltr.sys`, `HKMouFltr.sys`, `ACPI\CLV0001`, `ACPI\CLV0002`, removing via `pnputil /delete-driver <oem.inf> /uninstall /force`;
   - Clean `HKClipSvc`, `HKKbdFltr`, `HKMouFltr`, `CCDCHUService`, `Xtu3Service`, leftover `.sys`, `C:\Program Files (x86)\ControlCenter`, `C:\ComboKey`, `HKLM\SOFTWARE\ControlCenterAP`, `AcpiBridge\Parameters\AppSettings`, prior `CLEVOCO.*` UWPs, and stale `Run` keys.
2. **Install Sequence (Mirroring `Setup.rul`)**:
   - Import `.cer` to `LocalMachine\Root` & `TrustedPeople`, set `AllowAllTrustedApps = 1`, `FirstLogonDelay = 60`;
   - Copy clean `Payload\` (with `oem.ini` & XTU MSI, without `Driver\` or `AppInstall\Flexikey\`) to `C:\Program Files (x86)\ControlCenter\`;
   - Run XTU MSI (non-fatal on AMD), `PreCC30.exe`, `EventLogSize.bat`, `pnputil /add-driver AcpiBridge.inf /install` & `AcpiBridge1.Inf`, then patched `RunAutoInstall.exe`;
   - Verify/repair active-user `CLEVOCO.FnhotkeysandOSD` & `CLEVOCO.ControlCenter3.0` (`Status -eq 'Ok'`, running `Add-AppxPackage -ForceApplicationShutdown` if only provisioned), trigger `clevofnkey:`, print health summary, and advise a reboot.
3. **Compile SFX `.exe`**: Bundle payload ZIP cleanly after a C# stub (`csc.exe`, embedded `icon_tray.ico`, magic footer with offset + length) supporting UAC auto-elevation when running install/uninstall and unelevated `--extract <dir>`.

### Step 5: Mandatory Verification Gates
Run all checks before reporting completion and state only observed outputs:
1. All modified `.exe` assemblies pass `PEVerify.exe` with 0 new errors; binary & archive scans confirm zero residual `HKKbdFltr`, `HKMouFltr`, `HKClipSvc`, `HKFltrInstaller`, `HKFltrLib`, `kb.dll`, `CustomCapability.sccd`, or `Flexikey.appxbundle`.
2. Retained `AcpiBridge.*` and `AcpiBridge1.*` files match original SHA-256 hashes 1:1.
3. Rebuilt `_x64.appx` packages pass COM `IAppxFactory::CreatePackageReader`, and modified + unmodified `.appxbundle` files pass `Get-AuthenticodeSignature` checks.
4. All `.ps1` scripts pass `[System.Management.Automation.Language.Parser]::ParseFile`.
5. Running `*_Setup.exe --extract <tmp>` extracts cleanly and matches the folder contents byte-for-byte via SHA-256 (then clean up `<tmp>`).

---

## Mode B: Emergency PC Cleanup Only (Without Repackaging)

When a user only needs to rescue dead input (`UpperFilters`), stop unlock-screen Explorer popups, or remove broken Clevo remnants:
1. Prepare/adapt [`tools/Common_Clean.ps1`](tools/Common_Clean.ps1), show the user the exact registry paths, services (`HKClipSvc`, `HKKbdFltr`, `HKMouFltr`, `CCDCHUService`), and DriverStore INFs to be cleaned, and ask confirmation before running as Administrator (`-RunRepair -FullClean`).
2. Verify `UpperFilters` on `{4d36e96b-...}` / `{4d36e96f-...}` retain `kbdclass` / `mouclass` (`REG_MULTI_SZ`) without hotkey filters, and `CCDCHUService` / Clevo `oem*.inf` remnants are gone.
3. Prompt the user to reboot once.
