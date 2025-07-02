import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'dart:typed_data';
import '../l10n/app_localizations.dart';

class ReferencesScreen extends StatefulWidget {
  const ReferencesScreen({super.key});

  @override
  State<ReferencesScreen> createState() => _ReferencesScreenState();
}

class _ReferencesScreenState extends State<ReferencesScreen> {
  bool isLoading = true;
  String? errorMessage;
  String? pdfPath;

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  Future<void> _loadPDF() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // Load PDF from assets
      final ByteData data = await rootBundle.load('assets/pdf/reference.pdf');
      final Uint8List bytes = data.buffer.asUint8List();

      // Create temporary file
      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/reference.pdf');
      await tempFile.writeAsBytes(bytes);

      setState(() {
        pdfPath = tempFile.path;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading PDF: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _openPDF() async {
    if (pdfPath != null) {
      try {
        final result = await OpenFile.open(pdfPath!);
        if (result.type != ResultType.done) {
          setState(() {
            errorMessage = 'Error opening PDF: ${result.message}';
          });
        }
      } catch (e) {
        setState(() {
          errorMessage = 'Error opening PDF: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.references),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPDF,
                        child: Text(AppLocalizations.of(context)!.retry),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.picture_as_pdf,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Reference Document',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to open in PDF viewer',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: _openPDF,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open PDF'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
} 