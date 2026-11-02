> 历史文档：旧的后端版本接口、自动下载与自动安装流程已停用。当前方案以 [客户端更新](client-updates.md) 和 [发布流程](release.md) 为准，下文不作为现行操作指引。

# Windows 自动更新修复方案

## 问题描述

之前的 Windows 自动更新存在以下问题：
- ⚠️ 更新时提示：`PathAccessException: Cannot open file` (OS Error: 另一个程序正在使用此文件)
- ⚠️ 无法替换正在运行的 DLL 和 EXE 文件
- ⚠️ 跳过了多个关键文件，导致更新后仍然是旧版本

## 解决方案

采用独立更新器（Updater）模式，流程如下：

```
┌─────────────────┐
│   主应用运行    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  检测到新版本   │
│  下载更新包     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  解压到临时目录  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 启动独立更新器   │
│ (PowerShell)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   主应用退出    │ ← exit(0)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  更新器等待3秒  │
│  确保进程结束   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  复制新文件到   │
│   安装目录      │
│ （可以替换DLL） │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  清理临时文件   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  启动新版应用   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  更新器自动退出  │
└─────────────────┘
```

## 核心实现

### 1. 独立更新器脚本

**文件位置**: `windows/runner/updater.ps1`

这是一个独立的 PowerShell 脚本，它会：
- ✅ 等待主程序完全退出
- ✅ 强制结束任何残留进程
- ✅ 复制所有新文件到安装目录（可以覆盖正在使用的文件）
- ✅ 清理临时更新目录
- ✅ 重新启动应用
- ✅ 记录详细日志到 `安装目录/updater.log`

### 2. AutoUpdateService 修改

**文件位置**: `lib/services/auto_update_service.dart`

主要修改：
- ✅ 新增 `_installOnWindowsWithUpdater()` 方法
- ✅ 将更新包解压到临时目录而不是直接覆盖
- ✅ 从 assets 加载更新器脚本
- ✅ 启动 PowerShell 独立更新器
- ✅ 调用 `exit(0)` 关闭主应用

### 3. 资源配置

**文件位置**: `pubspec.yaml`

添加了更新器脚本作为 asset：
```yaml
assets:
  - windows/runner/updater.ps1
```

## 优势

### ✅ 完全解决文件锁定问题
- 主程序退出后，所有 DLL 和 EXE 文件都被释放
- 更新器可以无障碍地替换所有文件

### ✅ 可靠的更新流程
- 独立进程，不受主程序影响
- 详细的日志记录便于排查问题
- 失败时可以重试或手动更新

### ✅ 用户体验良好
- 自动下载 → 自动安装 → 自动重启
- 后台静默执行（PowerShell 隐藏窗口）
- 无需用户干预

### ✅ 安全可靠
- 解压前验证压缩包
- 创建临时目录避免污染
- 失败时保留原文件
- 更新完成后自动清理

## 使用说明

### 前提条件

1. 确保 PowerShell 可用（Windows 默认安装）
2. 更新包格式为 `.zip` 文件
3. 后端提供正确的下载链接

### 触发更新

1. **自动更新**（如果开启）
   ```dart
   AutoUpdateService().setEnabled(true);
   ```

2. **手动更新**
   ```dart
   await AutoUpdateService().startUpdate(
     versionInfo: versionInfo,
     autoTriggered: false,
   );
   ```

### 监控更新状态

```dart
// 监听更新进度
AutoUpdateService().addListener(() {
  final service = AutoUpdateService();
  print('更新进度: ${service.progress}');
  print('状态信息: ${service.statusMessage}');
  print('是否需要重启: ${service.requiresRestart}');
});
```

### 查看更新日志

更新器会在安装目录生成详细日志：
```
<安装目录>/updater.log
```

日志包含：
- 📝 每个文件的复制结果
- ⚠️ 失败文件列表
- 🚀 应用启动状态
- 📊 更新统计信息

## 测试步骤

### 1. 准备测试环境

```bash
# 构建当前版本（例如 1.0.5）
flutter build windows --release

# 修改版本号到 1.0.6
# 编辑 pubspec.yaml: version: 1.0.6+6

# 构建新版本
flutter build windows --release

# 打包成 ZIP
cd build/windows/x64/runner/Release
Compress-Archive -Path * -DestinationPath ../windows-1.0.6.zip
```

### 2. 部署到后端

将 `windows-1.0.6.zip` 上传到后端的 `/update/` 目录，并更新版本接口返回：

```json
{
  "version": "1.0.6",
  "forceUpdate": false,
  "downloadUrl": "/update/1.0.6/windows-1.0.6.zip",
  "windows": "/update/1.0.6/windows-1.0.6.zip"
}
```

### 3. 运行旧版本测试

1. 运行 1.0.5 版本
2. 开启自动更新
3. 应用会自动检测到新版本
4. 开始下载 → 解压 → 启动更新器 → 自动退出
5. 等待 3-5 秒，应用应该自动重启
6. 检查版本号是否为 1.0.6

### 4. 验证更新结果

```powershell
# 查看更新日志
Get-Content "build/windows/x64/runner/Release/updater.log" -Tail 50

# 确认版本号
# 在应用的"关于"页面查看
```

## 故障排查

### 问题：应用没有自动重启

**可能原因**:
- 更新器脚本执行失败
- 主程序路径错误

**解决方法**:
1. 查看 `updater.log`
2. 手动启动主程序
3. 检查脚本权限

### 问题：更新后仍然是旧版本

**可能原因**:
- 文件复制失败
- 目录结构不匹配

**解决方法**:
1. 查看 `updater.log` 中的失败文件列表
2. 确认压缩包结构正确
3. 手动解压测试

### 问题：PowerShell 执行策略错误

**错误信息**: `无法加载，因为在此系统上禁止运行脚本`

**解决方法**:
```powershell
# 管理员身份运行 PowerShell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

注意：代码中已经使用了 `-ExecutionPolicy Bypass` 参数，通常不会遇到此问题。

## 未来改进

### 可能的增强功能

1. **断点续传**
   - 大文件下载失败时可以恢复
   
2. **差异更新**
   - 只下载变化的文件，减少更新包大小
   
3. **回滚机制**
   - 更新失败时自动回滚到旧版本
   
4. **更新前备份**
   - 自动备份当前版本，便于恢复

5. **更新器自更新**
   - 允许更新器脚本本身也能被更新

## 参考资料

- [PowerShell 文件操作](https://docs.microsoft.com/powershell/scripting/samples/working-with-files-and-folders)
- [Flutter Asset 管理](https://docs.flutter.dev/development/ui/assets-and-images)
- [Windows 进程管理](https://docs.microsoft.com/windows/win32/procthread/processes-and-threads)

## 版本历史

- **2024-11-22**: 初始版本，实现独立更新器机制

