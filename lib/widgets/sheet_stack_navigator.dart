import 'package:flutter/material.dart';

class SheetStackPage {
  final String title;
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    SheetStackController stack,
  ) builder;
  final Key? key;

  const SheetStackPage({
    required this.title,
    required this.builder,
    this.key,
  });
}

class SheetStackController extends ChangeNotifier {
  final List<SheetStackPage> _pages;
  int _version = 0;

  SheetStackController({required SheetStackPage initialPage})
      : _pages = [initialPage];

  List<SheetStackPage> get pages => List.unmodifiable(_pages);
  SheetStackPage get currentPage => _pages.last;
  bool get canPop => _pages.length > 1;
  int get version => _version;

  void push(SheetStackPage page) {
    _pages.add(page);
    _bump();
  }

  void replace(SheetStackPage page) {
    if (_pages.isNotEmpty) {
      _pages.removeLast();
    }
    _pages.add(page);
    _bump();
  }

  bool pop() {
    if (!canPop) return false;
    _pages.removeLast();
    _bump();
    return true;
  }

  void _bump() {
    _version++;
    notifyListeners();
  }
}

class SheetStackNavigator extends StatefulWidget {
  final SheetStackController controller;
  final Color backgroundColor;
  final Color dividerColor;
  final TextStyle? titleTextStyle;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final EdgeInsets headerPadding;
  final bool showHandle;
  final BorderRadius borderRadius;
  final bool useDraggableSheet;
  final VoidCallback? onClose;

  const SheetStackNavigator({
    super.key,
    required this.controller,
    required this.backgroundColor,
    required this.dividerColor,
    this.titleTextStyle,
    this.initialChildSize = 0.82,
    this.minChildSize = 0.6,
    this.maxChildSize = 0.95,
    this.headerPadding = const EdgeInsets.fromLTRB(8, 6, 8, 6),
    this.showHandle = true,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(20)),
    this.useDraggableSheet = true,
    this.onClose,
  });

  @override
  State<SheetStackNavigator> createState() => _SheetStackNavigatorState();
}

class _SheetStackNavigatorState extends State<SheetStackNavigator> {
  int _lastDepth = 1;
  bool _forward = true;
  final ScrollController _fixedController = ScrollController();

  @override
  void initState() {
    super.initState();
    _lastDepth = widget.controller.pages.length;
    widget.controller.addListener(_onStackChanged);
  }

  @override
  void didUpdateWidget(SheetStackNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStackChanged);
      _lastDepth = widget.controller.pages.length;
      widget.controller.addListener(_onStackChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStackChanged);
    _fixedController.dispose();
    super.dispose();
  }

  void _onStackChanged() {
    final depth = widget.controller.pages.length;
    setState(() {
      if (depth == _lastDepth) {
        _forward = true;
      } else {
        _forward = depth > _lastDepth;
      }
      _lastDepth = depth;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.controller.canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.controller.canPop) {
          widget.controller.pop();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: widget.borderRadius,
        ),
        child: Column(
          children: [
            if (widget.showHandle) ...[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            _buildHeader(context),
            const SizedBox(height: 4),
            Expanded(
              child: widget.useDraggableSheet
                  ? DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: widget.initialChildSize,
                      minChildSize: widget.minChildSize,
                      maxChildSize: widget.maxChildSize,
                      builder: (context, controller) {
                        return _buildPage(context, controller);
                      },
                    )
                  : _buildPage(context, _fixedController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, ScrollController controller) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final page = widget.controller.currentPage;
        final key = ValueKey(
          '${widget.controller.version}_${widget.controller.pages.length}',
        );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final begin =
                _forward ? const Offset(1, 0) : const Offset(-1, 0);
            final offsetTween = Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic));
            return SlideTransition(
              position: animation.drive(offsetTween),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: KeyedSubtree(
            key: key,
            child: page.builder(context, controller, widget.controller),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final page = widget.controller.currentPage;
    final canPop = widget.controller.canPop;
    final iconColor =
        widget.titleTextStyle?.color ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: widget.headerPadding,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: canPop
                ? IconButton(
                    onPressed: () => widget.controller.pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: iconColor),
                    tooltip: 'Back',
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              page.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.titleTextStyle ??
                  Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close_rounded, color: iconColor),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}
