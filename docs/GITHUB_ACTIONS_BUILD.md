# GitHub Actions 构建与发布

主线为 `main`，不再监听 `just_audio`，也不根据 PR 标题创建版本。

| 操作 | 自动执行 | 产物 |
| --- | --- | --- |
| PR 提交到 main | 静态检查、测试格式检查、测试；通过后编译 Android Debug 和 Windows Release | Actions Artifacts，保留 14 天 |
| 推送 main | 静态检查、测试格式检查、测试 | 检查报告 |
| 推送 `v*` 标签 | 校验版本与 main 历史、质量检查、五个平台正式构建、发布 | GitHub Releases |
| 手动运行 Multi-Platform Build | 选择平台、质量检查、正式构建；默认 Android 和 Windows | Actions Artifacts，保留 14 天，不创建 Release |
| 手动运行 Test Build | 质量检查、Android Debug / Windows Release，可选择平台 | Actions Artifacts，保留 14 天 |

## 正式发布

1. 将修改合并到 main，更新 `pubspec.yaml` 的版本和构建号，等待主线检查通过。
2. 在已推送到 main 的提交上创建标签。标签须为 `v` 加版本名称，不包含 `+构建号`。例如 `version: 1.3.4+8` 对应 `v1.3.4`。
3. 推送标签：

```bash
git switch main
git pull --ff-only origin main
git tag v1.3.4
git push origin v1.3.4
```

版本标签必须唯一；上述名称仅为示例，不要覆盖已发布标签。

标签流水线会重新执行检查。Android、Windows、Linux、macOS 和 iOS 必须全部构建成功，且产物齐全，才进入发布阶段。先上传到草稿 Release，完整上传后再公开；任一步失败都不会继续公开本次草稿。修复失败原因后可以在 Actions 重跑任务。

发行产物包括 Android ARM64 APK、Windows x64 ZIP、Linux amd64 DEB、macOS DMG、未签名 iOS IPA，以及 SHA-256 校验清单和提交信息。iOS IPA 需要自行签名才能安装；macOS 当前未增加 Developer ID 签名或公证。

## Android 正式签名

在仓库 Settings → Secrets and variables → Actions 配置：

- `CYRENE_KEYSTORE_BASE64`
- `CYRENE_KEYSTORE_PASSWORD`
- `CYRENE_KEY_ALIAS`
- `CYRENE_KEY_PASSWORD`

正式 APK 缺少任一签名配置会立即失败，不回退到调试签名。PR 构建使用 Debug 签名，不读取这些 Secrets，因此外部 PR 也能进行编译验证。

工作流默认只有仓库读取权限，仅发布任务获得 `contents: write`。

## 手动构建

进入 Actions → Multi-Platform Build → Run workflow，选择分支和平台，至少选择一个平台。Android 和 Windows 默认开启，Linux、macOS、iOS 默认关闭。手动构建只上传 Artifacts，不会创建 Release，即使选择了版本标签也一样。

若只需要无正式签名的 Android 测试包，使用 Test Build 工作流。

## 环境与并发

本地与 CI 使用 Flutter 3.41.3、Java 17（Android）和已提交的依赖锁文件，依赖解析使用 `--enforce-lockfile`。Linux runner 固定为 Ubuntu 24.04。

同一 PR 或 main 的旧质量检查会被新提交取消。不同调用工作流的质量检查互相隔离，版本标签发布不自动取消。同一引用的正式构建排队执行。

本地正式构建：

```powershell
./scripts/build_release.ps1 -Target all
```

输出位于 `build/releases/`，包含 APK、Windows ZIP、构建记录和校验值。

