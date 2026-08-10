import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/storage/local_store.dart';
import '../data/metro/metro_repository.dart';
import '../features/journey/services/route_service.dart';
import 'app_scope.dart';
import 'routes.dart';
import 'theme.dart';

/// Uygulama kökü.
class MetroGameApp extends StatelessWidget {
  const MetroGameApp({
    super.key,
    required this.store,
    this.metro = const BundledMetroRepository(),
  });

  final LocalStore store;
  final MetroRepository metro;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      metro: metro,
      routeService: RouteService(metro),
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // Sistem yazı tipi ölçeği aşırı büyükse taşmayı önlemek için sınırla.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.2,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        initialRoute: AppRoutes.home,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}
