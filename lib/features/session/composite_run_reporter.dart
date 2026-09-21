import 'run_report.dart';

/// Biten koşuyu birden fazla dinleyiciye iletir.
///
/// Oyun controller'ı **tek** bir rapor hedefi tanır; kaç sistemin dinlediği
/// onu ilgilendirmez. Bugün iki dinleyici var (günlük görevler ve pasaport
/// başarımları); üçüncüsü eklendiğinde yedi oyun ekranının hiçbirine
/// dokunmak gerekmez.
class CompositeRunReporter implements RunReporter {
  const CompositeRunReporter(this.targets);

  final List<RunReporter> targets;

  @override
  void reportRunStarted() {
    for (final target in targets) {
      target.reportRunStarted();
    }
  }

  @override
  void reportRun(RunReport report) {
    for (final target in targets) {
      target.reportRun(report);
    }
  }
}
