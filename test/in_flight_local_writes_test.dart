import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/in_flight_local_writes.dart';

void main() {
  test('records nothing outside a window', () {
    final writes = InFlightLocalWrites<String>();
    expect(writes.isRecording, isFalse);
    writes.recordPush('a', 'local', WriteToken(1));
    writes.recordDelete('b', WriteToken(1));
    final resolved = writes.resolve(FetchWindow(0), <String, String>{
      'b': 'remote',
    });
    expect(resolved, <String, String>{'b': 'remote'});
  });

  test('a push during the window survives a snapshot that omits it', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));
    expect(
      writes.resolve(window, <String, String>{'b': 'remote'}),
      <String, String>{'b': 'remote', 'a': 'local'},
    );
  });

  test('a delete during the window is not resurrected by the snapshot', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordDelete('a', WriteToken(1));
    expect(
      writes.resolve(window, <String, String>{'a': 'remote', 'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
  });

  test('a push wins over the snapshot value for the same id', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));
    expect(
      writes.resolve(window, <String, String>{'a': 'stale'}),
      <String, String>{'a': 'local'},
    );
  });

  test('delete then push on one id in one window resolves to the push', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordDelete('a', WriteToken(1));
    writes.recordPush('a', 'local', WriteToken(2));
    expect(
      writes.resolve(window, <String, String>{'a': 'stale'}),
      <String, String>{'a': 'local'},
    );
  });

  test('push then delete on one id in one window resolves to the delete', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));
    writes.recordDelete('a', WriteToken(2));
    expect(writes.resolve(window, <String, String>{'a': 'stale'}), isEmpty);
  });

  test('resolve closes the window so the next fetch starts clean', () {
    final writes = InFlightLocalWrites<String>();
    final first = writes.beginFetch();
    writes.recordDelete('a', WriteToken(1));
    writes.resolve(first, <String, String>{});
    expect(writes.isRecording, isFalse);

    final second = writes.beginFetch();
    expect(
      writes.resolve(second, <String, String>{'a': 'remote'}),
      <String, String>{'a': 'remote'},
    );
  });

  test('abandonFetch drops the window without applying it', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));
    writes.abandonFetch(window);
    expect(writes.isRecording, isFalse);
    expect(
      writes.resolve(window, <String, String>{'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
  });

  test('beginFetch discards a window left open by a previous fetch', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a', WriteToken(1));
    final second = writes.beginFetch();
    expect(
      writes.resolve(second, <String, String>{'a': 'remote'}),
      <String, String>{'a': 'remote'},
    );
  });

  test('a superseded fetch cannot close the window a newer one opened', () {
    final writes = InFlightLocalWrites<String>();
    final stale = writes.beginFetch();
    final fresh = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));

    expect(
      writes.resolve(stale, <String, String>{'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
    expect(writes.isRecording, isTrue);

    expect(
      writes.resolve(fresh, <String, String>{'b': 'remote'}),
      <String, String>{'b': 'remote', 'a': 'local'},
    );
  });

  test('a superseded fetch cannot abandon the window a newer one opened', () {
    final writes = InFlightLocalWrites<String>();
    final stale = writes.beginFetch();
    final fresh = writes.beginFetch();
    writes.recordPush('a', 'local', WriteToken(1));

    writes.abandonFetch(stale);
    expect(writes.isRecording, isTrue);
    expect(writes.resolve(fresh, <String, String>{}), <String, String>{
      'a': 'local',
    });
  });

  test(
    'a write outstanding before the window opens still survives resolve',
    () {
      final writes = InFlightLocalWrites<String>();
      writes.beginPush('a', 'local');
      final window = writes.beginFetch();
      expect(
        writes.resolve(window, <String, String>{'b': 'remote'}),
        <String, String>{'b': 'remote', 'a': 'local'},
      );
    },
  );

  test('an outstanding delete still survives resolve', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginDelete('a');
    final window = writes.beginFetch();
    expect(
      writes.resolve(window, <String, String>{'a': 'remote', 'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
  });

  test('endWrite stops an outstanding write from being applied again', () {
    final writes = InFlightLocalWrites<String>();
    final token = writes.beginPush('a', 'local');
    writes.endWrite('a', token);
    final window = writes.beginFetch();
    expect(
      writes.resolve(window, <String, String>{'a': 'remote'}),
      <String, String>{'a': 'remote'},
    );
  });

  test('endWrite ignores a token a newer write for the same id replaced', () {
    final writes = InFlightLocalWrites<String>();
    final stale = writes.beginPush('a', 'stale-write');
    writes.beginPush('a', 'fresh-write');
    writes.endWrite('a', stale);
    final window = writes.beginFetch();
    expect(writes.resolve(window, <String, String>{}), <String, String>{
      'a': 'fresh-write',
    });
  });

  test('a completed write beats an outstanding write with an older token', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginPush('a', 'outstanding');
    final window = writes.beginFetch();
    writes.recordPush('a', 'landed', WriteToken(2));
    expect(writes.resolve(window, <String, String>{}), <String, String>{
      'a': 'landed',
    });
  });

  test('an outstanding write beats a completed write with an older token', () {
    final writes = InFlightLocalWrites<String>();
    final window = writes.beginFetch();

    writes.recordPush('a', 'first-write-landed', WriteToken(0));
    writes.beginPush('a', 'second-write-still-outstanding');
    expect(writes.resolve(window, <String, String>{}), <String, String>{
      'a': 'second-write-still-outstanding',
    });
  });
}
