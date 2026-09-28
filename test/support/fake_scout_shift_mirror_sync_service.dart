import 'dart:async';

import 'package:spectrumpit/src/models/scout_shift_mirror.dart';
import 'package:spectrumpit/src/services/scout_shift_mirror_sync_service.dart';

class FakeScoutShiftMirrorSyncService implements ScoutShiftMirrorSyncService {
  final StreamController<List<ScoutShiftMirror>> _controller =
      StreamController<List<ScoutShiftMirror>>.broadcast();

  void emit(List<ScoutShiftMirror> items) => _controller.add(items);

  @override
  Stream<List<ScoutShiftMirror>> streamAll() => _controller.stream;
}
