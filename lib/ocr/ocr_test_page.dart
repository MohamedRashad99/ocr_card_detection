import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'birth_certificate_reader.dart';

class OcrTestPage extends StatefulWidget {
  const OcrTestPage({super.key});

  @override
  State<OcrTestPage> createState() => _OcrTestPageState();
}

class _OcrTestPageState extends State<OcrTestPage> {
  final _reader = BirthCertificateReader();
  final Map<String, String> _values = {};
  bool _busy = false;
  String? _error;

  Future<void> _pickAndRead() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      setState(() {
        _values.clear();
        _error = 'No image bytes';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _values.clear();
    });

    try {
      final fields = await _reader.read(bytes);
      if (!mounted) return;
      setState(() {
        _values.addAll(fields);
      });
    } on BirthCertificateOcrException catch (e) {
      if (!mounted) return;
      setState(() {
        _values.clear();
        _error = e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _values.clear();
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _pickAndRead,
              icon: const Icon(Icons.image_search),
              label: Text(_busy ? 'Reading…' : 'Pick image'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _values.isEmpty
                  ? const Center(child: Text(''))
                  : ListView(
                      children: kBirthCertificateLabels
                          .map(
                            (label) => ListTile(
                              title: Text(label),
                              subtitle: Text(_values[label] ?? ''),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
