# 蓝天（Clevo）Control Center 去热键驱动 · 开源 Prompt 仓库

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **核心理念**：不分发任何厂商闭源二进制，而是提供一套通用的 **AI Agent 改造步骤规范（[`PROMPT.md`](PROMPT.md)）** 与 **无 SDK 签名封包伴随工具（[`tools/`](tools/)）**，让 AI 针对你手中任意蓝天公模机型、任意版本的官方 Control Center 安装包，现场完成“去热键驱动 + 隐藏前端 UI + 修复历史故障 + 重打包签名”。

> 🤖 **AI Agent Notice**: If a user gave you this repository URL to process their Clevo Control Center installer, follow the **Agent Instructions** section below (`给 AI Agent 的操作指引`) and execute [`PROMPT.md`](PROMPT.md) (Chinese) or [`PROMPT_EN.md`](PROMPT_EN.md) (English) step by step.

---

## 第一部分：给用户看的使用指南

### 1. 这个项目解决什么问题？
蓝天公模笔记本（七彩虹、神舟、机械革命、雷神、Sager、XMG、Schenker 等）官方 Control Center 常因自带热键内核过滤驱动（`HKKbdFltr.sys` / `HKMouFltr.sys`）引发系统蓝屏；而手动删除驱动后又极易出现以下连环后遗症：
- **键鼠直接失灵**：只删 `.sys` 未同步剔除注册表 `UpperFilters` 中的 `HKKbdFltr` / `HKMouFltr`（或破坏了原生 `kbdclass` / `mouclass`）。
- **每次解锁屏幕都弹出资源管理器（Explorer）**：`AcpiBridge1.Inf` 注册的 `CCDCHUService`（`DCHUService.exe`）在锁屏解锁时调用 `LaunchFnkey.exe` 执行 `explorer.exe shell:appsFolder\CLEVOCO.FnhotkeysandOSD_...!App`，且原版卸载脚本自带 `sc detele` 拼写错别字导致卸载不净；当 `FnKey` UWP 缺失/损坏时，Windows 会回退弹出普通“此电脑/文件资源管理器”窗口。
- **Control Center 无法打开或功能瘫痪**：直接阉割服务或缺少替代桩会导致电源模式、风扇策略、电池保护及控制中心界面整体不可用。

**通过本仓库处理后，你将得到一个定制重打包的干净安装包**：
- 彻底移除热键滤镜驱动、服务、`kb.dll`、`FKeyDriver.zip` 与 Flexikey 代码/UI；
- **原封不动保留**微软签名的 `AcpiBridge` / `AcpiBridge1` 硬件控制驱动、OLED 防烧唤醒、Per-Key RGB 灯效、风扇/电源模式/电池保护等核心功能；
- 自带安装前残余急救清理、修复版防解锁弹窗的 `LaunchFnkey.exe`，以及重新签名好的 `.appxbundle` 与单文件 `*_Setup.exe`。

### 2. 用户如何使用？（最省事用法）
**用法 A（推荐）：直接把本仓库地址 + 你的官网安装包路径发给你的 AI Agent**（支持 Antigravity、Claude Code、Codex、Cursor、Gemini CLI 等可运行本地终端的 Agent），例如：
> 请参考这个仓库 `https://github.com/sylw114/clevo-cc-dehotkeys-prompt`，把我电脑上的蓝天官方安装包 `D:\Downloads\07_CC30.rar` 去掉热键驱动和相关界面/代码并重新打包成可用安装包。

**用法 B：仅修复已经损坏的电脑（不重装控制中心）**
> 请参考这个仓库 `https://github.com/sylw114/clevo-cc-dehotkeys-prompt` 的 Mode B，检查并帮我安全清理电脑里残留的蓝天热键驱动、`UpperFilters` 和解锁自动弹资源管理器问题。

### 3. 本地环境准备（运行重打包 Agent 所在电脑需要）
- Windows 10 / Windows 11，已安装 `.NET Framework 4.x`（系统自带 `ilasm.exe`、`csc.exe`）
- Python 3.x
- `ildasm.exe` 与 `PEVerify.exe`（通常来自 Visual Studio 或 .NET Framework SDK Tools；若本地缺失，Agent 会提示你先安装）
- **无需安装庞大的 Windows 10/11 SDK**（本仓库 `tools/` 内置纯 Python APPX 打包与原生 `AppxSip.dll` 签名工具）

---

## 第二部分：给 AI Agent 的操作指引（Agent Instructions）

当你作为 AI Agent 接收到本仓库链接或目录时，请按以下规则路由与执行：

1. **先明确用户意图与输入**：
   - 若用户要求**重打包去热键版安装包（Mode A）**但尚未给出官网安装包本地路径（`.rar` / `.zip` / `.exe` / 已解压目录），**先向用户询问路径**，不要凭空猜测或虚构安装包位置。
   - 若用户仅需**修复现有系统故障（Mode B：键鼠异常 / 解锁弹 Explorer / 卸载残留）**，转至步骤文档中的 Mode B 流程。
2. **获取完整仓库并读取对应语言的操作步骤文档，按步执行**：
   - 若当前仅拿到了仓库 URL，建议先执行 `git clone https://github.com/sylw114/clevo-cc-dehotkeys-prompt` 到本地临时目录，以便直接调用 `tools/` 下全部脚本。
   - 中文环境读取：[`PROMPT.md`](PROMPT.md)
   - English environment: read [`PROMPT_EN.md`](PROMPT_EN.md)
3. **优先直接复用仓库 [`tools/`](tools/) 下已验证的工具脚本（避免重复造轮子与踩坑）**：
   - [`tools/decrypt_clevo_inx.py`](tools/decrypt_clevo_inx.py)：用于解密蓝天 InstallShield `setup.inx`，提取官方 `Setup.rul` 安装/卸载流程。
   - [`tools/appx_repacker.py`](tools/appx_repacker.py)：已内置 `zlib.Z_FULL_FLUSH` 64 KB 独立分块与 `urllib.parse.unquote` BlockMap 路径解码，用于重构并更新 `.appx` / `.appxbundle`（含 `scale-*.appx` 分包重签及 `AppxBundleManifest.xml` 偏移计算）。
   - [`tools/sign_appx.ps1`](tools/sign_appx.ps1)：用于生成与 `AppxManifest.xml` 的 `Publisher` 一致的自签名证书，并通过 `SignerSignEx2` + 系统内置 `AppxSip.dll` 对 `.appx` / `.appxbundle` 进行原生签名。
   - [`tools/Common_Clean.ps1`](tools/Common_Clean.ps1)：已封装全语言兼容的 `pnputil` + `C:\Windows\INF\oem*.inf` 扫描清理、`UpperFilters`/`LowerFilters`（保留 `kbdclass`/`mouclass` 并保持 `REG_MULTI_SZ`）及 `CCDCHUService` 清理函数；可直接复用到目标安装包 `scripts\` 中，或经用户确认后执行 `-RunRepair`。
   - **重要**：即使通过网页抓取未能下载 `tools/`，[`PROMPT.md`](PROMPT.md) / [`PROMPT_EN.md`](PROMPT_EN.md) 内仍保留了完整底层算法与 Win32 接口规格，你也可以据此自行生成等效实现。
4. **安全与验证铁律**：
   - **严禁硬编码**：禁止照搬示例行号、局部变量编号或固定文件夹名，必须以当前解压/反编译结果动态匹配修改；
   - **保护工作环境**：重打包构建与校验全部在独立输出/工作目录内完成，**不得未经用户明确同意就在当前系统静默执行安装驱动、删除驱动或修改宿主系统注册表/UWP**；
   - **如实汇报验证门禁**：必须实际跑通 `PEVerify`（脱离 `kb.dll`/`HKFltrLib.dll` 验证）、`IAppxFactory::CreatePackageReader`、全包禁用文件名扫描、保留 `.sys`/`.cat` 哈希比对与 SFX 解包校验后再输出成品路径。

---

## 目录结构

| 路径 | 面向读者 | 说明 |
| --- | --- | --- |
| [`README.md`](README.md) / [`README_EN.md`](README_EN.md) | 用户 + Agent 入口 | 背景介绍、使用方法与给 Agent 的自动路由指引 |
| [`PROMPT.md`](PROMPT.md) / [`PROMPT_EN.md`](PROMPT_EN.md) | AI Agent 核心执行步骤 | 跨版本通用动态分析、IL 手术、封包签名、安装器生成与门禁验证详细步骤 |
| [`tools/`](tools/) | AI Agent / 高级用户 | 可直接调用的 `.inx` 解密、`appxbundle` 打包、`AppxSip` 签名与残余修复工具 |
| [`LICENSE`](LICENSE) | 所有人 | MIT 开源协议 |

---

## 免责声明
本仓库仅提供通用 AI Agent 工程指令、技术原理说明与纯开源辅助脚本，**不包含、不分发任何第三方厂商（Clevo / Insyde / Intel / AMD / Microsoft）受版权保护的文件或签名证书**。操作内核驱动、系统注册表与安装包前请做好重要数据备份。
