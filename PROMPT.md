# AI Agent 执行步骤：通用蓝天（Clevo）Control Center 去热键驱动与重打包 SOP

> 本文件面向 AI Agent，规定从用户提供的官方安装包（`.rar` / `.zip` / `.exe` / 文件夹）构建去热键驱动版本安装包的标准化步骤。入口说明见 [`README.md`](README.md)。

---

## 前置约束（全程必须遵守）

1. **禁止修改任何保留的 `.sys` 内核驱动**及与其 `.cat` 目录签名的配套根文件（`AcpiBridge.inf/.sys/.cat`、`AcpiBridge1.Inf/.sys/.cat` 与受 `acpibridge1.cat` 覆盖的驱动目录文件），否则破坏 WHQL/目录签名导致 Windows 拒绝加载。
2. **禁止误伤正常硬件控制功能**：
   - **必须删除**：`Driver\` 目录（`HKKbdFltr.sys`、`HKKbdFltr.inf`、`HKMouFltr.sys`、`HKMouFltr.inf`、`hkkbdfltr.cat`、`hkmoufltr.cat`、`HKClipSvc.exe`、`HKFltrInstaller.exe`、`HKFltrLib.dll/.lib/.h`、`HKFltrSetup.bat`）、`Flexikey.appxbundle`、包内 `kb.dll` / `HKFltrLib.dll` / `CustomCapability.sccd`、内嵌更新包 `FKeyDriver.zip`、Manifest 中的 `Clevo.keyboardMouseFilter_*` 能力声明。
   - **必须保留**：`AcpiBridge`（`ACPI\CLV0001`，EC/BIOS WMI 通信）、`AcpiBridge1`（`ACPI\CLV0002`，用户态 `CCDCHUService` / `DCHUService.exe`）、使用用户态 `Windowshook.dll` / `SetWindowsHookEx` 的 OLED 防烧唤醒（`WakePanelUp`）与单键背光（`PerkeyKB`/`perkeyhook`），以及 EC WMI 控制的 `PgUpDnKey` / `FnkeyLock` / `WinkeyEnable` 与托盘菜单。
3. **禁止硬编码行号与版本特征**：不同机型的 Control Center 版本、IL 行号、局部变量编号与 UI 页面变体不同，所有目标点必须通过反汇编后按类名/方法名/字符串/位运算特征动态定位。
4. **宿主机安全**：所有解包、反编译、重打包与校验在独立工作目录完成；**不要未经允许对当前构建机执行驱动安装、系统注册表修改或宿主 UWP 部署**。

---

## Mode A：从官方安装包构建去热键重打包版本（完整步骤）

### Step 0：环境与伴随工具检查
1. 确认用户输入的目标安装包路径；若缺失则先向用户确认，再开始执行。
2. 检查构建机可用工具：`python`、`ilasm.exe`（`.NET v4.0.30319`）、`csc.exe`、`ildasm.exe`、`PEVerify.exe`（Windows SDK / NETFX Tools）。若缺少 `ildasm.exe` 或 `PEVerify.exe` 等反编译/校验关键工具，立即向用户报告缺失项。
3. 若工作区存在本仓库 [`tools/`](tools/) 目录，优先复用其中的 `decrypt_clevo_inx.py`、`appx_repacker.py`、`sign_appx.ps1`、`Common_Clean.ps1`；否则按下方各步中的底层规格生成等价工具。

### Step 1：全量解包与资产测绘
1. 将用户提供的压缩包或安装器解压到工作目录（支持 `.rar` / `.zip` / `.7z` / MSI / InstallShield `data1.cab` + `data1.hdr`）。
   - 若为 InstallShield 包，提取出 `TARGETDIR\`、`UNKNOWN_DIR*\`（常含 Intel XTU `.msi`）及根目录 `oem.ini` / `setup.inx`。
   - 若存在加密的 `setup.inx`，运行：
     ```bash
     python tools/decrypt_clevo_inx.py <setup.inx路径> <output.bin> --strings
     ```
     （核心解密公式为 `(ror(b ^ 0xf1, 2) - (i % 71)) & 0xff`），从中提取官方原版 `Setup.rul` 安装与卸载顺序（如 `AppReadiness\FirstLogonDelay`、`EventLogSize.bat`、`PreCC30.exe`、Intel XTU MSI 与 `Dpint.exe`/`Pnputil.exe`、ACPI INF、`RunAutoInstall.exe`、`manual.pdf`、`AppSettings` 等），确保关键初始化步骤一个不少。
2. 解包全部 `.appxbundle` 与内部 `_x64.appx`（以及独立 `.exe`）。对全部 `.NET` 程序集执行 `ildasm.exe /nobar /out:...`，保留 `.res` Win32 资源文件与托管 `.mresource` 文件，并读取记录每个原始 EXE 的 PE 头字段（`Machine`、`PE32`/`PE32+`、`Subsystem`、`CorFlags` 及是否强签名）。
3. 扫描所有目录与 `.il` 文件中的关键符号与字符串：
   `HKKbdFltr`, `HKMouFltr`, `HKClipSvc`, `HKFltr`, `kb.dll`, `FKeyDriver`, `cfdv`, `Flexikey`, `keyboardMouseFilter`, `shell:appsFolder`, `SessionUnlock`。

### Step 2：动态定位目标并执行 CIL 补丁改造
按各模块实际反汇编结果精确修改并保持 IL 堆栈严格平衡：

1. **修复热键驱动逻辑与 UI 入口**：
   - **引导安装器（如 `RunAutoInstall.exe`）**：在 `GetWMIFlag`（通常检测位 bit 2 / 索引 1）中强制跳过添加 Flexikey 启用标记（保持 `SupportArray[1] = 0`）；将 `GetUWPPackageIdentityName` / `GetAppName` 中的 `"CLEVOCO.Flexikey"` / `"Flexikey"` 置空。
   - **主瓷贴入口（如 `CC30.appxbundle` 内的 `ControlCenter30.exe`）**：在 `App::GetWMIFlag` 强制禁用 `APP_Flexikey`（不增加 `AppCount`）；在 `Window_MOUSE::.ctor` 强制隐藏 `BTN_Flexikey` 并置空 `BTN_Flexikey_Click`；清除 `AllApp` 九宫格与 `LaunchApp` 中的 `"Flexikey"` / `"clevoflexikey:"` / `ic_flexikey.png` 引用。
   - **核心控制 hub（如 `FnKey.appxbundle` 内的 `FnKey.exe`、`CC40.exe`、`cc30wk.exe`、`COUWP.exe`）**：
     - **`FnKey.exe`**：在 `Features::DoWMIFlag` 中强制跳过 `SupportFlexikey = true`；置空 `FlexikeyInit`、`SetKeybordMouseEnble`、`Set_Filiter_Driver`、`CheckFlexikeyDriver`、`UpdateFlexikeyStatusTimer_Tick`；置空 `FnKey.Flexikey` 以及 `Set2Driver` 中所有动态加载 `"kb.dll"` 的方法；守卫 `Arg001_GetEvent` 等事件回调跳过 Flexikey。
     - **`CC40.exe`**：在 `InsydeDriver::GetWMIFlag` 强制跳过 `UWP_Flexikey = true`（确保启动自动移除左侧 `BTN_PageFlexikey` 选项卡并跳过实例化 `Page_FlexiKey`）；守卫所有访问 `page_flexikey` 的方法（`BTN_PageFlexiKey_Click`、页面切换 switch case、`ExecEvent`、`FnKeyEvent`、EventLog `"osfd"` 分支）；置空 `Page_FlexiKey` 运行方法及 `Set2Driver` 全部 `"kb.dll"` 包装方法；删除程序集头中引用 `dlls/kb.dll` 和 `dlls/hkfltrlib.dll` 的 `.custom ... AssemblyAssociatedContentFileAttribute`。
     - **`cc30wk.exe`**：从 `.il` 头部删除 `FKeyDriver.zip` 的 `.mresource` 声明并在汇编目录排除该 zip；跳过 `ExecWorkaround` 的 `-cfdv` 分支，置空 `CheckIfFlexikeyDriverIsLateset` 及其匿名谓词。
     - **`COUWP.exe`**：屏蔽在线更新名称翻译中的 `"flexikey"`。
2. **根治“每次解锁屏幕弹出 Explorer”缺陷（修改 `DCHU\LaunchFnkey.exe`）**：
   - 背景：`CCDCHUService`（`AcpiBridge1.Inf`）在系统 `SessionUnlock` 时会运行 `C:\Program Files (x86)\ControlCenter\DCHU\LaunchFnkey.exe`，原版直接通过 PowerShell 调用 `explorer.exe shell:appsFolder\CLEVOCO.FnhotkeysandOSD_...!App`，一旦 `FnKey` UWP 缺失/未就绪就会打开文件资源管理器。
   - 定位 **非 `acpibridge1.cat` 覆盖的副本**（位于 `FnKey\FnKey\DCHU\LaunchFnkey.exe` 与 `Payload\DCHU\LaunchFnkey.exe`，**严禁改动根目录受 `acpibridge1.cat` 签名的 `LaunchFnkey.exe`**）：
   - 修改 `LaunchFnKey()` 内传给 PowerShell 的命令字符串，改为先校验状态再通过协议激活：
     `if (Get-AppxPackage CLEVOCO.FnhotkeysandOSD* -ErrorAction SilentlyContinue | Where-Object Status -eq Ok) { Start-Process clevofnkey: -ErrorAction SilentlyContinue }`
3. **CIL 汇编安全规范与 `PEVerify` 门禁**：
   - **堆栈平衡铁律**：把 `brfalse.s target` / `brtrue.s target`（弹出 1 个栈元素）改成跳过分支时，**必须写为 `pop` + `br.s target`**；把 `bne.un.s target` / `beq.s target`（弹出 2 个栈元素）改成跳过分支时，**必须写为 `pop; pop; br.s target`**。
   - **浮点无限大修复**：若 `.il` 出现 `ildasm` 反编译出的 `ldc.r8 inf` / `ldc.r4 inf`，替换为 IEEE-754 原始字节 `ldc.r8 (00 00 00 00 00 00 F0 7F)` / `ldc.r4 (00 00 80 7F)`。
   - **目标平台匹配与汇编**：根据原 PE 头运行 `ilasm.exe /NOLOGO /QUIET /PE64 /X64 /EXE /RESOURCE=... /OUTPUT=...`（确保工作目录含 `.res` 与所有托管 `.resources`/固件资源，不含 `FKeyDriver.zip`）。
   - **验证**：将所有改造后 `.exe` 放到完整依赖 DLL 的临时验证目录（刻意删除 `kb.dll` 和 `HKFltrLib.dll`），逐一执行 `PEVerify.exe`，确认零新增验证错误。

### Step 3：清理解包清单、重建并签名 `.appxbundle`
1. 在临时解包目录（如 `FnKey`）执行清理：
   - 删除 `kb.dll`、`HKFltrLib.dll`、`CustomCapability.sccd`；
   - 更新 `AppxManifest.xml`，删去 `<uap4:CustomCapability Name="Clevo.keyboardMouseFilter_..." />` 及无用的 `xmlns:uap4` / `IgnorableNamespaces` 引用；
   - 更新 `ClevoUWP.json`，移除 `flexikey` 项并将 `applicationCount` 减 1。
2. 生成代码签名证书（主体 `PublisherCN` **必须与 `AppxManifest.xml` 中 `<Identity Publisher="..."/>` 完全一致**，具备 `KeyUsage = DigitalSignature`、`EKU = 1.3.6.1.5.5.7.3.3`、`BasicConstraints = End Entity`）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools/sign_appx.ps1 -CreateCert -PublisherCN "<从Manifest读取的Publisher>" -OutDir <cert_dir> -Password "<pwd>"
   ```
3. 重建并签名改造过的 `.appxbundle`（例如 `CC30.appxbundle` 与 `FnKey.appxbundle`）：
   - 如有 Windows SDK（`makeappx.exe` + `signtool.exe`）可用，也可直接调用；**若无 SDK，直接使用 [`tools/appx_repacker.py`](tools/appx_repacker.py) + [`tools/sign_appx.ps1`](tools/sign_appx.ps1)**（或等价实现），务必确保：
     1. 压缩条目按 64 KB 分块并以 **`zlib.Z_FULL_FLUSH`** 刷新每块（避免 `Z_SYNC_FLUSH` 导致 `IAppxFactory` 报 `0x80080205`），`.png` 等图片以 `STORE (method=0)` 存储；
     2. `AppxBlockMap.xml` 内的 `<File Name="...">` 必须对 ZIP 项名称做 **`urllib.parse.unquote`** 解码，兼容 `%20` / `%C3%A9` 等转义路径；
     3. 重包前清理旧 `AppxSignature.p7x`、`CodeIntegrity.cat` 与对应 `[Content_Types].xml` `<Override>`，并将同一 Bundle 内的 `scale-*.appx` 资源包一并用新证书重签；
     4. 精确回填 `AppxBundleManifest.xml` 中每个内部 `.appx` 的 `Offset` 与 `Size`，再签名外层 `.appxbundle`（输出路径必须保留 `.appx`/`.appxbundle` 扩展名以触发系统 `AppxSip.dll`）。
4. 更新改过包的 `InstallPackage.bat`（如 `CC3.0` 与 `FnKey`）为：
   `Dism /Online /Add-ProvisionedAppxPackage /PackagePath:<bundle> /SkipLicense /Region="all"`
   并删除这两个包对应的原版 Store `*_License1.xml`（未修改的电源/电池/风扇/灯效/超频 `.appxbundle` 与其原版 Store `.xml` 授权保持原封不动）；顺带修复原版 `uninstallDCHUService.bat` 中 `sc detele CCDCHUService` 的错别字。

### Step 4：组装安装与历史残余修复包（目录版 + 单文件 SFX）
构建输出目录 `*_NoHotkey\`（含 `Install.bat`、`Uninstall.bat`、`.cer`、`scripts\`、`Payload\`、`README.txt`）与单文件 UAC 自解压 `*_Setup.exe`：
1. **残余安全清理脚本（可参考/复用 [`tools/Common_Clean.ps1`](tools/Common_Clean.ps1)）**：
   - 停止所有 Clevo / Hotkey 进程；
   - 安全遍历 `{4d36e96b-e325-11ce-bfc1-08002be10318}`（键盘类）、`{4d36e96f-e325-11ce-bfc1-08002be10318}`（鼠标类）及 `HKLM\SYSTEM\CurrentControlSet\Enum\*` 的 `UpperFilters` 与 `LowerFilters`：仅移除 `HKKbdFltr` / `HKMouFltr`，**强制保留 `kbdclass` 与 `mouclass` 并显式以 `[string[]]`（`REG_MULTI_SZ`）写回**；
   - 全语言兼容清理 DriverStore（解析 `pnputil /enum-drivers` 中英文全半角冒号 + 扫描 `C:\Windows\INF\oem*.inf` 内容标记 `HKKbdFltr.sys`/`HKMouFltr.sys`/`ACPI\CLV0001`/`ACPI\CLV0002`，执行 `pnputil /delete-driver <oem.inf> /uninstall /force`）；
   - 停止并删除 `HKClipSvc`、`HKKbdFltr`、`HKMouFltr`、`CCDCHUService`、`Xtu3Service`，清理残留 `System32\drivers\HK*.sys`、`C:\ccfw\FKeyDriver.zip`、`C:\ComboKey`、`C:\Program Files (x86)\ControlCenter`、`HKLM\SOFTWARE\ControlCenterAP`、`AcpiBridge\Parameters\AppSettings`、旧 `CLEVOCO.*` UWP 与异常 `Run` 启动项。
2. **安装执行主流程（对齐官方 `Setup.rul` 并兜底 UWP 可用性）**：
   - 导入自签名 `.cer` 到 `LocalMachine\Root` 与 `TrustedPeople`，确保 `AllowAllTrustedApps = 1`、`FirstLogonDelay = 60`；
   - 复制干净 Payload（含根目录 `oem.ini` 与 XTU MSI，不含 `Driver\` 和 `AppInstall\Flexikey\`）到程序硬编码目录 `C:\Program Files (x86)\ControlCenter\`；
   - 部署 Intel XTU 运行时（非 Intel 平台非致命容错）、执行 `PreCC30.exe` 与 `EventLogSize.bat`、`pnputil /add-driver AcpiBridge.inf /install` & `AcpiBridge1.Inf`；
   - 执行去热键版 `RunAutoInstall.exe`；完成后逐一核验当前用户的 `CLEVOCO.FnhotkeysandOSD` 与 `CLEVOCO.ControlCenter3.0`（若状态缺失或非 `Ok`，兜底运行 `Add-AppxPackage -ForceApplicationShutdown`），通过 `clevofnkey:` 启动后台托盘，打印自检报告并提示重启一次。
3. **编译单文件自解压 `*_Setup.exe`**：
   - 用 `csc.exe` 编译带 UAC 提权（非 `--extract` 时自动 `runas`）、支持 `--uninstall` / `--silent` / `--extract <dir>` 与尾部魔数偏移的轻量自解压器，嵌入 `icon_tray.ico` 并追加完整包 ZIP 负载。

### Step 5：必做验收门禁（全部实跑并通过后才可交付）
1. **IL 与禁用物清零检查**：所有改动 `.exe` 通过 `PEVerify`（无新增错误）；全包目录及所有内部 `.appx` 遍历扫描，确认零 `HKKbdFltr`、`HKMouFltr`、`HKClipSvc`、`HKFltrInstaller`、`HKFltrLib`、`kb.dll`、`CustomCapability.sccd`、`Flexikey.appxbundle`。
2. **原版驱动哈希比对**：核对 `Payload\` 下 `AcpiBridge.inf/.sys/.cat` 与 `AcpiBridge1.Inf/.sys/.cat` 的 SHA-256 与原始包完全一致。
3. **APPX 结构与签名检查**：对重建的 `_x64.appx` 调用 COM `IAppxFactory::CreatePackageReader` 验证通过，对改过的 `.appxbundle` 与至少一个未改动包运行 `Get-AuthenticodeSignature` 核验。
4. **脚本与 SFX 还原一致性检查**：全部 `.ps1` 通过 `[System.Management.Automation.Language.Parser]::ParseFile`；实测运行 `*_Setup.exe --extract <temp>` 后对比源目录全部文件 SHA-256 100% 一致，随后清理临时测试目录，只据实汇报真实路径与实测输出。

---

## Mode B：仅修复已损坏 PC 的急救模式步骤（不重打包）

当用户仅需解决“之前手动删驱动后键鼠失灵 / 解锁弹 Explorer / 旧版卸载不净”时执行：
1. 生成或直接调取 [`tools/Common_Clean.ps1`](tools/Common_Clean.ps1)，向用户说明其将操作的注册表项（`UpperFilters`/`LowerFilters`）、服务（`HKClipSvc`、`HKKbdFltr`、`HKMouFltr`、`CCDCHUService`）与 DriverStore 包，**确认后执行（或请用户以管理员运行）**。
2. 验证键盘类 `{4d36e96b-...}` 与鼠标类 `{4d36e96f-...}` 下的 `UpperFilters` 已不含 `HKKbdFltr`/`HKMouFltr` 且保留 `kbdclass`/`mouclass`（`REG_MULTI_SZ`），且 `CCDCHUService` 已停止删除、`oem*.inf` 已清除。
3. 提醒用户重启电脑一次使输入类滤镜链与服务状态完全刷新生效。
