# Auto-Update Setup Guide

This guide explains how to set up the auto-update system using Dropbox for your MOI Snipers app.

## Prerequisites

1. A Dropbox account
2. The latest APK file of your app
3. The version manifest file

## Step 1: Prepare Your Files

### 1.1 Create Version Manifest
The `version_manifest.json` file is already created in your project. Update it with your new version information:

```json
{
  "version": "1.0.1",
  "apk_file": "moi_snipers_1.0.1.apk",
  "changelog": "• Your update description here\n• Bug fixes\n• New features",
  "force_update": false,
  "min_version": "1.0.0",
  "release_date": "2024-01-15",
  "file_size": "23.6MB"
}
```

### 1.2 Build New APK
```bash
flutter build apk --release
```

## Step 2: Upload to Dropbox

### 2.1 Upload APK File
1. Go to your Dropbox account
2. Create a folder called "MOI_Snipers_Updates"
3. Upload your APK file (e.g., `moi_snipers_1.0.1.apk`) to this folder
4. Right-click on the APK file and select "Share"
5. Click "Create a link"
6. Copy the link (it will look like: `https://www.dropbox.com/s/xxxxx/moi_snipers_1.0.1.apk?dl=0`)
7. Convert it to a direct download link by replacing `?dl=0` with `?dl=1`
8. Extract the file ID from the URL (the part after `/s/` and before the filename)

### 2.2 Upload Version Manifest
1. Upload the `version_manifest.json` file to the same Dropbox folder
2. Create a share link for the manifest file
3. Convert to direct download link
4. Extract the file ID

## Step 3: Update App Configuration

### 3.1 Update UpdateService
Open `lib/update_service.dart` and replace the placeholder URLs:

```dart
static const String _manifestUrl = 'https://dl.dropboxusercontent.com/s/YOUR_MANIFEST_ID/version_manifest.json';
static const String _apkBaseUrl = 'https://dl.dropboxusercontent.com/s/YOUR_APK_ID/';
```

Replace:
- `YOUR_MANIFEST_ID` with the file ID from your manifest file
- `YOUR_APK_ID` with the file ID from your APK file

### 3.2 Update App Version
In `pubspec.yaml`, update the version number:

```yaml
version: 1.0.1+2
```

## Step 4: Test the Update System

1. Install the current version of your app on a device
2. Build and install the new version with updated URLs
3. The app should automatically check for updates and show the update dialog

## How It Works

1. **Background Check**: The app checks for updates 2 seconds after startup
2. **Version Comparison**: Compares current version with the latest version from Dropbox
3. **Update Dialog**: Shows update information if a new version is available
4. **Download & Install**: Downloads the APK and installs it automatically
5. **Scheduling**: If user dismisses, checks again in 24 hours

## Update Process

1. User opens the app
2. App checks Dropbox for new version (in background)
3. If update available, shows dialog with:
   - Version information
   - Changelog
   - Update/Later buttons
4. User clicks "Update Now"
5. App downloads APK from Dropbox
6. App installs the new version
7. User restarts app to complete update

## Security Considerations

- Only use trusted Dropbox links
- Verify APK integrity before installation
- Consider adding checksums to the manifest
- Test updates thoroughly before releasing

## Troubleshooting

### Update Not Showing
- Check Dropbox links are accessible
- Verify version numbers in manifest and pubspec.yaml
- Check internet connectivity
- Review console logs for errors

### Download Fails
- Verify APK file is accessible via direct link
- Check file size and permissions
- Ensure sufficient storage space on device

### Installation Fails
- Verify APK is properly signed
- Check Android permissions
- Ensure unknown sources installation is enabled

## File Structure on Dropbox

```
MOI_Snipers_Updates/
├── version_manifest.json
├── moi_snipers_1.0.0.apk
├── moi_snipers_1.0.1.apk
└── moi_snipers_1.0.2.apk
```

## Example URLs

After setup, your URLs should look like:
- Manifest: `https://dl.dropboxusercontent.com/s/abc123def456/version_manifest.json`
- APK Base: `https://dl.dropboxusercontent.com/s/xyz789uvw012/`

The app will automatically append the APK filename from the manifest. 