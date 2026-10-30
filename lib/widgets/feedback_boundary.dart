import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import '../services/auth_service.dart';
import '../services/url_service.dart';
import '../services/netease_login_service.dart';
import '../services/navigation_provider.dart';
import '../utils/page_visibility_notifier.dart';
import '../utils/theme_manager.dart';
import '../utils/app_feedback.dart';

/// Clears ephemeral messages when their UI/account scope no longer applies.
class FeedbackBoundary extends StatefulWidget {
  const FeedbackBoundary({super.key, required this.child});
  final Widget child;
  @override
  State<FeedbackBoundary> createState() => _FeedbackBoundaryState();
}

class _FeedbackBoundaryState extends State<FeedbackBoundary>
    with WidgetsBindingObserver {
  late String identity;
  late final listeners = [
    AuthService(),
    UrlService(),
    NeteaseLoginService(),
    NavigationProvider(),
    PageVisibilityNotifier(),
    ThemeManager(),
  ];
  String get scope =>
      '${AuthService().dataSessionIdentity}:${UrlService().backendRevision}:'
      '${NeteaseLoginService().bindingRevision}:${NavigationProvider().currentIndex}:'
      '${PageVisibilityNotifier().currentPageIndex}:${ThemeManager().themeFramework}:'
      '${ThemeManager().mobileThemeFramework}:${ThemeManager().themeMode}:${ThemeManager().seedColor}';
  @override
  void initState() {
    super.initState();
    identity = scope;
    WidgetsBinding.instance.addObserver(this);
    for (final listener in listeners) {
      listener.addListener(changed);
    }
  }

  void changed() {
    if (identity == scope) return;
    identity = scope;
    AppFeedback.dismissAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) AppFeedback.dismissAll();
  }

  @override
  void dispose() {
    for (final listener in listeners) {
      listener.removeListener(changed);
    }
    WidgetsBinding.instance.removeObserver(this);
    AppFeedback.dismissAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Publishes actual dock/player bounds, including floating and resized layouts.
class FeedbackAvoidance extends SingleChildRenderObjectWidget {
  const FeedbackAvoidance({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AvoidanceRender(ModalRoute.of(context));
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _AvoidanceRender).route = ModalRoute.of(context);
  }
}

class _AvoidanceRender extends RenderProxyBox {
  _AvoidanceRender(this.route);
  ModalRoute<dynamic>? route;
  bool scheduled = false;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!attached || !hasSize) return;
      AppFeedback.updateOccupiedArea(
        this,
        size.height > 0
            ? FeedbackOccupiedArea(localToGlobal(Offset.zero) & size, route)
            : null,
      );
    });
  }

  @override
  void detach() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached) AppFeedback.updateOccupiedArea(this, null);
    });
    super.detach();
  }
}
