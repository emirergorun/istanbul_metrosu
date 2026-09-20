import 'package:flutter/widgets.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_host.dart';

import 'metro_fixture.dart';

/// Testte süren yolculuğu ağaca kurar.
///
/// Uygulamada [JourneyHost] `Navigator`'ın üstündedir; tek bir ekranı
/// doğrudan pump eden testlerde de aynı katman gerekir, yoksa ekran
/// yolculuğu bulamaz.
Widget withJourney({
  required LocalStore store,
  required Widget child,
  RouteService? routes,
}) => JourneyHost(
  store: store,
  routes: routes ?? RouteService(MetroFixture.load()),
  child: child,
);
