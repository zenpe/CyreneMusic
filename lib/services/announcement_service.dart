import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import '../models/announcement.dart';
import 'persistent_storage_service.dart';
import 'developer_mode_service.dart';
import 'api/api_client.dart';

/// 公告服务 - 管理全局公告的获取和显示逻辑
class AnnouncementService extends ChangeNotifier {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  static const String _storageKeyPrefix = 'announcement_dismissed_';

  bool _isInitialized = false;
  Announcement? _currentAnnouncement;
  bool _isLoading = false;
  String? _error;

  bool get isInitialized => _isInitialized;
  Announcement? get currentAnnouncement => _currentAnnouncement;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 初始化公告服务
  Future<void> initialize() async {
    if (_isInitialized) {
      StructuredLogService.log('📢 [AnnouncementService] 已经初始化过，跳过');
      return;
    }

    try {
      StructuredLogService.log('📢 [AnnouncementService] 开始初始化');
      DeveloperModeService().addLog('📢 公告服务初始化');
      await fetchAnnouncement();
      _isInitialized = true;
      StructuredLogService.log('📢 [AnnouncementService] 初始化完成');
      StructuredLogService.log('📢 [AnnouncementService] _currentAnnouncement: $_currentAnnouncement');
      DeveloperModeService().addLog('✅ 公告服务初始化完成');
    } catch (e) {
      StructuredLogService.log('📢 [AnnouncementService] 初始化失败: $e');
      DeveloperModeService().addLog('❌ 公告服务初始化失败: $e');
      _error = e.toString();
      _isInitialized = true; // 即使失败也标记为已初始化，避免重复尝试
    }
  }

  /// 从后端获取公告配置
  Future<void> fetchAnnouncement() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      StructuredLogService.log('📢 [AnnouncementService] 正在获取公告配置...');
      DeveloperModeService().addLog('📢 正在获取公告配置');

      final result = await ApiClient().getJson('/config/public', auth: false);

      StructuredLogService.log('📢 [AnnouncementService] 响应状态码: ${result.statusCode}');

      if (result.ok) {
        final responseData = result.data as Map<String, dynamic>?;
        StructuredLogService.log('📢 [AnnouncementService] 解析后的响应数据: $responseData');

        if (responseData != null && responseData.containsKey('data')) {
          final data = responseData['data'] as Map<String, dynamic>;

          if (data.containsKey('announcement')) {
            final announcementData = data['announcement'] as Map<String, dynamic>;

            _currentAnnouncement = Announcement.fromJson(announcementData);
            StructuredLogService.log('📢 [AnnouncementService] enabled: ${_currentAnnouncement?.enabled}');
            StructuredLogService.log('📢 [AnnouncementService] id: ${_currentAnnouncement?.id}');
            StructuredLogService.log('📢 [AnnouncementService] title: ${_currentAnnouncement?.title}');

            DeveloperModeService().addLog(
              '✅ 公告配置获取成功: ${_currentAnnouncement?.id} - ${_currentAnnouncement?.title}'
            );
          } else {
            DeveloperModeService().addLog('⚠️ 后端配置中未找到公告数据');
            _currentAnnouncement = null;
          }
        } else {
          DeveloperModeService().addLog('⚠️ 响应格式不正确');
          _currentAnnouncement = null;
        }
      } else {
        throw Exception('获取公告配置失败: HTTP ${result.statusCode}');
      }
    } catch (e, stackTrace) {
      StructuredLogService.log('📢 [AnnouncementService] 获取公告配置失败: $e');
      StructuredLogService.log('📢 [AnnouncementService] 堆栈: $stackTrace');
      DeveloperModeService().addLog('❌ 获取公告配置失败: $e');
      _error = e.toString();
      _currentAnnouncement = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 检查是否应该显示公告
  /// 返回 true 表示应该显示，false 表示不应该显示
  bool shouldShowAnnouncement() {
    StructuredLogService.log('📢 [AnnouncementService] shouldShowAnnouncement() 开始检查');
    StructuredLogService.log('📢 [AnnouncementService] _currentAnnouncement: $_currentAnnouncement');

    if (_currentAnnouncement == null) {
      final msg = '📢 无公告数据，不显示';
      StructuredLogService.log(msg);
      DeveloperModeService().addLog(msg);
      return false;
    }

    StructuredLogService.log('📢 [AnnouncementService] enabled: ${_currentAnnouncement!.enabled}');
    if (!_currentAnnouncement!.enabled) {
      final msg = '📢 公告已禁用，不显示';
      StructuredLogService.log(msg);
      DeveloperModeService().addLog(msg);
      return false;
    }

    StructuredLogService.log('📢 [AnnouncementService] id: ${_currentAnnouncement!.id}');
    if (_currentAnnouncement!.id.isEmpty) {
      final msg = '📢 公告 ID 为空，不显示';
      StructuredLogService.log(msg);
      DeveloperModeService().addLog(msg);
      return false;
    }

    // 检查用户是否已经选择不再显示此公告
    final storageKey = _storageKeyPrefix + _currentAnnouncement!.id;
    final isDismissed = PersistentStorageService().getBool(storageKey) ?? false;

    StructuredLogService.log('📢 [AnnouncementService] storageKey: $storageKey');
    StructuredLogService.log('📢 [AnnouncementService] isDismissed: $isDismissed');

    if (isDismissed) {
      final msg = '📢 用户已选择不再显示此公告: ${_currentAnnouncement!.id}';
      StructuredLogService.log(msg);
      DeveloperModeService().addLog(msg);
      return false;
    }

    final msg = '📢 应该显示公告: ${_currentAnnouncement!.id}';
    StructuredLogService.log(msg);
    DeveloperModeService().addLog(msg);
    return true;
  }

  /// 标记公告为已关闭（不再显示）
  Future<void> dismissAnnouncement({required bool dontShowAgain}) async {
    if (_currentAnnouncement == null) return;

    if (dontShowAgain) {
      final storageKey = _storageKeyPrefix + _currentAnnouncement!.id;
      await PersistentStorageService().setBool(storageKey, true);
      DeveloperModeService().addLog('📢 用户选择不再显示公告: ${_currentAnnouncement!.id}');
    } else {
      DeveloperModeService().addLog('📢 用户关闭公告（未选择不再显示）');
    }
  }

  /// 清除所有已关闭的公告记录（用于测试或重置）
  Future<void> clearAllDismissedAnnouncements() async {
    // 这个方法可以用于测试或管理员功能
    // 实际使用时需要遍历所有可能的公告 ID
    DeveloperModeService().addLog('📢 清除所有已关闭的公告记录');
    // 由于我们不知道所有的公告 ID，这里只是一个占位实现
    // 实际项目中可能需要维护一个公告 ID 列表
  }
}
