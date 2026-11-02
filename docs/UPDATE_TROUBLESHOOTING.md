> 历史文档：旧的后端版本接口、自动下载与自动安装流程已停用。当前方案以 [客户端更新](client-updates.md) 和 [发布流程](release.md) 为准，下文不作为现行操作指引。

# Windows 自动更新问题排查指南

## 问题现象

更新文件只存在于临时目录（如 `updates\temp_1763794683966`），主程序目录的 exe 文件没有被替换。

## 排查步骤

### 步骤 1: 测试更新器脚本本身

首先验证更新器脚本的逻辑是否正常：

```powershell
# 在项目根目录运行
.\scripts\test_updater_directly.ps1
```

这个脚本会：
1. 创建模拟的安装目录和文件
2. 创建模拟的更新文件
3. 直接调用更新器脚本
4. 验证文件是否被正确替换

**预期结果**: 所有文件应该被成功更新，显示 "测试成功！"

**如果测试失败**: 说明更新器脚本本身有问题，请查看错误信息。

### 步骤 2: 检查更新日志

查看应用安装目录下的 `updater.log` 文件：

```powershell
# 假设应用安装在这个位置
Get-Content "D:\work\cyrene_music\build\windows\x64\runner\Debug\updater.log" -Tail 50
```

**关键信息**:
- ✅ 更新器是否成功启动
- ✅ 发现了多少个文件需要更新
- ✅ 实际的源路径和目标路径是什么
- ✅ 哪些文件复制成功，哪些失败
- ✅ 主程序是否被重新启动

### 步骤 3: 检查应用日志

在应用内查看开发者页面的日志：

**关键信息**:
- ✅ 更新器脚本的完整路径
- ✅ 传递给更新器的参数（InstallDir, UpdateDir, ExePath）
- ✅ 更新器进程是否成功启动
- ✅ 应用是否调用了 `exit(0)`

### 步骤 4: 手动运行更新器

如果自动更新失败，可以手动测试更新器：

```powershell
# 1. 找到临时更新目录（从应用日志中获取）
$updateDir = "D:\work\cyrene_music\build\windows\x64\runner\Debug\updates\temp_1763794683966"

# 2. 确认更新文件存在
Get-ChildItem $updateDir -Recurse -File | Select-Object -First 10

# 3. 手动运行更新器（先关闭应用！）
cd D:\work\cyrene_music

powershell.exe -ExecutionPolicy Bypass -File "windows\runner\updater.ps1" `
    -InstallDir "D:\work\cyrene_music\build\windows\x64\runner\Debug" `
    -UpdateDir $updateDir `
    -ExePath "D:\work\cyrene_music\build\windows\x64\runner\Debug\cyrene_music.exe" `
    -WaitSeconds 1
```

**注意**: 运行前必须完全关闭应用，否则文件会被锁定。

## 常见问题及解决方案

### 问题 1: 更新器窗口一闪而过

**原因**: 更新器脚本执行出错，PowerShell 窗口立即关闭。

**解决方法**:
1. 暂时移除 `-WindowStyle Hidden` 参数（已在最新代码中移除）
2. 在脚本末尾添加 `Read-Host "按回车键退出"` 以便查看错误

### 问题 2: 主程序没有退出

**症状**: `updater.log` 显示"检测到主程序仍在运行"

**原因**: 
- 托盘图标持有进程
- 后台服务未释放
- 窗口关闭但进程未结束

**解决方法**:
```dart
// 在 auto_update_service.dart 中，exit(0) 前添加更彻底的清理
await windowManager.destroy();
await trayManager.destroy();
await PlayerService().dispose();
exit(0);
```

### 问题 3: 路径包含中文或特殊字符

**症状**: PowerShell 无法正确解析路径

**解决方法**: 
- 确保所有路径使用反斜杠 `\`
- 路径参数使用引号包裹
- 避免在安装路径中使用中文字符

### 问题 4: 权限不足

**症状**: "拒绝访问" 或 "Access Denied"

**解决方法**:
1. 以管理员身份运行应用
2. 检查安装目录的写入权限
3. 临时关闭杀毒软件

### 问题 5: 临时目录结构不正确

**症状**: 更新器找不到文件，或者目录嵌套错误

**检查方法**:
```powershell
# 查看临时目录结构
tree /F "D:\work\cyrene_music\build\windows\x64\runner\Debug\updates\temp_xxx"
```

**预期结构**:
```
temp_xxx\
  ├─ cyrene_music.exe
  ├─ flutter_windows.dll
  ├─ data\
  │  └─ flutter_assets\
  └─ ...
```

**如果多了一层目录**（如 `temp_xxx\Release\...`），则需要修改解压逻辑。

## 调试技巧

### 1. 在更新器脚本中添加断点

```powershell
# 在关键位置添加暂停
Write-Log "即将复制文件，按任意键继续..."
Read-Host
```

### 2. 输出详细的变量信息

在 `updater.ps1` 中添加：

```powershell
Write-Log "调试信息:"
Write-Log "  `$InstallDir = $InstallDir"
Write-Log "  `$UpdateDir = $UpdateDir"
Write-Log "  Test-Path InstallDir: $(Test-Path $InstallDir)"
Write-Log "  Test-Path UpdateDir: $(Test-Path $UpdateDir)"
```

### 3. 使用 Process Monitor 监控文件操作

1. 下载 [Process Monitor](https://docs.microsoft.com/sysinternals/downloads/procmon)
2. 运行并设置过滤器：Process Name is "powershell.exe"
3. 触发更新
4. 查看 PowerShell 的所有文件操作

### 4. 检查 PowerShell 执行策略

```powershell
# 查看当前策略
Get-ExecutionPolicy -List

# 如果过于严格，临时修改
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## 改进建议

### 短期方案（立即可用）

1. **更新器显示窗口**: 移除 `-WindowStyle Hidden`，让用户看到更新过程
2. **更详细的日志**: 记录每个关键步骤的结果
3. **手动重启提示**: 如果自动重启失败，提示用户手动启动

### 中期方案（需要开发）

1. **更新前备份**: 复制当前版本到 `backup` 目录
2. **更新失败回滚**: 如果更新失败，自动恢复备份
3. **分步更新**:
   - 第一步：下载并验证
   - 第二步：关闭应用
   - 第三步：替换文件
   - 第四步：重启应用

### 长期方案（未来考虑）

1. **差异更新**: 只下载变化的文件
2. **断点续传**: 大文件下载失败可以恢复
3. **更新服务**: 使用 Windows Service 而不是 PowerShell 脚本
4. **数字签名**: 验证更新包的完整性和来源

## 成功更新的完整流程

```
用户触发更新
    ↓
下载更新包 (xxx.zip)
    ↓
解压到临时目录 (updates/temp_xxx/)
    ↓
从 assets 加载 updater.ps1
    ↓
写入到 updates/updater_xxx.ps1
    ↓
启动 PowerShell 进程执行更新器
    ↓
更新器记录: "更新器启动"
    ↓
主应用调用 exit(0) 退出
    ↓
更新器等待 3 秒
    ↓
更新器强制结束残留进程（如果有）
    ↓
更新器记录: "开始复制更新文件"
    ↓
更新器逐个复制文件到安装目录
    ↓
更新器记录: "文件更新完成"
    ↓
更新器删除临时目录
    ↓
更新器记录: "启动新版本应用"
    ↓
更新器启动应用: cyrene_music.exe
    ↓
更新器退出
    ↓
新版本应用运行
```

## 验证更新是否成功

```powershell
# 1. 检查应用版本（在应用的"关于"页面）

# 2. 检查文件时间戳
Get-ChildItem "D:\work\cyrene_music\build\windows\x64\runner\Debug\*.exe" | 
    Select-Object Name, LastWriteTime

# 3. 检查文件大小（新旧版本大小应该不同）
Get-ChildItem "D:\work\cyrene_music\build\windows\x64\runner\Debug\*.exe" | 
    Select-Object Name, Length

# 4. 检查更新日志的最后时间
Get-Item "D:\work\cyrene_music\build\windows\x64\runner\Debug\updater.log" | 
    Select-Object LastWriteTime
```

## 需要提供的调试信息

如果问题仍未解决，请提供以下信息：

1. **updater.log 的完整内容**
2. **应用日志**（开发者页面中的日志）
3. **临时目录的内容**:
   ```powershell
   tree /F "安装目录\updates"
   ```
4. **PowerShell 版本**:
   ```powershell
   $PSVersionTable.PSVersion
   ```
5. **安装目录路径**
6. **是否有杀毒软件/安全软件阻止**

## 联系支持

如果以上步骤都无法解决问题，请联系开发者并提供上述调试信息。

