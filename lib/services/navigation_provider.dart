import 'package:flutter/foundation.dart';
import 'developer_mode_service.dart';

/// 导航状态管理 Provider
/// 负责管理应用的导航状态，包括当前选中的页面索引和导航历史
class NavigationProvider with ChangeNotifier {
  // 单例模式
  static final NavigationProvider _instance = NavigationProvider._internal();
  factory NavigationProvider() => _instance;
  NavigationProvider._internal();

  int _currentIndex = 0;
  final List<int> _history = [0];

  /// 获取当前选中的页面索引
  int get currentIndex => _currentIndex;

  /// 获取导航历史记录
  List<int> get history => List.unmodifiable(_history);

  /// 导航到指定索引的页面
  /// 
  /// [index] 目标页面索引
  void navigateTo(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      _history.add(index);
      notifyListeners();
    }
  }

  /// 检查是否可以返回上一页
  bool get canGoBack => _history.length > 1;

  /// 返回上一页
  void goBack() {
    if (canGoBack) {
      _history.removeLast();
      _currentIndex = _history.last;
      notifyListeners();
    }
  }

  /// 清空导航历史并重置到首页
  void reset() {
    _currentIndex = 0;
    _history.clear();
    _history.add(0);
    notifyListeners();
  }

  /// 获取历史记录长度
  int get historyLength => _history.length;

  /// 导航到设置页
  /// 设置页索引计算：首页(0) + 发现(1) + 历史(2) + 本地(3) + 我的(4) + [Dev](开发者模式) + 支持
  void navigateToSettings() {
    // 基础页面数量: 首页, 发现, 历史, 本地, 我的 = 5
    // 加上支持页 = 6
    // 开发者模式下加 1
    int settingsIndex = 6;
    if (DeveloperModeService().isDeveloperMode) {
      settingsIndex = 7;
    }
    navigateTo(settingsIndex);
  }
}
