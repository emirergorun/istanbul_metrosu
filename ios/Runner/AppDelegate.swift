import Flutter
import GameKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Game Center köprüsü. Yalnız takma adı dışarı veriyor; bkz.
    // `GameCenterBridge`.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "GameCenterBridge"
    ) {
      GameCenterBridge.register(with: registrar)
    }
  }
}

// Köprü **bu dosyanın içinde** duruyor, ayrı bir dosyada değil.
//
// Gerekçe Xcode: yeni bir `.swift` dosyası ancak `project.pbxproj` içindeki
// derleme kaynaklarına elle eklenirse derleniyor. O dosyayı elle düzenlemek
// projeyi bozma riski taşıyor ve bu kadar küçük bir köprü için karşılığı yok.
// Köprü büyürse Xcode üzerinden düzgün bir dosyaya taşınmalı.

/// Game Center köprüsü — Dart tarafına **yalnızca takma ad** verir.
///
/// Dışarı çıkan tek alan `alias`. `displayName` bilerek kullanılmıyor:
/// Apple'ın belgelediği davranışa göre `displayName`, bakan kişi oyuncunun
/// arkadaşıysa **gerçek adını** döndürüyor, değilse takma adı. Bu üründe ad
/// bir karekoda giriyor ve o kareyi tanımadığı biri okuyabiliyor; gerçek ad
/// oraya asla girmemeli. `alias` Game Center'ın herkese açık takma adı ve
/// doğru alan bu.
///
/// `gamePlayerID` ve `teamPlayerID` **hiç okunmuyor**: bunlar geliştirici
/// ekibine kapsamlı teknik kimlikler, arayüzde gösterilmeleri ve paylaşılan
/// bir yüke yazılmaları yanlış olur.
///
/// Köprü hiçbir durumda hata fırlatmıyor. Game Center kapalıysa, oyuncu
/// oturum açmadıysa, cihaz çevrimdışıysa ya da uygulama App Store Connect'te
/// tanımlı değilse sonuç `nil` oluyor ve oyun yerel kimliğiyle devam ediyor.
/// Platform kimliği bir **zenginleştirme**; eksikliği bir arıza değil.
enum GameCenterBridge {
  static let channelName = "istanbul_metro/game_center"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        // Cihazda Game Center çerçevesi her zaman var; asıl soru oyuncunun
        // oturum açıp açmadığı ve bunu `signIn` cevaplıyor.
        result(true)
      case "signIn":
        authenticate(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Oturum açmayı dener ve takma adı döndürür.
  ///
  /// `authenticateHandler` ömür boyu birden çok kez çağrılabiliyor (oyuncu
  /// ayarlardan çıkış yaparsa yeniden tetikleniyor). Flutter tarafındaki
  /// çağrı ise **tek** bir cevap bekliyor; ikinci kez cevaplamak çökme
  /// sebebi. `answered` bayrağı bunu kapatıyor.
  private static func authenticate(result: @escaping FlutterResult) {
    let player = GKLocalPlayer.local

    if player.isAuthenticated {
      result(payload(for: player))
      return
    }

    var answered = false
    let reply: (Any?) -> Void = { value in
      guard !answered else { return }
      answered = true
      DispatchQueue.main.async { result(value) }
    }

    player.authenticateHandler = { viewController, _ in
      if let viewController {
        // Game Center oturum açma ekranı. Sunulamıyorsa sessizce
        // vazgeçiliyor: oyuncuyu bir hata penceresiyle karşılamak,
        // oynamak için hiç gerekmeyen bir adım yüzünden kötü olurdu.
        guard let root = rootViewController() else {
          reply(nil)
          return
        }
        root.present(viewController, animated: true)
        return
      }

      reply(player.isAuthenticated ? payload(for: player) : nil)
    }
  }

  /// Dart tarafına giden sözlük. **Yalnızca takma ad.**
  private static func payload(for player: GKLocalPlayer) -> [String: Any]? {
    let alias = player.alias.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !alias.isEmpty else { return nil }
    return ["alias": alias]
  }

  private static func rootViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
