/// Coordinates back navigation inside full-screen player surfaces.
///
/// Transient UI always gets the first back action. The route is popped only
/// when no transient surface is visible.
class BackNavigationCoordinator {
  const BackNavigationCoordinator();

  bool handleBack({
    required bool transientPanelVisible,
    required void Function() closeTransientPanel,
    required void Function() popRoute,
  }) {
    if (transientPanelVisible) {
      closeTransientPanel();
      return false;
    }
    popRoute();
    return true;
  }
}
