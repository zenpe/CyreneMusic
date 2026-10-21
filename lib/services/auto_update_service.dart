import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/version_info.dart';
import 'developer_mode_service.dart';
import 'persistent_storage_service.dart';
import 'url_service.dart';
import 'update_package_downloader.dart';

/// 自动更新服务
class AutoUpdateService extends ChangeNotifier {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal()
    : _platform = defaultTargetPlatform,
      _downloader = UpdatePackageDownloader();

  @visibleForTesting
  AutoUpdateService.forTesting({
    required TargetPlatform platform,
    required Future<Directory> Function() downloadDirectory,
    required Future<OpenResult> Function(String) openInstaller,
    UpdatePackageDownloader? downloader,
  }) : _platform = platform,
       _downloader = downloader ?? UpdatePackageDownloader(),
       _downloadDirectory = downloadDirectory,
       _openInstaller = openInstaller;

  final TargetPlatform _platform;
  final UpdatePackageDownloader _downloader;
  Future<Directory> Function()? _downloadDirectory;
  Future<OpenResult> Function(String)? _openInstaller;

  static const String _storageKey = 'auto_update_enabled';

  bool _isInitialized = false;
  bool _enabled = false;
  bool _isUpdating = false;
  bool _requiresRestart = false;
  double _progress = 0.0;
  String _statusMessage = '未开始';
  String? _lastError;
  VersionInfo? _pendingVersion;
  DateTime? _lastSuccessAt;

  /// 初始化自动更新服务
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final storedValue = PersistentStorageService().getBool(_storageKey);
      _enabled = storedValue ?? false;
      _isInitialized = true;
      DeveloperModeService().addLog(
        '🔄 自动更新服务初始化，当前状态: ${_enabled ? '已开启' : '已关闭'}',
      );
    } catch (e) {
      DeveloperModeService().addLog('❌ 自动更新服务初始化失败: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isEnabled => _enabled;
  bool get isUpdating => _isUpdating;
  bool get requiresRestart => _requiresRestart;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;
  VersionInfo? get pendingVersion => _pendingVersion;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// 当前平台是否支持自动更新
  bool get isPlatformSupported =>
      _platform == TargetPlatform.windows ||
      _platform == TargetPlatform.android;

  /// 设置自动更新开关
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;

    _enabled = value;
    notifyListeners();

    final saved = await PersistentStorageService().setBool(_storageKey, value);
    if (!saved) {
      DeveloperModeService().addLog('⚠️ 自动更新状态保存失败');
    }

    DeveloperModeService().addLog(value ? '⚙️ 自动更新已开启' : '⏸️ 自动更新已关闭');

    if (value &&
        _pendingVersion != null &&
        !_isUpdating &&
        isPlatformSupported) {
      // 延迟触发，确保调用方已有机会更新 UI
      unawaited(
        Future.delayed(const Duration(milliseconds: 200), () {
          final version = _pendingVersion;
          if (_enabled && version != null) {
            unawaited(startUpdate(versionInfo: version, autoTriggered: true));
          }
        }),
      );
    }
  }

  /// 监听到新版本信息
  void onNewVersionDetected(VersionInfo versionInfo) {
    _pendingVersion = versionInfo;
    _lastError = null;
    _requiresRestart = false;
    notifyListeners();

    if (_enabled &&
        !_isUpdating &&
        isPlatformSupported &&
        !versionInfo.forceUpdate) {
      startUpdate(versionInfo: versionInfo, autoTriggered: true);
    }
  }

  /// 清除待更新版本（例如确认已是最新版本时）
  void clearPendingVersion() {
    if (_pendingVersion == null) return;
    _pendingVersion = null;
    notifyListeners();
  }

  /// 手动或自动触发更新
  Future<void> startUpdate({
    VersionInfo? versionInfo,
    bool autoTriggered = false,
  }) async {
    versionInfo ??= _pendingVersion;

    if (versionInfo == null) {
      _statusMessage = '未检测到可用更新';
      _lastError = '没有可用的版本信息';
      notifyListeners();
      return;
    }

    if (!isPlatformSupported) {
      _statusMessage = '当前平台暂不支持自动更新';
      _lastError = _statusMessage;
      notifyListeners();
      return;
    }

    if (_isUpdating) {
      DeveloperModeService().addLog('⚠️ 自动更新任务已在执行中，跳过重复触发');
      return;
    }

    final downloadUrl = _resolveDownloadUrl(versionInfo);
    if (downloadUrl == null) {
      final message = '后端未提供当前平台的更新包链接';
      _statusMessage = message;
      _lastError = message;
      notifyListeners();
      DeveloperModeService().addLog('❌ $message');
      return;
    }

    _isUpdating = true;
    _progress = 0.0;
    _lastError = null;
    _requiresRestart = false;
    _statusMessage = autoTriggered ? '正在后台自动下载更新...' : '正在下载更新包...';
    notifyListeners();

    DeveloperModeService().addLog('⬇️ 原始下载URL: $downloadUrl');
    DeveloperModeService().addLog('🌐 当前后端baseUrl: ${UrlService().baseUrl}');

    try {
      final normalizedUrl = UpdatePackageDownloader.resolveUrl(
        downloadUrl,
        UrlService().baseUrl,
      );
      DeveloperModeService().addLog('🔄 归一化后URL: $normalizedUrl');
      final downloadedFile = await _downloader.download(
        normalizedUrl,
        await (_downloadDirectory?.call() ?? _resolveDownloadDirectory()),
        onProgress: (value) {
          _progress = value;
          notifyListeners();
        },
      );

      _statusMessage = '下载完成，正在安装...';
      _progress = 1.0;
      notifyListeners();

      if (_platform == TargetPlatform.windows) {
        if (downloadedFile.path.toLowerCase().endsWith('.zip')) {
          await _installOnDesktop(downloadedFile, versionInfo);
          _statusMessage = '更新文件已准备，请重启应用生效';
          _requiresRestart = true;
          _lastSuccessAt = DateTime.now();
        } else {
          await _openFile(downloadedFile);
          _statusMessage = '已打开安装程序，请按照提示完成安装';
        }
      } else if (_platform == TargetPlatform.android) {
        await _installOnAndroid(downloadedFile);
      } else {
        // 兜底处理
        await _openFile(downloadedFile);
      }
    } catch (e, stackTrace) {
      _lastError = e.toString();
      _statusMessage = '更新失败: $e';
      DeveloperModeService().addLog('❌ 自动更新失败: $e');
      DeveloperModeService().addLog(stackTrace.toString());
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  /// 辅助方法：根据平台解析下载地址
  String? _resolveDownloadUrl(VersionInfo versionInfo) {
    if (_platform == TargetPlatform.windows) {
      return versionInfo.platformDownloadUrl('windows') ??
          versionInfo.downloadUrl;
    }
    if (_platform == TargetPlatform.android) {
      return versionInfo.platformDownloadUrl('android') ??
          versionInfo.downloadUrl;
    }
    if (Platform.isIOS) {
      return versionInfo.platformDownloadUrl('ios') ?? versionInfo.downloadUrl;
    }
    if (Platform.isMacOS) {
      return versionInfo.platformDownloadUrl('macos') ??
          versionInfo.downloadUrl;
    }
    if (Platform.isLinux) {
      return versionInfo.platformDownloadUrl('linux') ??
          versionInfo.downloadUrl;
    }
    return versionInfo.downloadUrl;
  }

  Future<Directory> _resolveDownloadDirectory() async {
    Directory baseDir;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final installDir = Directory(_resolveInstallDirectory());
      baseDir = Directory(p.join(installDir.path, 'updates'));
    } else {
      final supportDir = await getApplicationSupportDirectory();
      baseDir = Directory(p.join(supportDir.path, 'updates'));
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  String _resolveInstallDirectory() {
    try {
      final executable = File(Platform.resolvedExecutable);
      final executableName = executable.uri.pathSegments.isNotEmpty
          ? executable.uri.pathSegments.last.toLowerCase()
          : '';

      if (executableName.contains('flutter') ||
          executableName.contains('dart')) {
        return Directory.current.path;
      }
      return executable.parent.path;
    } catch (_) {
      return Directory.current.path;
    }
  }

  Future<void> _installOnDesktop(
    File archiveFile,
    VersionInfo versionInfo,
  ) async {
    if (!archiveFile.path.toLowerCase().endsWith('.zip')) {
      // 非 Zip 包直接尝试打开
      await _openFile(archiveFile);
      return;
    }

    _statusMessage = '正在解压更新包...';
    notifyListeners();

    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    // 在 Windows 上，解压到临时目录并启动独立更新器
    if (Platform.isWindows) {
      await _installOnWindowsWithUpdater(archive, archiveFile);
      return;
    }

    // 其他桌面平台：直接解压到安装目录
    final installDir = Directory(_resolveInstallDirectory());
    final rootSegments = <String>{};
    for (final entry in archive) {
      final sanitizedName = _sanitizeArchiveEntry(entry.name);
      if (sanitizedName.isEmpty) continue;
      final parts = sanitizedName.split('/');
      if (parts.isNotEmpty) {
        rootSegments.add(parts.first);
      }
    }

    final shouldStripRoot =
        rootSegments.length == 1 && rootSegments.first.isNotEmpty;
    final rootToStrip = shouldStripRoot ? '${rootSegments.first}/' : null;

    int successCount = 0;
    int skipCount = 0;
    final skippedFiles = <String>[];

    for (final entry in archive) {
      var sanitizedName = _sanitizeArchiveEntry(entry.name);
      if (sanitizedName.isEmpty) {
        continue;
      }

      if (rootToStrip != null && sanitizedName.startsWith(rootToStrip)) {
        sanitizedName = sanitizedName.substring(rootToStrip.length);
      }

      if (sanitizedName.isEmpty) {
        continue;
      }

      final outputPath = p.join(installDir.path, sanitizedName);

      if (entry.isDirectory) {
        final directory = Directory(outputPath);
        if (!directory.existsSync()) {
          try {
            directory.createSync(recursive: true);
            successCount++;
          } catch (e) {
            DeveloperModeService().addLog('⚠️ 创建目录失败: $outputPath - $e');
            skipCount++;
          }
        }
      } else {
        final file = File(outputPath);
        try {
          file.parent.createSync(recursive: true);
          final data = entry.content as List<int>;

          await file.writeAsBytes(data, flush: true);
          successCount++;
          DeveloperModeService().addLog('✅ 更新文件: $sanitizedName');
        } catch (e) {
          DeveloperModeService().addLog('⚠️ 更新文件失败: $sanitizedName - $e');
          skipCount++;
          skippedFiles.add(sanitizedName);
        }
      }
    }

    DeveloperModeService().addLog(
      '📦 解压完成: 成功 $successCount 个，跳过 $skipCount 个',
    );
    if (skippedFiles.isNotEmpty) {
      DeveloperModeService().addLog(
        '⏭️ 跳过的文件: ${skippedFiles.take(10).join(', ')}${skippedFiles.length > 10 ? '...' : ''}',
      );
    }

    archiveFile.delete().ignore();

    if (skipCount > 0) {
      _statusMessage = '更新完成（部分文件将在重启后生效）';
    } else {
      _statusMessage = '更新文件已覆盖，等待重启';
    }
    notifyListeners();
  }

  /// Windows 平台使用独立更新器安装
  Future<void> _installOnWindowsWithUpdater(
    Archive archive,
    File archiveFile,
  ) async {
    try {
      final installDir = Directory(_resolveInstallDirectory());

      // 创建临时更新目录
      final tempUpdateDir = Directory(
        p.join(
          installDir.path,
          'updates',
          'temp_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      if (!await tempUpdateDir.exists()) {
        await tempUpdateDir.create(recursive: true);
      }

      DeveloperModeService().addLog('📁 临时更新目录: ${tempUpdateDir.path}');

      // 分析压缩包结构，判断是否需要去除顶层目录
      final rootSegments = <String>{};
      for (final entry in archive) {
        final sanitizedName = _sanitizeArchiveEntry(entry.name);
        if (sanitizedName.isEmpty) continue;
        final parts = sanitizedName.split('/');
        if (parts.isNotEmpty) {
          rootSegments.add(parts.first);
        }
      }

      final shouldStripRoot =
          rootSegments.length == 1 && rootSegments.first.isNotEmpty;
      final rootToStrip = shouldStripRoot ? '${rootSegments.first}/' : null;

      DeveloperModeService().addLog(
        '📦 解压结构分析: ${shouldStripRoot ? "去除顶层目录 '$rootToStrip'" : "保持原结构"}',
      );

      // 解压所有文件到临时目录
      int extractCount = 0;
      for (final entry in archive) {
        var sanitizedName = _sanitizeArchiveEntry(entry.name);
        if (sanitizedName.isEmpty) continue;

        // 去除顶层目录（如果需要）
        if (rootToStrip != null && sanitizedName.startsWith(rootToStrip)) {
          sanitizedName = sanitizedName.substring(rootToStrip.length);
        }

        if (sanitizedName.isEmpty) continue;

        final outputPath = p.join(tempUpdateDir.path, sanitizedName);

        if (entry.isDirectory) {
          final directory = Directory(outputPath);
          if (!directory.existsSync()) {
            directory.createSync(recursive: true);
          }
        } else {
          final file = File(outputPath);
          file.parent.createSync(recursive: true);
          final data = entry.content as List<int>;
          await file.writeAsBytes(data, flush: true);
          extractCount++;

          // 每50个文件输出一次进度
          if (extractCount % 50 == 0) {
            DeveloperModeService().addLog('📦 已解压 $extractCount 个文件...');
          }
        }
      }

      DeveloperModeService().addLog('✅ 解压完成，共 $extractCount 个文件');

      // 删除下载的压缩包
      archiveFile.delete().ignore();

      // 从 assets 加载更新器脚本并写入到临时文件
      DeveloperModeService().addLog('📝 加载更新器脚本...');

      String updaterScriptContent;
      try {
        // 尝试从新版本的文件中读取（如果存在）
        final newUpdaterPath = File(
          p.join(
            tempUpdateDir.path,
            'data',
            'flutter_assets',
            'windows',
            'runner',
            'updater.ps1',
          ),
        );
        if (await newUpdaterPath.exists()) {
          updaterScriptContent = await newUpdaterPath.readAsString();
          DeveloperModeService().addLog('✅ 使用新版本的更新器脚本');
        } else {
          // 从当前版本的 assets 加载
          updaterScriptContent = await rootBundle.loadString(
            'windows/runner/updater.ps1',
          );
          DeveloperModeService().addLog('✅ 使用当前版本的更新器脚本');
        }
      } catch (e) {
        DeveloperModeService().addLog('❌ 加载更新器脚本失败: $e');
        throw Exception('无法加载更新器脚本: $e');
      }

      // 将脚本写入到临时文件
      final updaterScriptFile = File(
        p.join(
          tempUpdateDir.parent.path,
          'updater_${DateTime.now().millisecondsSinceEpoch}.ps1',
        ),
      );
      await updaterScriptFile.writeAsString(updaterScriptContent);
      DeveloperModeService().addLog('📝 更新器脚本已写入: ${updaterScriptFile.path}');

      // 验证文件是否真的存在
      if (!await updaterScriptFile.exists()) {
        throw Exception('更新器脚本文件写入失败');
      }
      DeveloperModeService().addLog('✓ 已验证脚本文件存在');

      File updaterToUse = updaterScriptFile;

      // 准备更新器参数
      final exePath = Platform.resolvedExecutable;

      // 确保路径格式正确
      final installDirPath = installDir.path.replaceAll('/', '\\');
      final updateDirPath = tempUpdateDir.path.replaceAll('/', '\\');
      final exePathClean = exePath.replaceAll('/', '\\');
      final scriptPath = updaterToUse.path.replaceAll('/', '\\');

      // 先创建一个批处理文件来启动更新器（最可靠的方式）
      final batchFile = File(
        p.join(tempUpdateDir.parent.path, 'start_updater.bat'),
      );
      final batchContent =
          '''@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    :: Already running as administrator
    goto :RunUpdater
) else (
    :: Request administrator privileges
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:RunUpdater
echo ========================================
echo Cyrene Music Updater
echo ========================================
echo.
echo Script: $scriptPath
echo Install: $installDirPath
echo Update: $updateDirPath
echo.
echo Starting updater with administrator privileges...
echo.

powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "$scriptPath" -InstallDir "$installDirPath" -UpdateDir "$updateDirPath" -ExePath "$exePathClean" -WaitSeconds 3

echo.
echo Update completed
echo Window will close automatically in 2 seconds...
timeout /t 2 /nobreak >nul
exit
''';

      // 使用 ASCII 编码写入批处理文件（避免中文编码问题）
      await batchFile.writeAsString(batchContent, encoding: latin1);
      DeveloperModeService().addLog('📝 批处理文件已创建: ${batchFile.path}');

      DeveloperModeService().addLog('🚀 启动更新器...');
      DeveloperModeService().addLog('   批处理文件: ${batchFile.path}');
      DeveloperModeService().addLog('   更新器脚本: $scriptPath');
      DeveloperModeService().addLog('   安装目录: $installDirPath');
      DeveloperModeService().addLog('   更新目录: $updateDirPath');
      DeveloperModeService().addLog('   主程序: $exePathClean');

      try {
        // 方式1: 直接运行批处理文件（最简单可靠）
        final process = await Process.start(
          batchFile.path,
          [],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );

        DeveloperModeService().addLog('✅ 更新器批处理已启动 (PID: ${process.pid})');
      } catch (e) {
        DeveloperModeService().addLog('❌ 批处理启动失败: $e');
        DeveloperModeService().addLog('尝试方式2: 使用 cmd 启动批处理');

        // 方式2: 使用 cmd /c 启动
        try {
          final process = await Process.start(
            'cmd.exe',
            ['/c', batchFile.path],
            mode: ProcessStartMode.detached,
            runInShell: false,
          );

          DeveloperModeService().addLog(
            '✅ 更新器批处理已启动 (方式2, PID: ${process.pid})',
          );
        } catch (e2) {
          DeveloperModeService().addLog('❌ 方式2也失败: $e2');
          DeveloperModeService().addLog('尝试方式3: 直接启动 PowerShell');

          // 方式3: 直接启动 PowerShell（最后的备用方案）
          final arguments = [
            '-WindowStyle',
            'Hidden',
            '-ExecutionPolicy',
            'Bypass',
            '-NoProfile',
            '-File',
            scriptPath,
            '-InstallDir',
            installDirPath,
            '-UpdateDir',
            updateDirPath,
            '-ExePath',
            exePathClean,
            '-WaitSeconds',
            '3',
          ];

          try {
            final process = await Process.start(
              'powershell.exe',
              arguments,
              mode: ProcessStartMode.detached,
            );

            DeveloperModeService().addLog(
              '✅ 更新器进程已启动 (方式3, PID: ${process.pid})',
            );
          } catch (e3) {
            DeveloperModeService().addLog('❌ 所有方式都失败了');
            DeveloperModeService().addLog('   错误1: $e');
            DeveloperModeService().addLog('   错误2: $e2');
            DeveloperModeService().addLog('   错误3: $e3');
            throw Exception('无法启动更新器进程，请查看日志了解详情');
          }
        }
      }

      _statusMessage = '更新器已启动，应用即将重启';
      _requiresRestart = true;
      notifyListeners();

      DeveloperModeService().addLog('⏳ 等待 2 秒确保更新器完全启动...');

      // 增加等待时间，确保更新器完全启动
      await Future.delayed(const Duration(seconds: 2));

      DeveloperModeService().addLog('👋 退出应用 - exit(0)');

      // 退出应用
      exit(0);
    } catch (e, stackTrace) {
      DeveloperModeService().addLog('❌ Windows 更新器启动失败: $e');
      DeveloperModeService().addLog(stackTrace.toString());
      rethrow;
    }
  }

  Future<void> _installOnAndroid(File packageFile) async {
    _statusMessage = '正在调用系统安装程序...';
    notifyListeners();
    final result =
        await (_openInstaller?.call(packageFile.path) ??
            OpenFilex.open(
              packageFile.path,
              type: 'application/vnd.android.package-archive',
              uti: 'com.android.package-archive',
            ));
    if (result.type != ResultType.done) {
      throw StateError(switch (result.type) {
        ResultType.permissionDenied => '需要授予“安装未知应用”权限才能更新',
        ResultType.noAppToOpen => '系统无法找到 APK 安装器',
        _ => '打开安装程序失败：${result.message}',
      });
    }
    // Launching the installer does not mean the user installed the APK.
    _statusMessage = '已打开安装程序，请按照提示完成安装';
    notifyListeners();
  }

  Future<void> _openFile(File file) async {
    final result =
        await (_openInstaller?.call(file.path) ?? OpenFilex.open(file.path));
    if (result.type != ResultType.done) {
      throw StateError('打开安装程序失败：${result.message}');
    }
  }

  String _sanitizeArchiveEntry(String originalName) {
    var name = originalName.replaceAll('\\', '/');
    name = p.normalize(name);

    while (name.startsWith('../')) {
      name = name.substring(3);
    }
    while (name.startsWith('./')) {
      name = name.substring(2);
    }

    if (name.contains('..')) {
      return '';
    }
    return name;
  }
}

extension on Future<void> {
  void ignore() {}
}
