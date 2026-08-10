import '../../features/journey/models/station.dart';

/// MVP metro datası — uygulama paketinin içinde gömülü, network yok.
///
/// Amaç doğruluk değil: "yolculuk süresi -> zorluk" eşlemesini kanıtlamak.
/// TODO(PROD): Resmi/izinli istasyon datası, çok hatlı ağ, aktarma süreleri ve
/// servis takvimi ayrı bir data katmanından beslenmeli. UI ve oyun kodu
/// değişmeden bu dosya değiştirilebilir olmalı.
class MetroData {
  const MetroData._();

  static const MetroLine m2 = MetroLine(
    id: 'M2',
    name: 'M2 Yenikapı – Hacıosman',
    // Nötr yeşil accent. Resmi marka görseli değildir.
    colorValue: 0xFF00A65A,
  );

  static const List<MetroLine> lines = <MetroLine>[m2];

  /// M2 hattının örnek istasyon listesi (hat sırasına göre).
  static const List<Station> stations = <Station>[
    Station(id: 'm2_yenikapi', name: 'Yenikapı', lineId: 'M2', order: 0),
    Station(id: 'm2_vezneciler', name: 'Vezneciler', lineId: 'M2', order: 1),
    Station(id: 'm2_halic', name: 'Haliç', lineId: 'M2', order: 2),
    Station(id: 'm2_sishane', name: 'Şişhane', lineId: 'M2', order: 3),
    Station(id: 'm2_taksim', name: 'Taksim', lineId: 'M2', order: 4),
    Station(id: 'm2_osmanbey', name: 'Osmanbey', lineId: 'M2', order: 5),
    Station(
      id: 'm2_sisli_mecidiyekoy',
      name: 'Şişli-Mecidiyeköy',
      lineId: 'M2',
      order: 6,
    ),
    Station(id: 'm2_gayrettepe', name: 'Gayrettepe', lineId: 'M2', order: 7),
    Station(id: 'm2_levent', name: 'Levent', lineId: 'M2', order: 8),
    Station(id: 'm2_4levent', name: '4. Levent', lineId: 'M2', order: 9),
    Station(
      id: 'm2_sanayi_mahallesi',
      name: 'Sanayi Mahallesi',
      lineId: 'M2',
      order: 10,
    ),
    Station(id: 'm2_itu_ayazaga', name: 'İTÜ-Ayazağa', lineId: 'M2', order: 11),
    Station(
      id: 'm2_ataturk_oto_sanayi',
      name: 'Atatürk Oto Sanayi',
      lineId: 'M2',
      order: 12,
    ),
    Station(id: 'm2_darussafaka', name: 'Darüşşafaka', lineId: 'M2', order: 13),
    Station(id: 'm2_haciosman', name: 'Hacıosman', lineId: 'M2', order: 14),
  ];
}
