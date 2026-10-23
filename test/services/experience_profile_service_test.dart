import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/services/back_navigation_coordinator.dart';
import 'package:cyrene_music/services/experience_profile_service.dart';

void main() {
  group('ExperienceProfileService', () {
    test('classifies phone, tablet and desktop by shortest side and size', () {
      expect(
        ExperienceProfileService.classifyScreen(width: 390, height: 844),
        ScreenClass.phone,
      );
      expect(
        ExperienceProfileService.classifyScreen(width: 1280, height: 800),
        ScreenClass.tablet,
      );
      expect(
        ExperienceProfileService.classifyScreen(width: 1920, height: 1080),
        ScreenClass.desktop,
      );
    });

    test(
      'explicit car profile overrides screen inference and persists',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final service = ExperienceProfileService();
        await service.setProfile(ExperienceProfile.car);

        expect(
          service.resolve(width: 1280, height: 800),
          ExperienceProfile.car,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('experience_profile'), 'car');

        await service.setProfile(null);
      },
    );

    test('car policy specializes shared wide-player behavior', () {
      const car = ExperienceProfilePolicy(ExperienceProfile.car);
      const tablet = ExperienceProfilePolicy(ExperienceProfile.tablet);

      expect(car.usesWidePlayer, isTrue);
      expect(tablet.usesWidePlayer, isTrue);
      expect(car.reducedEffects, isTrue);
      expect(tablet.reducedEffects, isFalse);
      expect(car.minimumTouchTarget, 56);
      expect(tablet.minimumTouchTarget, 48);
      expect(
        car.mobileImmersiveScale,
        greaterThan(tablet.mobileImmersiveScale),
      );
    });
  });

  group('BackNavigationCoordinator', () {
    test('closes transient panel before popping route', () {
      final coordinator = const BackNavigationCoordinator();
      final events = <String>[];
      expect(
        coordinator.handleBack(
          transientPanelVisible: true,
          closeTransientPanel: () => events.add('close'),
          popRoute: () => events.add('pop'),
        ),
        isFalse,
      );
      expect(events, ['close']);
    });

    test('pops route when no transient panel is visible', () {
      final coordinator = const BackNavigationCoordinator();
      final events = <String>[];
      expect(
        coordinator.handleBack(
          transientPanelVisible: false,
          closeTransientPanel: () => events.add('close'),
          popRoute: () => events.add('pop'),
        ),
        isTrue,
      );
      expect(events, ['pop']);
    });
  });
}
