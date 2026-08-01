import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'log_service.dart';

class UpdateService extends GetxService {
  final LogService _log = Get.find<LogService>();
  
  static const String repoOwner = 'RamNathawat';
  static const String repoName = 'Uncensored-Offline-AI-Working';
  static const String latestReleaseApi = 'https://api.github.com/repos/$repoOwner/$repoName/releases/tags/latest';

  final isChecking = false.obs;
  final updateAvailable = false.obs;
  String? latestApkUrl;
  DateTime? latestReleaseDate;

  Future<UpdateService> init() async {
    // Check on startup silently
    checkForUpdates(silent: true);
    return this;
  }

  /// Checks the GitHub API for the latest release.
  Future<void> checkForUpdates({bool silent = false}) async {
    if (isChecking.value) return;
    
    isChecking.value = true;
    try {
      final response = await http.get(Uri.parse(latestReleaseApi));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Find the Android APK asset
        final assets = data['assets'] as List;
        for (var asset in assets) {
          final name = asset['name'] as String;
          if (name.endsWith('.apk') && name.contains('arm64')) {
            latestApkUrl = asset['browser_download_url'];
            latestReleaseDate = DateTime.parse(data['published_at']);
            break;
          }
        }
        
        if (latestReleaseDate != null) {
          // Compare with local app install/update time or build number if we had one
          // Since we use rolling releases, any newer published_at than 24 hours ago 
          // or we can just always allow downloading the 'latest' if they click check.
          // For a true version check, we'd compare tags.
          // Since our tag is always 'latest', we'll just say update is available if it exists.
          updateAvailable.value = true;
          
          if (!silent) {
            Get.defaultDialog(
              title: 'Update Available',
              middleText: 'A new version of Anima is available!',
              textConfirm: 'Download',
              textCancel: 'Cancel',
              confirmTextColor: Get.context?.theme.colorScheme.onPrimary ?? const Color(0xFFFFFFFF),
              buttonColor: Get.context?.theme.colorScheme.primary ?? const Color(0xFF6366F1),
              onConfirm: () {
                Get.back();
                downloadUpdate();
              },
            );
          }
        } else {
          if (!silent) {
            Get.snackbar('Up to date', 'No new APK found in the latest release.');
          }
        }
      } else {
        if (!silent) {
          Get.snackbar('Error', 'Failed to check for updates. HTTP ${response.statusCode}');
        }
      }
    } catch (e) {
      _log.error('Failed to check for updates: $e', source: 'UpdateService');
      if (!silent) {
        Get.snackbar('Error', 'Failed to check for updates: $e');
      }
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> downloadUpdate() async {
    if (latestApkUrl == null) return;
    final uri = Uri.parse(latestApkUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      Get.snackbar('Error', 'Could not open download link.');
    }
  }
}
