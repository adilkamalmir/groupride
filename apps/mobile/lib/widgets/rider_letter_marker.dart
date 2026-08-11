import 'package:flutter/material.dart';

import '../theme.dart';

/// Circular letter avatar for a rider on the map (first letter of first name).
class RiderLetterMarker extends StatelessWidget {
  const RiderLetterMarker({
    super.key,
    required this.displayName,
    required this.status,
    this.role,
    this.showName = true,
  });

  final String displayName;
  final String status;
  final String? role;
  final bool showName;

  static String initialFor(String displayName) {
    final first = displayName.trim().split(RegExp(r'\s+')).firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => '?',
        );
    if (first.isEmpty) return '?';
    return first.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    final letter = initialFor(displayName);
    final firstName = displayName.trim().isEmpty
        ? 'Rider'
        : displayName.trim().split(RegExp(r'\s+')).first;
    final isLead = (role ?? '').toLowerCase() == 'leader';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            if (isLead)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: AppTheme.signal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        if (showName) ...[
          const SizedBox(height: 2),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
