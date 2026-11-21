# Lynx 云构建（公开）

本仓库只放构建工装：源码包由 workflow 从交付 URL 拉取，在 GitHub Actions 的
macOS runner（预装完整 Xcode，含 SwiftUIMacros 插件）上编译并跑 46 项单测，
成功后把 `Lynx.app` 发布为 Release 资产。本地无需安装 Xcode。

## 取成品

1. Releases 页下载最新 `Lynx-app.zip`（或 Actions run 的 artifact）；
2. 解压得 Lynx.app；若 Gatekeeper 拦截：
   `xattr -dr com.apple.quarantine Lynx.app`，或右键 → 打开。

## 重新构建 / 换源码包

Actions → Build Lynx.app → Run workflow，可填新的源码包 zip URL；
默认 URL 指向最新交付包。push 到 main（除 ci-logs/README）也会触发。

## 失败自诊

构建或测试失败时，workflow 自动把 build.log / test.log 提交到 `ci-logs/`，
供无人值守排查；该提交不会触发新 run。

## 说明

- runner 为 arm64（macos-15），产物适配 Apple Silicon，部署目标 macOS 14+；
- ad-hoc 签名仅供本机运行；分发需 Developer ID + 公证；
- 旧私有仓库 AIMX210/lynx 已被本公开仓库取代，可手动删除。
