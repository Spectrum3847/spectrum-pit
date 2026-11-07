import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/driver_schedule.dart';
import '../theme/pit_palette.dart';

class ScheduleImage {
  const ScheduleImage({
    required this.bytes,
    required this.title,
    required this.fileName,
  });

  final Uint8List bytes;
  final String title;
  final String fileName;
}

Future<ScheduleImage> scheduleImage(
  DriverSchedule schedule,
  ScheduleGroup group,
) async {
  final labels = schedule.config.roleLabels;
  final shown = schedule.shownRoleKeys(group);
  final slots = schedule.slotsFor(group);
  final team = schedule.teamFor(group);
  final event = schedule.matches?.eventKey;

  final title = [?group.label, if (team != null) 'team $team'].join(', ');
  final heading = title.isEmpty ? 'Drive team schedule' : title;
  final subtitle = [
    ?event,
    '${slots.length} match${slots.length == 1 ? '' : 'es'}',
  ].join(', ');
  final slug = [
    ?event,
    ?group.label,
    if (team != null) 'team $team',
  ].join(' ').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final fileName = '${slug.isEmpty ? '' : '$slug-'}schedule.png';

  final header = ['Match', for (final key in shown) labels[key] ?? key];
  final rows = [
    for (final slot in slots)
      [
        schedule.slotLabel(slot),
        for (final key in shown)
          schedule.nameAt(key, slot).isEmpty ? '-' : schedule.nameAt(key, slot),
      ],
  ];

  const sans = 'IBM Plex Sans';
  const margin = 24.0, pad = 14.0, titleHeight = 64.0;
  const headHeight = 34.0, rowHeight = 32.0, scale = 2.0;

  TextPainter text(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  const titleStyle = TextStyle(
    fontFamily: sans,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: PitPalette.lightInk,
  );
  const subStyle = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    color: PitPalette.lightInkMuted,
  );
  const headStyle = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: PitPalette.lightInk,
  );
  const matchStyle = TextStyle(
    fontFamily: 'IBM Plex Mono',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: PitPalette.lightInkMuted,
  );
  const nameStyle = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    color: PitPalette.lightInk,
  );
  final emptyStyle = nameStyle.copyWith(color: PitPalette.lightInkMuted);

  final cells = [
    for (final row in rows)
      [
        for (var i = 0; i < row.length; i++)
          text(
            row[i],
            i == 0
                ? matchStyle
                : row[i] == '-'
                ? emptyStyle
                : nameStyle,
          ),
      ],
  ];
  final heads = [for (final label in header) text(label, headStyle)];
  var widths = [
    for (var i = 0; i < header.length; i++)
      pad * 2 +
          [heads[i].width, for (final row in cells) row[i].width].reduce(max),
  ];
  final tableWidth = widths.reduce((a, b) => a + b);
  final titlePainter = text(heading, titleStyle);
  final subPainter = text(subtitle, subStyle);

  final innerWidth = [
    tableWidth,
    titlePainter.width,
    subPainter.width,
    320.0,
  ].reduce(max);
  if (widths.length > 1) {
    final extra = (innerWidth - tableWidth) / (widths.length - 1);
    widths = [widths.first, for (final w in widths.skip(1)) w + extra];
  }
  final tableHeight = headHeight + rows.length * rowHeight;
  final width = innerWidth + margin * 2;
  final height = margin + titleHeight + tableHeight + margin;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = PitPalette.lightCanvas,
  );
  titlePainter.paint(canvas, const Offset(margin, margin));
  subPainter.paint(canvas, Offset(margin, margin + titlePainter.height + 4));

  const top = margin + titleHeight;
  final box = RRect.fromRectAndRadius(
    Rect.fromLTWH(margin, top, innerWidth, tableHeight),
    const Radius.circular(PitPalette.radiusSm),
  );
  canvas
    ..save()
    ..clipRRect(box)
    ..drawRect(
      Rect.fromLTWH(margin, top, innerWidth, headHeight),
      Paint()..color = PitPalette.lightSurfaceStrong,
    );
  for (var r = 0; r < rows.length; r++) {
    canvas.drawRect(
      Rect.fromLTWH(
        margin,
        top + headHeight + r * rowHeight,
        innerWidth,
        rowHeight,
      ),
      Paint()
        ..color = r.isOdd ? PitPalette.lightSurface : PitPalette.lightCanvas,
    );
  }
  canvas
    ..restore()
    ..drawRRect(
      box.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = PitPalette.lightOutline,
    );

  var x = margin;
  for (var i = 0; i < header.length; i++) {
    final head = heads[i];
    head.paint(canvas, Offset(x + pad, top + (headHeight - head.height) / 2));
    for (var r = 0; r < cells.length; r++) {
      final cell = cells[r][i];
      cell.paint(
        canvas,
        Offset(
          x + pad,
          top + headHeight + r * rowHeight + (rowHeight - cell.height) / 2,
        ),
      );
    }
    x += widths[i];
  }

  final image = await recorder.endRecording().toImage(
    (width * scale).ceil(),
    (height * scale).ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return ScheduleImage(
    bytes: data!.buffer.asUint8List(),
    title: heading,
    fileName: fileName,
  );
}
