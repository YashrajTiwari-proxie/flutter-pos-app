import 'package:flutter/material.dart';

/// Lets a screen react to being revealed again after a route pushed on top of it is popped
/// (via `RouteAware.didPopNext`) - registered as a `MaterialApp` navigator observer in `app.dart`.
final routeObserver = RouteObserver<PageRoute<void>>();
