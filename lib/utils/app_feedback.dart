import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../utils/theme_manager.dart';

enum FeedbackKind { info, success, error }

/// One short message at a time. Page progress and durable errors stay on-page.
class AppFeedback {
  AppFeedback._(this.context);
  final BuildContext context;
  static _ActiveFeedback? _active;
  static final Map<Object, FeedbackOccupiedArea> _occupied = {};
  static final ValueNotifier<int> geometryRevision = ValueNotifier(0);

  static OverlayState? _overlayOf(BuildContext context) =>
      context is StatefulElement && context.state is OverlayState
      ? context.state as OverlayState
      : Overlay.maybeOf(context);

  static AppFeedback of(BuildContext context) => AppFeedback._(context);
  static AppFeedback? maybeOf(BuildContext context) =>
      context.mounted && _overlayOf(context) != null ? of(context) : null;

  void info(String message, {String? operationKey, IconData? icon}) =>
      showSnackBar(
        SnackBar(content: Text(message)),
        operationKey: operationKey,
        icon: icon,
      );
  void success(String message, {String? operationKey}) => showSnackBar(
    SnackBar(content: Text(message)),
    kind: FeedbackKind.success,
    operationKey: operationKey,
  );
  void error(String message, {String? operationKey, VoidCallback? onRetry}) =>
      showSnackBar(
        SnackBar(
          content: Text(message),
          action: onRetry == null
              ? null
              : SnackBarAction(label: '重试', onPressed: onRetry),
        ),
        kind: FeedbackKind.error,
        operationKey: operationKey,
      );

  void showSnackBar(
    SnackBar bar, {
    FeedbackKind kind = FeedbackKind.info,
    String? operationKey,
    IconData? icon,
  }) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!context.mounted ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final overlay = _overlayOf(context);
    if (overlay == null) return;
    final old = _active;
    if (old != null && (!old.owner.mounted || !old.overlay.mounted)) {
      dismissAll();
    }
    final message = bar.content is Text ? (bar.content as Text).data : null;
    final key =
        operationKey ??
        (bar.content is Text ? (bar.content as Text).data : null);
    final priority = bar.action != null
        ? 3
        : kind == FeedbackKind.error
        ? 2
        : 0;
    if (_active case final current?) {
      if (key != null &&
          current.key == key &&
          current.kind == kind &&
          message != null &&
          current.message == message) {
        return;
      }
      if (current.priority > priority) return;
    }
    dismissAll();
    final theme = InheritedTheme.capture(from: context, to: overlay.context);
    final active = _ActiveFeedback(
      context,
      overlay,
      key,
      kind,
      priority,
      message,
    );
    final duration = bar.action != null
        ? const Duration(seconds: 6)
        : kind == FeedbackKind.error
        ? const Duration(seconds: 5)
        : const Duration(seconds: 2);
    active.entry = OverlayEntry(
      builder: (overlayContext) => ValueListenableBuilder<int>(
        valueListenable: geometryRevision,
        builder: (_, _, _) {
          final media = MediaQuery.of(overlayContext);
          final box = overlay.context.findRenderObject();
          final overlayRect = box is RenderBox && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : Offset.zero & media.size;
          var bottom =
              math.max(media.viewPadding.bottom, media.viewInsets.bottom) + 16;
          for (final area in _occupied.values) {
            if ((area.route == null || area.route!.isCurrent) &&
                area.rect.overlaps(overlayRect)) {
              bottom = math.max(
                bottom,
                overlayRect.bottom - area.rect.top + 12,
              );
            }
          }
          final availableHeight = math.max(
            0.0,
            overlayRect.height - bottom - media.padding.top - 16,
          );
          Widget buildSurface() => theme.wrap(
            _FeedbackSurface(
              bar: bar,
              kind: kind,
              icon: icon,
              duration: duration,
              close: () {
                if (identical(_active, active)) dismissAll();
              },
            ),
          );
          if (availableHeight < 56) {
            return Offstage(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: buildSurface(),
              ),
            );
          }
          return Positioned(
            left: 16,
            right: 16,
            bottom: bottom,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 460,
                  maxHeight: availableHeight,
                ),
                child: buildSurface(),
              ),
            ),
          );
        },
      ),
    );
    _active = active;
    overlay.insert(active.entry);
  }

  void hideCurrentSnackBar() => dismissAll();
  void clearSnackBars() => dismissAll();
  static void dismissAll() {
    final active = _active;
    _active = null;
    if (active == null) return;
    active.entry.remove();
    active.entry.dispose();
  }

  static void updateOccupiedArea(Object token, FeedbackOccupiedArea? area) {
    if (area == null) {
      if (_occupied.remove(token) == null) return;
    } else {
      final old = _occupied[token];
      if (old?.rect == area.rect && old?.route == area.route) return;
      _occupied[token] = area;
    }
    geometryRevision.value++;
  }
}

class FeedbackOccupiedArea {
  const FeedbackOccupiedArea(this.rect, this.route);
  final Rect rect;
  final ModalRoute<dynamic>? route;
}

class _ActiveFeedback {
  _ActiveFeedback(
    this.owner,
    this.overlay,
    this.key,
    this.kind,
    this.priority,
    this.message,
  );
  final BuildContext owner;
  final OverlayState overlay;
  final String? key;
  final FeedbackKind kind;
  final int priority;
  final String? message;
  late final OverlayEntry entry;
}

class FeedbackNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppFeedback.dismissAll();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppFeedback.dismissAll();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppFeedback.dismissAll();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      AppFeedback.dismissAll();
}

class _FeedbackSurface extends StatefulWidget {
  const _FeedbackSurface({
    required this.bar,
    required this.kind,
    required this.duration,
    required this.close,
    this.icon,
  });
  final SnackBar bar;
  final FeedbackKind kind;
  final Duration duration;
  final VoidCallback close;
  final IconData? icon;
  @override
  State<_FeedbackSurface> createState() => _FeedbackSurfaceState();
}

class _FeedbackSurfaceState extends State<_FeedbackSurface> {
  Timer? timer;
  DateTime? started;
  late Duration remaining;
  bool hovered = false;
  bool focused = false;
  bool accessible = false;
  @override
  void initState() {
    super.initState();
    remaining = widget.duration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.bar.onVisible?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    accessible = MediaQuery.of(context).accessibleNavigation;
    _updateTimer();
  }

  void _updateTimer() {
    if (timer != null) {
      remaining -= DateTime.now().difference(started!);
      timer!.cancel();
      timer = null;
    }
    if (hovered || focused || accessible) return;
    started = DateTime.now();
    timer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      widget.close,
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = Theme.of(context);
    final fluentTheme = fluent.FluentTheme.maybeOf(context);
    final brightness = fluentTheme?.brightness ?? material.brightness;
    final cs = material.brightness == brightness
        ? material.colorScheme
        : ColorScheme.fromSeed(
            seedColor: ThemeManager().seedColor,
            brightness: brightness,
          );
    final isCupertino = ThemeManager().isCupertinoFramework;
    final radius = fluentTheme != null
        ? 8.0
        : isCupertino
        ? 12.0
        : 16.0;
    final icon =
        widget.icon ??
        switch (widget.kind) {
          FeedbackKind.info => Icons.info_outline_rounded,
          FeedbackKind.success => Icons.check_circle_outline_rounded,
          FeedbackKind.error => Icons.error_outline_rounded,
        };
    final action = widget.bar.action;
    final content = DefaultTextStyle.merge(
      style: material.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      child: widget.bar.content,
    );
    Widget actionButton(String text, VoidCallback onPressed) {
      if (fluentTheme != null) {
        return fluent.Button(onPressed: onPressed, child: Text(text));
      }
      if (isCupertino) {
        return CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: onPressed,
          child: Text(text),
        );
      }
      return TextButton(onPressed: onPressed, child: Text(text));
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: MouseRegion(
        onEnter: (_) {
          hovered = true;
          _updateTimer();
        },
        onExit: (_) {
          hovered = false;
          _updateTimer();
        },
        child: Focus(
          onFocusChange: (value) {
            focused = value;
            _updateTimer();
          },
          child: Material(
            key: const ValueKey('app-feedback-surface'),
            color: cs.surfaceContainerHigh,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: .15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          icon,
                          size: 20,
                          color: widget.kind == FeedbackKind.error
                              ? cs.error
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: content,
                        ),
                      ),
                      if (accessible ||
                          action != null ||
                          widget.kind == FeedbackKind.error)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton(
                            tooltip: '关闭提示',
                            onPressed: widget.close,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (action != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButton(action.label, () {
                        widget.close();
                        action.onPressed();
                      }),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
