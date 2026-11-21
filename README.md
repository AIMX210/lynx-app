# Lynx

原生 macOS SSH 服务器管理工具：监控、终端、文件、Docker、进程与端口转发，
全部复用同一条 OpenSSH 长连接，以**最低系统占用**为第一设计目标。纯 Swift / SwiftUI 编写。

## 功能一览

- **仪表盘**：统计三卡 + 标签过滤 + 无按钮服务器卡片（CPU / 内存环形表、网络趋势、磁盘用量、
  GPU、负载、运行时间），连接状态一目了然；右键连接 / 断开 / 终端 / 编辑 / 删除。
- **服务器详情**：概览 / 终端 / 文件 / Docker / 进程五个标签，头部只承载身份与状态。
  - **概览**：CPU 逐核竖条、内存三段条（已用 / 缓存 / 空闲）、负载、网卡与磁盘 IO 速率、
    挂载点用量、NVIDIA GPU（占用 / 显存 / 温度 / 功耗）、系统信息。
  - **终端**：多会话标签、片段菜单注入、状态侧栏（`⌥⌘I`）、字号 `⌘+` / `⌘-`、
    多套配色在设置中切换、会话结束可重连。
  - **文件**：路径栏（上级 / 主目录 / 路径框 / 刷新，`⇧⌘G` 聚焦），排序、双击进入 / 编辑、
    拖拽上传、新建 / 重命名 / 权限 / 删除（恒确认）、2MB 以内文本编辑（超限只读防截断覆盖）。
  - **Docker**：引擎卡 + 状态堆叠条；容器启停 / 重启 / 日志查看复制；容器与镜像删除（恒确认）。
  - **进程**：按 CPU / 内存 / RSS 等排序、搜索、SIGTERM / SIGKILL（恒确认）。
- **命令片段**：编辑、注入指定服务器终端、多选批量执行（并发 4、未连接自动先连、
  逐台结果与退出码、可中途停止）。
- **端口转发**：`-L` / `-R` / `-D` 规则管理，开关即时生效，连接后可自动启动。
- **SSH 密钥**：扫描 `~/.ssh`、生成 Ed25519（600 权限）、导入本机私钥、复制公钥、
  一键安装到已连接服务器的 `authorized_keys`、在 Finder 中定位、删除。
- **认证**：密码 / 密钥口令 / 键盘交互（OTP）/ 主机指纹确认，统一认证窗口；
  凭据只存系统 Keychain。
- **安全**：Touch ID / 设备密码启动锁与手动锁定（`⌃⌘L`）；主机密钥 TOFU 或严格模式；
  密钥变更一律拒绝并警示中间人风险。
- **数据**：JSON 原子写入 + 防抖保存；导出 / 导入（不含凭据）；`~/.ssh/config` 一键导入去重分组。
- **菜单栏**：可选迷你监控面板，标题显示首台就绪服务器的 CPU 与网速。

Lynx 刻意不做的事（保持精简）：iCloud 同步、Mosh、Windows 远端监控、Docker Compose 编排、
主题式功能堆砌。macOS 远端为基础指标口径（CPU / 内存 / 负载 / 网络 / 存储）。

## 低占用架构

- **一台服务器 = 一条连接**：系统 OpenSSH `ControlMaster` 长连接（`ssh -N -M -S socket`）。
  终端、监控、文件、Docker、进程、端口转发全部走这条连接的复用通道，不重复握手、不额外驻留进程；
  转发用 `ssh -O forward/cancel` 即时生效，零新增进程。
- **窗口不可见即暂停**：未开菜单栏时，窗口被遮挡 / 最小化即暂停全部轮询，CPU 趋近于零；
  开启菜单栏则保持轻量轮询（2 秒刷新标题）。
- **轻量渲染**：趋势图用 SwiftUI `Canvas` 手绘 sparkline（不引入图表框架），
  历史环形缓冲 240 点，列表 `LazyVGrid` / `Table` 虚拟化。
- **轮询错峰**：每台服务器独立协程 + 随机抖动，避免同时采集造成尖峰。
- **流式传输**：上传下载恒定 64KB–256KB 缓冲，内存不随文件大小增长。

## 代码架构

```
Lynx/
├── Package.swift              # LynxCore 恒在；Lynx 应用层仅 macOS 编译
├── Sources/
│   ├── LynxCore/              # 纯 Foundation 逻辑层（跨平台，可单测）
│   │   ├── Models.swift            # 服务器 / 片段 / 转发 / 密钥 / 指标 / 连接状态模型
│   │   ├── RemoteScripts.swift     # 远端 POSIX sh 采集与操作脚本（免安装）
│   │   ├── MetricsParser.swift     # 行协议解析 + 差分速率计算
│   │   ├── TextParsers.swift       # ps / docker / ls(GNU|BSD) 输出解析
│   │   ├── SSHConfigAndPrompts.swift # ssh_config 解析 + 认证提示状态机
│   │   ├── SSHCommandBuilder.swift   # OpenSSH argv 构造（master/exec/forward）
│   │   ├── ExecRunner.swift        # 异步进程执行器（阻塞读 + 流式传输 + 超时/取消）
│   │   ├── FileStore.swift         # JSON 持久化与合并
│   │   └── Utilities.swift         # Shell 引用 / 路径 / 格式化
│   └── Lynx/                  # macOS 应用层（SwiftUI + AppKit + 终端 + Keychain）
│       ├── LynxApp.swift       # @main、菜单命令、生命周期
│       ├── AppState.swift      # 根状态：导航 / 会话 / 锁定 / 菜单栏 / 暂停策略
│       ├── ConnectionPool.swift / SSHConnection.swift  # ControlMaster 连接池与状态机
│       ├── MonitorService.swift      # 抖动轮询、差分、暂停
│       ├── RemoteServices.swift      # 文件 / Docker / 进程 / 片段 / 密钥安装
│       ├── TerminalSession.swift / TerminalThemes.swift / TerminalPane.swift / TerminalInspector.swift
│       ├── Store.swift / Settings.swift / Keychain.swift
│       └── 各功能视图（仪表盘 / 详情 / 概览 / 文件 / Docker / 进程 / 片段 / 转发 / 密钥 / 设置 / 认证 / 锁）
├── Tests/LynxCoreTests/       # 46 项单元测试
├── Tools/UIShim/              # Linux 类型级验证用 shim 模块（不参与 macOS 构建）
├── Resources/                 # Info.plist + 图标
└── scripts/
    ├── build_app.sh           # macOS 一键构建 .app
    └── typecheck_ui.sh        # Linux 类型级 UI 签名校验
```

- **LynxCore**：不依赖任何 Apple UI 框架，模型、远端脚本、解析器、命令构造与 exec 运行器
  全部可在 Linux 上独立构建与单元测试。
- **Lynx**：macOS 应用层，`#if os(macOS)` 条件编译；在 Linux 构建中不参与编译，
  改由 `Tools/UIShim` 提供签名对齐的桩模块做类型级校验。

## 依赖

唯一直接第三方依赖是终端仿真库
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)（MIT 许可证，v1.9.0，
以 revision `8840e3596739adfe9599c0e7fff89f4fa88bedcf` 锁定 tag 同一份代码）。
SwiftTerm 自身以 revision 锁 `swift-subprocess`，SPM 禁止「稳定版根依赖指向不稳定版
传递依赖」边，故根包对 SwiftTerm 同样使用 revision 锁定（内容确定、不漂移）。
`swift-system`、`swift-argument-parser`、`swift-subprocess` 均为 SwiftTerm 的传递依赖。

## 构建与运行（macOS）

- **系统要求**：macOS 15 或更高；完整安装 Xcode 16+（Swift 5.9+ 工具链）。
  仅装 Command Line Tools 不够：SwiftUI 的 `@State` 等宏插件 `libSwiftUIMacros.dylib`
  只随完整 Xcode 附带，CLT 缺失会产生连锁编译错误；`scripts/build_app.sh` 已含预检与指引。
- Package.swift 声明的部署目标为 macOS 14。

```bash
./scripts/build_app.sh          # release 构建并组装 build/Lynx.app（含图标、ad-hoc 签名）
open build/Lynx.app
```

也可以直接用 Xcode 打开 `Package.swift` 运行 `Lynx` target。

首次运行若被 Gatekeeper 拦截：`xattr -dr com.apple.quarantine build/Lynx.app`，或右键 → 打开。
正式分发请改用 Developer ID 签名并公证。

> Lynx 是非沙盒应用：它需要执行 `/usr/bin/ssh`、读取 `~/.ssh` 与访问 Keychain，
> 这些能力无法在 App Sandbox 内实现。

## Linux 上的验证（CI 与本地复跑）

逻辑层在 Linux（Swift 6.0.3）上构建并跑全部单元测试；应用层在 Linux 上走 shim 类型级校验。

```bash
export PATH=/home/user/vm/toolchain/usr/bin:$PATH

# 1. UI 类型级校验：七个 shim 模块 + 真实 LynxCore 对全部应用源文件做整模块 swiftc -typecheck
scripts/typecheck_ui.sh        # 末尾输出 UI_TYPECHECK_OK

# 2. 构建（含测试 target）
swift build --build-tests

# 3. 运行单元测试（46 项）
.build/x86_64-unknown-linux-gnu/debug/LynxPackageTests.xctest
```

测试覆盖：指标解析 / 差分、ps / docker / ls 解析、`ssh_config` 解析、认证提示识别、
命令构造、ExecRunner 超时 / 取消 / 大输出 / 二进制流，以及真实 `/proc` 采集脚本端到端。

## CI

GitHub Actions 在 `macos-15`  runner 上执行：还原图标（仓库内 base64 sidecar 解码为 PNG，
校验 PNG 签名）→ 选择 Xcode → `scripts/build_app.sh release` 构建 `Lynx.app` → `swift test`
跑单元测试 → `ditto` 打包（zip 兜底）→ 上传 artifact 并发布 release；
失败时上传构建 / 测试 / 打包 / job 日志，状态写入 `ci-logs/status.json`。

## 安全设计

- 密码与密钥口令**只存系统 Keychain**（本设备、解锁后可用、不同步），
  数据文件与导出内容永远不含凭据。
- 远端命令全部经 Shell 引用单引号安全转义，路径注入免疫。
- 主机密钥默认 TOFU（首次自动信任），密钥变更一律拒绝并提示清理 `known_hosts`；
  可选严格模式逐台确认指纹。
- 破坏性操作（删除服务器 / 文件 / 容器 / 镜像 / 密钥、杀进程、清凭据）恒弹确认，无开关可关闭。
