
# Cyrene Music 🎵

一个功能完善的跨平台音乐播放器，使用 Flutter 开发。


> [!CAUTION]
> 根据版权合规要求，项目已经移除了内置音源，您需要先导入音源才能正常使用！兼容洛雪音源，TuneHub，OmniParse。



## 📱 支持平台

- ✅ Windows
- ✅ Android
- ✅ Linux
- ✅ macOS
- ✅ iOS

## 🚀 快速开始

### 下载预编译版本

前往 [Releases](https://github.com/your-repo/releases) 页面下载对应平台的安装包。

### 本地开发运行

```bash
# 安装依赖
flutter pub get

# 运行应用（自动选择连接的设备）
flutter run

# 指定平台运行
flutter run -d windows
flutter run -d linux
flutter run -d macos
flutter run -d android
```

项目固定使用 Flutter 3.41.3。Windows 开发环境推荐使用 Puro；项目脚本会将仍位于系统盘的
Puro、Pub、Gradle 和 Android 缓存重定向到项目所在盘的 `DevTools` 目录。也可通过
`CYRENE_DEV_ROOT` 指定其他非系统盘目录。

```powershell
# 完整质量检查：锁定依赖、静态分析、格式检查、单元测试
.\scripts\quality_check.ps1

# 构建可分发的 Android 测试包
.\scripts\build_test.ps1 -Target android

# 同时构建 Android 与 Windows 测试包
.\scripts\build_test.ps1 -Target all

# 启动 API 36 横屏 Pad（1920x1080）并运行应用，模拟车机中控屏
.\scripts\run_android_car.ps1
```

测试产物及 SHA-256 清单写入 `artifacts/test`，该目录不会提交到 Git。

### 手动构建

```bash
# Windows
flutter build windows --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release

# Android APK
flutter build apk --release --split-per-abi

# iOS (需要 macOS)
flutter build ios --release
```

### 自动构建（GitHub Actions）

推送版本标签即可自动构建所有平台：

```bash
git tag v1.0.4
git push origin v1.0.4
```

详细说明请查看 [GitHub Actions 构建指南](docs/GITHUB_ACTIONS_BUILD.md)。

### 后端运行

```bash
cd backend

# 安装依赖
bun install

# 启动服务器
bun run src/index.ts
```
