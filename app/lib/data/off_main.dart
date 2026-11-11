import 'dart:async';
import 'dart:io';
import 'dart:isolate';

final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Runs [work] on a background isolate so heavy calculations never freeze the screen. [work] must
/// only capture plain data (rows, reference data, settings), never the database or widgets. In
/// tests it runs inline, where fake time cannot wait for another isolate.
///
/// If the isolate cannot be used (a closure that captured something unsendable), it falls back to
/// running inline, so a screen can never be left waiting forever.
Future<T> offMain<T>(FutureOr<T> Function() work) async {
  if (_inTest) return work();
  try {
    return await Isolate.run(work);
  } on Object {
    return work();
  }
}
