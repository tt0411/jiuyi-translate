# 开发与发布

## 环境

- macOS 15+，Xcode 16+，Swift 6，macOS SDK。
- Swift Package Manager，无第三方包。
- `hdiutil`、`ditto`、`iconutil`、`codesign` 和 `shasum` 由 macOS/Xcode 提供。

## 开发构建

```bash
swift build
bash scripts/build.sh
open "dist/啾译.app"
```

仅在构建工具运行于不允许嵌套沙盒的受限环境时，可在脚本后传 `--disable-sandbox`。它只影响 SwiftPM 构建过程，不改变系统安全设置或应用权限。

## 架构与 DMG

```bash
# 默认构建当前机器架构的 .app
bash scripts/build.sh

# 指定单架构
BUILD_ARCH=arm64 bash scripts/build.sh
BUILD_ARCH=x86_64 bash scripts/build.sh

# 默认构建 Universal DMG、ZIP、SHA-256 校验文件
bash scripts/package.sh
```

Universal 分别编译 arm64 和 x86_64，再通过 `lipo` 合并。打包脚本在 `dist/` 下使用临时目录，校验签名后替换旧构建，避免混入历史资源。DMG 包含应用、Applications 快捷入口、安装说明和离线帮助。产物不进入 Git，只作为 Release 附件上传。

Intel 二进制可构建不等于完成 Intel 实机验证。发布说明必须保留该限制，直到有实机测试记录。

## 图标

图标为仓库内 Swift 脚本绘制的原创矢量图形，不依赖外部素材。

```bash
mkdir -p .build/AppIcon.iconset
xcrun swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
cp .build/AppIcon.iconset/icon_256x256@2x.png Resources/AppIcon.png
```

## 签名与公证

默认使用临时签名，未公证。不要将 iOS Distribution、Apple Development 或临时签名误写成“已公证分发版”。

如已有有效的 **Developer ID Application** 证书，可在环境变量 `SIGNING_IDENTITY` 中设置证书名或指纹后运行构建；脚本会启用 hardened runtime 和安全时间戳。不要将私钥、证书密码、API Key 写进仓库。

正式公证流程：Developer ID 签名 → 向 Apple 提交应用或 DMG → 等待 Accepted → staple 公证票据 → 验证 Gatekeeper → 重新计算 SHA-256。构建脚本仅完成签名，不自动执行公证；未完成上述步骤时始终保留未公证提示。公证时认证信息由环境变量或钥匙串配置提供。

## 发布前检查

1. 更新 `Resources/Info.plist` 的版本和构建号、`CHANGELOG.md`、`docs/RELEASE_NOTES.md`。
2. 运行 `bash scripts/package.sh`，确认 `codesign --verify --strict`、`hdiutil verify`、ZIP 校验通过。
3. 检查 `lipo -archs dist/啾译.app/Contents/MacOS/SelectionTranslate`，Universal 应含两种架构。
4. 实测：启动、手动粘贴、中英互译、长文滚动、辅助功能取词、网页复制兜底、设置入口；自启动需单独进行注销/登录测试。
5. 确认 DMG 拖拽安装、安装说明及帮助页面正确。记录哪些平台或流程尚未实测。
6. 确认签名/公证声明与实际一致，确认源码许可证已由项目所有者选择。

## GitHub

初次发布需先创建公开仓库、确认源码许可证，并在本机执行 `gh auth login` 完成身份验证。不要向他人发送登录令牌。

代码推送或 PR 触发构建检查；推送 `v版本号` 标签会创建**未发布的预览 Release 草稿**，包含 DMG、ZIP、校验文件。标签必须与 Info.plist 版本一致，所有自动产物默认采用临时签名。

维护者在 GitHub 检查 Release 草稿、说明和附件后发布。手动构建可在 Actions 运行工作流并下载 artifact。当前没有自动更新服务；用户从 Releases 手动更新。

若工作流产物已接受额外签名或公证处理，不要直接复用旧校验文件，应重新生成校验和。
