import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static const String manifestUrl = 'https://www.dropbox.com/scl/fi/ejz0iu6ag6py3qen7cqvn/version_manifest.json?rlkey=mfpg8vcyxswgigrytgmd2qzj3&st=kxwy80mo&dl=1';

  static Map<String, dynamic>? _latestManifest;

  static Future<Map<String, dynamic>?> fetchManifest() async {
    try {
      final response = await http.get(Uri.parse(manifestUrl));
      if (response.statusCode == 200) {
        final manifest = json.decode(response.body);
        _latestManifest = manifest;
        return manifest;
      }
    } catch (e) {
      debugPrint('UpdateService: Failed to fetch manifest: $e');
    }
    return null;
  }

  static Future<String?> getLatestVersion() async {
    if (_latestManifest != null) return _latestManifest!['version']?.toString();
    final manifest = await fetchManifest();
    return manifest?['version']?.toString();
  }

  static Future<void> checkForUpdate(BuildContext context) async {
    if (!Platform.isAndroid) {
      print('Update check: Not Android, skipping.');
      return;
    }
    print('Update check: Starting...');
    final manifest = await fetchManifest();
    print('Fetched manifest: $manifest');
    if (manifest == null) {
      print('Manifest is null.');
      return;
    }
    final latestVersion = manifest['version']?.toString();
    final apkUrl = manifest['apk_url']?.toString();
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    print('Current version: $currentVersion, Latest version: $latestVersion, APK URL: $apkUrl');
    final forceUpdate = manifest['force_update'] == true;
    final changelog = manifest['changelog']?.toString() ?? '';
    if (latestVersion == null || apkUrl == null) return;

    if (_isNewerVersion(latestVersion, currentVersion)) {
      print('A newer version is available!');
      // Show update dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: !forceUpdate,
          builder: (ctx) => AlertDialog(
            title: const Text('Update Available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A new version ($latestVersion) is available.'),
                if (changelog.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('What\'s new:', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(changelog),
                ],
              ],
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Later'),
                ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAndInstallApk(context, apkUrl);
                },
                child: const Text('Update'),
              ),
            ],
          ),
        );
      }
    } else {
      print('No update needed.');
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    latest = latest.split('+')[0];
    current = current.split('+')[0];
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();
    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static Future<void> _downloadAndInstallApk(BuildContext context, String apkUrl) async {
    bool dialogOpen = true;
    try {
      // Request storage and manage external storage permissions
      final storageStatus = await Permission.storage.request();
      final manageStatus = await Permission.manageExternalStorage.request();
      if (!storageStatus.isGranted && !manageStatus.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is required to download the update.')),
          );
        }
        return;
      }

      // Try to use the public Downloads directory first
      Directory? downloadDir;
      final publicDownloadDir = Directory('/storage/emulated/0/Download');
      if (await publicDownloadDir.exists()) {
        downloadDir = publicDownloadDir;
      } else {
        // Fallback to app-specific downloads directory
        final downloadsDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (downloadsDirs == null || downloadsDirs.isEmpty) {
          throw Exception('Cannot access downloads directory');
        }
        downloadDir = downloadsDirs.first;
      }
      await downloadDir.create(recursive: true);
      final filePath = '${downloadDir.path}/update.apk';
      final file = File(filePath);

      double progress = 0.0;
      late StateSetter dialogSetState;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            dialogSetState = setState;
            return AlertDialog(
              title: const Text('Downloading Update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 16),
                  Text('${(progress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            );
          },
        ),
      );

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await request.send();
      final contentLength = response.contentLength ?? 0;
      int bytesReceived = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response.stream) {
          bytesReceived += chunk.length;
          sink.add(chunk);
          progress = contentLength > 0 ? bytesReceived / contentLength : 0;
          if (dialogOpen) {
            dialogSetState(() {});
          }
        }
        await sink.close();
      } catch (fileError) {
        print('File write error: $fileError');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File write error: $fileError')),
          );
        }
        throw fileError;
      }

      // Debug: Show where the APK was saved
      print('APK saved to: $filePath');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('APK saved to: $filePath')),
        );
      }

      // Close the dialog
      if (context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show prompt before installing
      if (context.mounted) {
        final isPublicDownload = downloadDir != null && downloadDir.path == '/storage/emulated/0/Download';
        final shouldInstall = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ready to Install'),
            content: Text(
              isPublicDownload
                ? "The update is ready. Tap 'Install' on the next screen to complete the update."
                : "The update is ready, but may not appear in your Downloads app. Tap 'Install' to continue, or open update.apk from the app's files if needed."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Install'),
              ),
            ],
          ),
        );
        if (shouldInstall == true) {
          final result = await OpenFile.open(filePath);
          if (result.type != ResultType.done && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not launch installer. Please open update.apk from your Downloads folder.')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download update: $e')));
    }
  }
} 