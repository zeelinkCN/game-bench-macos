# 开发计划

## 明日：Apple TV / tvOS

1. 在 Apple TV 的“设置 → 通用 → 关于本机”确认型号与 tvOS 版本。
2. 安装完整 Xcode 和 tvOS 平台组件，在同一网络配对 Apple TV。
3. 新建 tvOS target，复用 libretro 核心、目录模型、存档与作弊层。
4. 把 macOS 的 AppKit 交互替换为 tvOS 焦点导航和全屏播放器。
5. 在真机测试 Xbox、Switch Pro／Joy-Con、双人输入、声音和休眠恢复。
6. 使用 Personal Team 做首次私有安装；需要长期更新时配置 Developer Program / TestFlight。

首次配对需要用户在电视上显示验证码并在 Mac 确认。完成配对和签名后，可以在
同一局域网内从 Mac 构建并推送后续更新。
