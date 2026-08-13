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

/// Metro verisi okunamadığında gösterilen tek ekran.
///
/// Oyunun tamamı `assets/data/metro.json` üzerine kurulu; veri yoksa
/// yapılabilecek bir şey yok. Sessizce çökmek yerine ne olduğunu söyler.
class MetroDataErrorApp extends StatelessWidget {
  const MetroDataErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.wrong_location_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Metro verisi yüklenemedi',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Hat ve istasyon bilgisi okunamadığı için oyun '
                  'başlatılamıyor. Uygulamayı kapatıp yeniden açmayı dene; '
                  'sorun sürerse uygulamayı yeniden yükle.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
