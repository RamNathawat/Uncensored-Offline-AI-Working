import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';

/// Checks and prompts the user to disable battery optimization on Android.
/// This is critical on Samsung and other aggressive OEMs that kill background apps.
class BackgroundOptimizerService {
  static const _promptedKey = 'battery_opt_prompted';

  /// Check and prompt the user if battery optimization is still enabled.
  /// Shows a dialog explaining why it's needed, then opens system settings.
  /// Only prompts on Android, and only once per install (unless optimization
  /// is still enabled).
  static Future<void> checkAndPrompt(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      final box = Hive.box('settings');

      // Check if battery optimization is already disabled for our app
      final isDisabled =
          await DisableBatteryOptimization.isBatteryOptimizationDisabled;

      if (isDisabled == true) return; // Already good

      // Check if we've already prompted the user
      final alreadyPrompted = box.get(_promptedKey, defaultValue: false) as bool;
      if (alreadyPrompted) return; // Don't nag

      // Mark as prompted
      await box.put(_promptedKey, true);

      if (!context.mounted) return;

      // Show explanation dialog
      final shouldOpen = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.battery_alert_rounded,
                  color: Colors.orange.shade400, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Background Permission',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This app needs to run in the background to:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 12),
              _BulletPoint('Continue model downloads when the screen is off'),
              SizedBox(height: 6),
              _BulletPoint('Keep AI inference running without interruption'),
              SizedBox(height: 6),
              _BulletPoint('Serve the local API to other apps'),
              SizedBox(height: 16),
              Text(
                'Please disable battery optimization for this app on the next screen.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Later',
                  style: TextStyle(color: Colors.grey.shade500)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade400,
              ),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpen == true) {
        await DisableBatteryOptimization
            .showDisableBatteryOptimizationSettings();
      }
    } catch (e) {
      debugPrint('BackgroundOptimizerService error: $e');
    }
  }

  /// Re-prompt the user (e.g. from settings). Always shows regardless of
  /// previous prompts.
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await DisableBatteryOptimization
          .showDisableBatteryOptimizationSettings();
    } catch (e) {
      debugPrint('BackgroundOptimizerService.openBatterySettings error: $e');
    }
  }

  /// Check if battery optimization is currently disabled.
  static Future<bool> isOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    try {
      return await DisableBatteryOptimization
              .isBatteryOptimizationDisabled ??
          false;
    } catch (_) {
      return false;
    }
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 8),
          child: Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
        ),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
