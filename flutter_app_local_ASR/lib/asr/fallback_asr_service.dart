import 'dart:async';

import 'asr_engine.dart';

class FallbackAsrService implements AsrEngine {
  FallbackAsrService({required List<AsrEngine> engines}) : _engines = engines {
    for (final engine in _engines) {
      _subscriptions.add(engine.segments.listen(_segments.add));
      _subscriptions.add(engine.partials.listen(_partials.add));
      _subscriptions.add(
        engine.status.listen((message) {
          _status.add('${engine.name}: $message');
        }),
      );
    }
  }

  final List<AsrEngine> _engines;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final StreamController<AsrSegment> _segments =
      StreamController<AsrSegment>.broadcast();
  final StreamController<AsrPartial> _partials =
      StreamController<AsrPartial>.broadcast();
  final StreamController<String> _status = StreamController<String>.broadcast();

  AsrEngine? _activeEngine;
  Set<String>? _enabledEngineNames;

  @override
  String get name => _activeEngine?.name ?? 'ASR fallback chain';

  String? get activeEngineName => _activeEngine?.name;

  @override
  Stream<AsrSegment> get segments => _segments.stream;

  @override
  Stream<AsrPartial> get partials => _partials.stream;

  @override
  Stream<String> get status => _status.stream;

  void useOnlyEngine(String engineName) {
    _enabledEngineNames = {engineName};
  }

  Iterable<AsrEngine> get _enabledEngines {
    final enabledEngineNames = _enabledEngineNames;
    if (enabledEngineNames == null) {
      return _engines;
    }
    return _engines.where((engine) => enabledEngineNames.contains(engine.name));
  }

  @override
  Future<AsrAvailability> checkAvailability() async {
    final reasons = <String>[];
    for (final engine in _enabledEngines) {
      final availability = await engine.checkAvailability();
      if (availability.isAvailable) {
        return const AsrAvailability.available();
      }
      reasons.add('${engine.name}: ${availability.reason}');
    }

    return AsrAvailability.unavailable(reasons.join('\n'));
  }

  @override
  Future<void> start() async {
    final errors = <String>[];

    for (final engine in _enabledEngines) {
      final availability = await engine.checkAvailability();
      if (!availability.isAvailable) {
        errors.add('${engine.name}: ${availability.reason}');
        continue;
      }

      try {
        _status.add('Trying ${engine.name}');
        await engine.start();
        _activeEngine = engine;
        _status.add('Using ${engine.name}');
        return;
      } catch (error) {
        errors.add('${engine.name}: $error');
      }
    }

    throw StateError('No ASR engine is available.\n${errors.join('\n')}');
  }

  @override
  Future<void> stop() async {
    final engine = _activeEngine;
    if (engine == null) {
      return;
    }

    await engine.stop();
    _status.add('Stopped ${engine.name}');
    _activeEngine = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final engine in _engines) {
      await engine.dispose();
    }
    await _segments.close();
    await _partials.close();
    await _status.close();
  }
}
