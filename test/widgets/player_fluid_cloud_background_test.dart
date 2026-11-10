import 'package:cyrene_music/pages/player_components/player_fluid_cloud_background.dart';
import 'package:cyrene_music/services/player_background_service.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:cyrene_music/widgets/flowing_light_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends ChangeNotifier implements PlayerService {
  @override
  bool isTrackSwitchPending = false;
  @override
  bool isLoading = false;
  @override
  String? displayCoverUrl;
  @override
  String? currentCoverUrl;
  @override
  ImageProvider? currentCoverImageProvider;
  @override
  final themeColorNotifier = ValueNotifier<Color?>(null);
  void emit() => notifyListeners();
  bool get observed => hasListeners;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    themeColorNotifier.dispose();
    super.dispose();
  }
}

class _Background extends ChangeNotifier implements PlayerBackgroundService {
  @override
  PlayerBackgroundType backgroundType = PlayerBackgroundType.adaptive;
  @override
  Color solidColor = Colors.black;
  void emit() => notifyListeners();
  bool get observed => hasListeners;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Keep image loading pending: these tests exercise subscription behavior,
// not networking, image decoding or the animated background's GPU processing.
class _PendingImage extends ImageStreamCompleter {}

class _Cover extends ImageProvider<_Cover> {
  @override
  Future<_Cover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Cover key,
    ImageErrorListener handleError,
  ) {
    stream.setCompleter(_PendingImage());
  }
}

void main() {
  Widget host(_Player player, _Background background, {bool reduced = false}) =>
      MaterialApp(
        home: SizedBox.expand(
          child: PlayerFluidCloudBackground(
            player: player,
            background: background,
            reducedEffects: reduced,
          ),
        ),
      );

  Widget surface(WidgetTester tester) => tester.widget(
    find
        .descendant(
          of: find.byType(PlayerFluidCloudBackground),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );

  for (final mode in [
    PlayerBackgroundType.adaptive,
    PlayerBackgroundType.dynamic,
  ]) {
    testWidgets(
      '${mode.name}: progress notifications do not rebuild the background',
      (tester) async {
        final player = _Player();
        final background = _Background()..backgroundType = mode;
        addTearDown(player.dispose);
        addTearDown(background.dispose);
        await tester.pumpWidget(host(player, background));
        final initial = surface(tester);
        for (var i = 0; i < 30; i++) {
          player.emit();
          await tester.pump(const Duration(milliseconds: 16));
          expect(surface(tester), same(initial));
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${mode.name}: late cover and provider replacement refresh without a track change',
      (tester) async {
        final player = _Player();
        final background = _Background()..backgroundType = mode;
        addTearDown(player.dispose);
        addTearDown(background.dispose);
        await tester.pumpWidget(host(player, background));
        final before = surface(tester);
        final first = _Cover();
        player.displayCoverUrl = player.currentCoverUrl =
            'https://example.test/cover.jpg';
        player.currentCoverImageProvider = first;
        player.emit();
        await tester.pump();
        expect(surface(tester), isNot(same(before)));
        ImageProvider? shown() => mode == PlayerBackgroundType.dynamic
            ? tester
                  .widget<FlowingLightBackground>(
                    find.byType(FlowingLightBackground),
                  )
                  .imageProvider
            : tester.widget<Image>(find.byType(Image)).image;
        expect(shown(), same(first));
        final replacement = _Cover();
        player.currentCoverImageProvider = replacement;
        player.emit();
        await tester.pump();
        expect(shown(), same(replacement));

        // While switching, the previous cover must not leak into an empty target.
        player.isTrackSwitchPending = true;
        player.isLoading = true;
        player.displayCoverUrl = null;
        player.emit();
        await tester.pump();
        if (mode == PlayerBackgroundType.dynamic) {
          expect(shown(), isNull);
        } else {
          expect(find.byType(Image), findsNothing);
        }
        player.isTrackSwitchPending = false;
        player.isLoading = false;
        player.displayCoverUrl = player.currentCoverUrl;
        player.emit();
        await tester.pump();
        expect(shown(), same(replacement));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'custom backgrounds ignore player changes and switching modes reads the latest cover',
    (tester) async {
      final player = _Player();
      final background = _Background()
        ..backgroundType = PlayerBackgroundType.solidColor;
      addTearDown(player.dispose);
      addTearDown(background.dispose);
      await tester.pumpWidget(host(player, background));
      final original = surface(tester);
      final cover = _Cover();
      player.displayCoverUrl = player.currentCoverUrl =
          'https://example.test/new.jpg';
      player.currentCoverImageProvider = cover;
      player.emit();
      await tester.pump();
      expect(surface(tester), same(original));
      background.solidColor = Colors.blue;
      background.emit();
      await tester.pump();
      expect(surface(tester), isNot(same(original)));
      background.backgroundType = PlayerBackgroundType.adaptive;
      background.emit();
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).image, same(cover));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reduced effects retain independent theme-color updates', (
    tester,
  ) async {
    final player = _Player();
    final background = _Background()
      ..backgroundType = PlayerBackgroundType.dynamic;
    addTearDown(player.dispose);
    addTearDown(background.dispose);
    await tester.pumpWidget(host(player, background, reduced: true));
    expect(find.byType(FlowingLightBackground), findsNothing);
    final original = surface(tester);
    player.emit();
    await tester.pump();
    expect(surface(tester), same(original));
    player.themeColorNotifier.value = Colors.blue;
    await tester.pump();
    expect(surface(tester), isNot(same(original)));
    expect(
      tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any(
            (widget) =>
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color == Colors.blue,
          ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'replacing dependencies and disposing release the old listeners',
    (tester) async {
      final oldPlayer = _Player(), newPlayer = _Player();
      final oldBackground = _Background(), newBackground = _Background();
      for (final notifier in [
        oldPlayer,
        newPlayer,
        oldBackground,
        newBackground,
      ]) {
        addTearDown(notifier.dispose);
      }
      await tester.pumpWidget(host(oldPlayer, oldBackground));
      expect(oldPlayer.observed, isTrue);
      await tester.pumpWidget(host(newPlayer, newBackground));
      expect(oldPlayer.observed, isFalse);
      expect(oldBackground.observed, isFalse);
      expect(newPlayer.observed, isTrue);
      expect(newBackground.observed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(newPlayer.observed, isFalse);
      expect(newBackground.observed, isFalse);
      newPlayer.emit();
      newBackground.emit();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
