import 'package:flutter/material.dart';

/// Global [RouteObserver] shared across the app so any screen can subscribe
/// as a [RouteAware] and get notified when it becomes visible again
/// (e.g. after a pushed route is popped on top of it).
///
/// Typed as [PageRoute] with a dynamic payload so it matches every page
/// route the app pushes, whether a Flutter [MaterialPageRoute] or a GetX
/// [GetPageRoute] (whose type parameter varies).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
