import 'package:flutter/material.dart';
import '../../models/device.dart';

class DeviceListItem extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const DeviceListItem({
    super.key,
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIconForOs(device.os),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      device.os,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForOs(String os) {
    final lower = os.toLowerCase();
    if (lower.contains('android')) return Icons.android;
    if (lower.contains('ios') || lower.contains('mac')) return Icons.apple;
    if (lower.contains('windows')) return Icons.window;
    if (lower.contains('linux')) return Icons.laptop_chromebook; // standard alternative
    return Icons.smartphone;
  }
}
