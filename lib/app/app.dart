import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/audio/audio_service.dart';
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
    required this.audio,
    required this.metro,
  });

  final LocalStore store;
  final AudioService audio;
  final MetroRepository metro;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      audio: audio,
      metro: metro,
      routeService: RouteService(metro),
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // Erişilebilirlik: kullanıcının yazı tipi tercihine saygı gösterilir.
        //
        // Üst sınır tamamen kaldırılmadı çünkü oyun tahtası sabit oranlı;
        // aşırı ölçekte HUD tahtayı eziyor. 1.6 iOS'un "Büyük" kademelerini
        // kapsar ve düzen bu değere kadar test edildi.
        // TODO(PROD): Tahta/HUD düzenini ölçekten bağımsız hale getirip
        // sınırı tamamen kaldır.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(maxScaleFactor: 1.6),
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
