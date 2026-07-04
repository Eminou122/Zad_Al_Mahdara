import 'package:flutter/widgets.dart';

/// Fired by a child section (e.g. Teams) so the root [ZadSwipeNav] can
/// track the child's PageController and detect whether the gesture was
/// consumed internally.
class PageControllerRegistration extends Notification {
  final PageController controller;
  const PageControllerRegistration(this.controller);
}
