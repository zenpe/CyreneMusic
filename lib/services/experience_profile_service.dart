import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Physical layout class derived from the available window.
enum ScreenClass { phone, tablet, desktop }

/// Interaction profile. Car is an overlay on top of the screen class, not a
/// second implementation of the player.
enum ExperienceProfile { phone, tablet, car, desktop }

class ExperienceProfilePolicy {
  final ExperienceProfile profile;

  const ExperienceProfilePolicy(this.profile);

  bool get usesWidePlayer => profile != ExperienceProfile.phone;
  bool get reducedEffects => profile == ExperienceProfile.car;
  double get minimumTouchTarget => profile == ExperienceProfile.car ? 56 : 48;
  double get mobileImmersiveScale =>
      profile == ExperienceProfile.car ? 0.65 : 0.5;
}

class ExperienceProfileService extends ChangeNotifier {
  static final ExperienceProfileService _instance =
      ExperienceProfileService._();
  factory ExperienceProfileService() => _instance;
  ExperienceProfileService._() {
    _load();
  }

  static const _storageKey = 'experience_profile';
  ExperienceProfile? _explicitProfile;

  ExperienceProfile? get explicitProfile => _explicitProfile;

  bool get isCarMode => _explicitProfile == ExperienceProfile.car;

  ExperienceProfile resolve({required double width, required double height}) {
    if (_explicitProfile != null) return _explicitProfile!;
    final screenClass = classifyScreen(width: width, height: height);
    switch (screenClass) {
      case ScreenClass.phone:
        return ExperienceProfile.phone;
      case ScreenClass.tablet:
        return ExperienceProfile.tablet;
      case ScreenClass.desktop:
        return ExperienceProfile.desktop;
    }
  }

  static ScreenClass classifyScreen({
    required double width,
    required double height,
  }) {
    final shortestSide = width < height ? width : height;
    if (shortestSide < 600) return ScreenClass.phone;
    if (width >= 1600 || height >= 1000) return ScreenClass.desktop;
    return ScreenClass.tablet;
  }

  Future<void> setProfile(ExperienceProfile? profile) async {
    if (_explicitProfile == profile) return;
    _explicitProfile = profile;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (profile == null) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, profile.name);
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_storageKey);
      if (value == null) return;
      for (final item in ExperienceProfile.values) {
        if (item.name == value) {
          _explicitProfile = item;
          break;
        }
      }
      notifyListeners();
    } catch (_) {
      // The profile is an enhancement; layout inference remains available.
    }
  }

  /// Whether car-specific interaction constraints should be applied.
  bool shouldUseCarRules({required double width, required double height}) {
    return resolve(width: width, height: height) == ExperienceProfile.car;
  }

  ExperienceProfilePolicy policy({
    required double width,
    required double height,
  }) {
    return ExperienceProfilePolicy(resolve(width: width, height: height));
  }
}
