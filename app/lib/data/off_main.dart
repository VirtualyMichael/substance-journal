import 'dart:io';
import 'dart:isolate';

final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Runs [work] on a background isolate so heavy calculations never freeze the screen. [work] must
/// only capture plain data (rows, reference data, settings), never the database or widgets. In
/// tests it runs inline, where fake time cannot wait for another isolate.
Future<T> offMain<T>(T Function() work) => _inTest ? Future.value(work()) : Isolate.run(work);
