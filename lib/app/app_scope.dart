import 'package:flutter/widgets.dart';

import '../core/audio/audio_service.dart';
import '../core/storage/local_store.dart';
import '../data/metro/metro_repository.dart';
import '../data/questions/question_repository.dart';
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
    this.questions = const EmptyQuestionRepository(),
    required this.routeService,
    required super.child,
  });

  final LocalStore store;
  final AudioService audio;
  final MetroRepository metro;

  /// Elle yazılmış bilgi soruları. Dosya okunamazsa boş havuz gelir ve
  /// Metro Bilgi yalnızca üretilen sorularla oynanır.
  final QuestionRepository questions;

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
      questions != oldWidget.questions ||
      routeService != oldWidget.routeService;
}
