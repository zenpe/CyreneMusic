> 历史文档：旧的后端版本接口、自动下载与自动安装流程已停用。当前方案以 [客户端更新](client-updates.md) 和 [发布流程](release.md) 为准，下文不作为现行操作指引。

# Android 自动更新配置指南

## 📱 功能说明

Android 端支持**应用内自动更新**，无需跳转浏览器：
- ✅ 在应用内下载 APK
- ✅ 显示下载进度（百分比 + 进度条）
- ✅ 自动调用系统安装程序
- ✅ 无需手动管理文件

---

## 🔧 配置步骤

### 1️⃣ **权限配置**（已完成）

在 `android/app/src/main/AndroidManifest.xml` 中已添加：

```xml
<!-- 自动更新所需权限 -->
<!-- Android 8.0+ (API 26+) 安装 APK 权限 -->
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
<!-- 写入外部存储（Android 10 以下） -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29" />
```

### 2️⃣ **后端配置**

确保后端 `backend/update/{version}/` 目录下有 APK 文件：

```
backend/update/
  └── 1.0.7/
      ├── 1.0.7-full.apk     # ← Android 更新包
      ├── 1.0.7-full.zip     # Windows 更新包
      └── manifest.json      # 版本信息
```

APK 文件命名格式：`{版本号}-full.apk`

### 3️⃣ **构建 APK**

```bash
# 构建 Release APK
flutter build apk --release

# 构建后的文件位置
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🎯 工作流程

### 用户体验流程

```mermaid
graph TD
    A[用户打开应用] --> B[自动检查更新]
    B --> C{有新版本?}
    C -->|是| D[显示更新对话框]
    C -->|否| E[正常使用]
    D --> F[用户点击"一键更新"]
    F --> G[显示进度对话框]
    G --> H[应用内下载 APK]
    H --> I[实时显示进度条]
    I --> J[下载完成]
    J --> K[自动打开安装程序]
    K --> L[用户确认安装]
    L --> M[安装完成]
```

### 技术实现流程

1. **检查更新**：
   - 首页延迟 2 秒自动检查
   - 调用 `/version/latest` API
   - 比较版本号

2. **显示更新对话框**：
   - Material Design 对话框
   - 显示版本号、更新日志
   - 提供"一键更新"按钮

3. **开始下载**：
   - 显示进度对话框（不可关闭）
   - 使用 HTTP 流式下载
   - 实时更新进度条

4. **安装 APK**：
   - 检查安装权限
   - 使用 `open_filex` 插件打开 APK
   - 系统安装程序接管

---

## 🔐 权限说明

### REQUEST_INSTALL_PACKAGES

**用途**：允许应用安装其他应用（APK）

**适用版本**：Android 8.0 (API 26) 及以上

**权限级别**：特殊权限

**用户授权**：
- 首次安装 APK 时，系统会弹出授权对话框
- 标题："允许安装未知应用"
- 用户可在系统设置中管理此权限

**代码处理**：
```dart
// open_filex 插件会自动处理权限请求
final result = await OpenFilex.open(
  packageFile.path,
  type: 'application/vnd.android.package-archive',
);

if (result.type == ResultType.permissionDenied) {
  // 权限被拒绝的处理
  print('需要授予"安装未知应用"权限');
}
```

### WRITE_EXTERNAL_STORAGE

**用途**：写入外部存储（用于保存下载的 APK）

**适用版本**：Android 10 (API 29) 以下

**限制**：`android:maxSdkVersion="29"`

**说明**：
- Android 10+ 使用分区存储，不需要此权限
- 应用会将 APK 保存到应用私有目录

---

## 📊 下载进度显示

### Material Design 版本

```
┌─────────────────────────────┐
│ 🔄 正在更新                  │
├─────────────────────────────┤
│ 正在下载更新包...            │
│                              │
│ ████████████░░░░░░░░░░       │
│ 60.0%                    ⭕  │
└─────────────────────────────┘
```

### 进度信息

- **进度条**：线性进度条，实时更新
- **百分比**：精确到 0.1%（如：60.3%）
- **状态消息**：
  - "正在下载更新包..."
  - "下载完成，正在安装..."
  - "准备安装更新..."
  - "正在调用系统安装程序..."

---

## ⚠️ 常见问题

### 问题 1：点击更新后跳转到浏览器

**原因**：
- 平台判断错误
- 缺少权限配置
- 代码逻辑问题

**解决方案**：
1. 确认 `AndroidManifest.xml` 已添加权限
2. 确认 `isPlatformSupported` 包含 Android
3. 查看日志是否有错误信息

### 问题 2：下载后无法安装

**原因**：
- 用户拒绝了"安装未知应用"权限
- APK 文件损坏
- APK 签名问题

**解决方案**：
```dart
// 检查安装结果
if (result.type == ResultType.permissionDenied) {
  // 引导用户授予权限
  print('请在设置中允许安装未知应用');
}
```

### 问题 3：下载进度不更新

**原因**：
- 服务器未返回 Content-Length
- 网络问题
- 状态监听器未正确设置

**解决方案**：
1. 确认后端返回 Content-Length 头
2. 检查 `AutoUpdateService` 的 `notifyListeners()` 调用
3. 使用 `AnimatedBuilder` 监听进度变化

### 问题 4：APK 签名验证失败

**原因**：
- Debug 版本尝试覆盖 Release 版本
- 签名密钥不一致

**解决方案**：
- 卸载旧版本后重新安装
- 确保使用相同的签名密钥

---

## 🧪 测试步骤

### 1. 准备测试环境

```bash
# 1. 构建当前版本（如 1.0.6）
flutter build apk --release

# 2. 安装到测试设备
flutter install

# 3. 构建新版本（如 1.0.7）
# 修改 lib/services/version_service.dart 中的版本号
# static const String kAppVersion = '1.0.7';
flutter build apk --release

# 4. 将新版本 APK 放到后端
cp build/app/outputs/flutter-apk/app-release.apk \
   backend/update/1.0.7/1.0.7-full.apk

# 5. 创建 manifest.json
cat > backend/update/1.0.7/manifest.json << 'EOF'
{
  "version": "1.0.7",
  "changelog": "- [测试] 测试自动更新功能\n- [修复] 修复已知问题",
  "force_update": false
}
EOF

# 6. 重启后端
cd backend
bun run src/index.ts
```

### 2. 执行测试

1. **打开应用**（旧版本 1.0.6）
2. **等待 2 秒**，应该弹出更新对话框
3. **点击"一键更新"**
4. **观察进度对话框**：
   - ✅ 进度条从 0% 增长到 100%
   - ✅ 百分比实时更新
   - ✅ 状态消息变化
5. **下载完成后**，自动弹出系统安装程序
6. **点击"安装"**
7. **安装完成**，打开应用验证版本号

### 3. 测试权限拒绝

1. 在系统设置中**撤销"安装未知应用"权限**：
   - 设置 → 应用 → Cyrene Music → 高级 → 安装未知应用 → 关闭
2. 重复上述测试步骤
3. 点击"一键更新"后，应该提示权限被拒绝
4. 引导用户手动开启权限

### 4. 测试网络异常

```bash
# 在下载过程中断开网络
# 应该显示错误提示
```

---

## 📝 日志说明

### 开启开发者模式

1. 进入**设置** → **开发者选项**
2. 开启开发者模式
3. 查看实时日志

### 关键日志

```
📥 开始下载，URL: http://...
📁 下载目录: /data/user/0/com.cyrene.music/...
📄 文件名: 1.0.7-full.apk
🌐 发送请求: GET http://...
📥 收到响应: 状态码 200
📥 响应头: {content-length: 28451256, ...}
📱 检查安装权限...
📱 正在调用系统安装程序...
📱 APK 安装结果: done
📱 结果类型: ResultType.done
✅ 安装程序已打开
```

### 错误日志

```
❌ 下载失败，状态码: 404
❌ 无法打开安装程序
❌ 安装权限被拒绝
❌ 安装异常: ...
```

---

## 🎉 功能优势

1. **用户体验好**：
   - 不跳转浏览器
   - 实时显示进度
   - 自动化安装

2. **安全可靠**：
   - 使用官方 API
   - 权限控制严格
   - 错误处理完善

3. **维护简单**：
   - 后端只需放置 APK 文件
   - 无需额外配置
   - 自动版本检测

---

## 🔗 相关文档

- [版本发布指南](VERSION_RELEASE_GUIDE.md)
- [Windows 自动更新](WINDOWS_AUTO_UPDATE_FINAL.md)
- [更新故障排查](UPDATE_TROUBLESHOOTING.md)

---

## 📅 更新记录

- **2025-11-22**：初始版本，支持 Android 应用内自动更新

