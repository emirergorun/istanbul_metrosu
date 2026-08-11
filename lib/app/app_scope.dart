import 'package:flutter/widgets.dart';

import '../core/audio/audio_service.dart';
import '../core/storage/local_store.dart';
import '../data/metro/metro_repository.dart';
import '../features/journey/services/route_service.dart';

/// Uygulama seviyesindeki servisleri widget ağacına taşır.
///
/// Ekstra state-management paketi eklememek için sade bir
/// [InheritedWidget] kullanılır.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.audio,
    required this.metro,
    required this.routeService,
    required super.child,
  });

  final LocalStore store;
  final AudioService audio;
  final MetroRepository metro;
  final RouteService routeService;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope widget ağacında bulunamadı');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      store != oldWidget.store ||
      audio != oldWidget.audio ||
      metro != oldWidget.metro ||
      routeService != oldWidget.routeService;
}
