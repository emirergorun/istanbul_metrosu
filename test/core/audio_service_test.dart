import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS ses oturumu', () {
    test('ambient kategori mixWithOthers olmadan kurulabilir', () {
      // Regresyon: kod `ambient` kategorisine ayrıca `mixWithOthers`
      // seçeneğini de veriyordu. audioplayers bunu yasaklıyor ve kurucu
      // assert atıyor. Assert `AudioService.init` içindeki try/catch'e
      // düşüyor, `_ready` false kalıyor ve oyunda HİÇ ses çıkmıyordu.
      // Cihazda doğrulandı (iPhone 17, debug).
      expect(
        () => AudioContextIOS(category: AVAudioSessionCategory.ambient),
        returnsNormally,
      );
    });

    test('ambient + mixWithOthers hâlâ yasak (varsayımı sabitler)', () {
      // Paket bu kuralı gevşetirse test kırılır ve yorum satırlarının
      // güncellenmesi gerektiğini haber verir.
      expect(
        () => AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const <AVAudioSessionOptions>{
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
