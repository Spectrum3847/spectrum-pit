import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:share_plus/share_plus.dart';

import 'schedule_image.dart';

bool get scheduleImageSaves =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

Future<bool> shareScheduleImage(ScheduleImage image, {Rect? origin}) async {
  final file = XFile.fromData(
    image.bytes,
    mimeType: 'image/png',
    name: image.fileName,
  );
  if (scheduleImageSaves) {
    final location = await getSaveLocation(
      suggestedName: image.fileName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG image', extensions: ['png']),
      ],
    );
    if (location == null) return false;
    await file.saveTo(location.path);
    return true;
  }
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [image.fileName],
      title: image.title,
      sharePositionOrigin: origin,
    ),
  );
  return result.status != ShareResultStatus.dismissed;
}
