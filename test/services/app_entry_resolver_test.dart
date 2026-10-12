import 'package:cyrene_music/services/app_entry_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppEntryRoute route({
    bool loggedIn = true,
    bool configured = true,
    bool terms = true,
    bool navidrome = false,
    bool local = false,
  }) => AppEntryResolver.resolve(
    isLoggedIn: loggedIn,
    isConfigured: configured,
    isTermsAccepted: terms,
    isNavidromeActive: navidrome,
    isLocalMode: local,
  );

  test('first installation requires authentication and configuration', () {
    expect(
      route(loggedIn: false, configured: false, terms: false),
      AppEntryRoute.regularSetup,
    );
    expect(route(configured: false), AppEntryRoute.regularSetup);
    expect(route(), AppEntryRoute.regularMain);
  });

  test(
    'logout blocks entry but a restored login reuses the configured source',
    () {
      expect(route(loggedIn: false), AppEntryRoute.regularSetup);
      expect(route(), AppEntryRoute.regularMain);
      expect(
        route(loggedIn: false, navidrome: true),
        AppEntryRoute.regularSetup,
      );
      expect(route(navidrome: true), AppEntryRoute.navidromeMain);
    },
  );

  test('legacy local-mode flag cannot bypass source setup', () {
    expect(route(configured: false, local: true), AppEntryRoute.regularSetup);
  });

  test(
    'Navidrome setup remains available after authentication and consent',
    () {
      expect(
        route(navidrome: true, configured: false),
        AppEntryRoute.navidromeSetup,
      );
    },
  );

  for (final loggedIn in [false, true]) {
    for (final terms in [false, true]) {
      for (final configured in [false, true]) {
        for (final navidrome in [false, true]) {
          for (final local in [false, true]) {
            test(
              'entry prerequisites: auth=$loggedIn terms=$terms configured=$configured navidrome=$navidrome local=$local',
              () {
                final result = route(
                  loggedIn: loggedIn,
                  terms: terms,
                  configured: configured,
                  navidrome: navidrome,
                  local: local,
                );
                final entersMain =
                    result == AppEntryRoute.regularMain ||
                    result == AppEntryRoute.navidromeMain;
                expect(entersMain, loggedIn && terms && configured);
                if (!loggedIn || !terms) {
                  expect(result, AppEntryRoute.regularSetup);
                }
              },
            );
          }
        }
      }
    }
  }
}
