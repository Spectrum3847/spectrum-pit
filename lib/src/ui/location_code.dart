import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

class LocationCode extends StatelessWidget {
  const LocationCode({required this.label, required this.code, super.key});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final value = code.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: muted),
        ),
        const SizedBox(width: 6),
        Text(
          value.isEmpty ? '--' : value.toUpperCase(),
          style: pitCodeStyle(
            context,
            color: value.isEmpty ? muted : PitPalette.inkOf(context),
          ),
        ),
      ],
    );
  }
}
