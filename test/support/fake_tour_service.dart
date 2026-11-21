import 'package:spectrumpit/src/services/tour_service.dart';

class FakeTourService implements TourService {
  FakeTourService({this.seen = false});

  bool seen;

  @override
  Future<bool> isSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
  }
}
