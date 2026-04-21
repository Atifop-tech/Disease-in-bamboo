import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _predictUrl = 'http://localhost:5000/predict';

  final List<_PredictionRecord> _history = <_PredictionRecord>[];

  XFile? _image;
  Uint8List? _imageBytes;
  String _statusMessage = 'Select a bamboo leaf photo to start the analysis.';
  String? _predictedClass;
  double? _confidence;
  bool _isUploading = false;

  Future<void> _showImageSourcePicker() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF0E291C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Choose image source',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Capture a fresh sample or pick a saved photo.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _SourceTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Gallery',
                  subtitle: 'Use an existing image',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 12),
                _SourceTile(
                  icon: Icons.photo_camera_rounded,
                  title: 'Camera',
                  subtitle: 'Capture a new sample',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source != null) {
      await _pickImage(source);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
    );

    if (picked == null) {
      return;
    }

    final Uint8List bytes = await picked.readAsBytes();
    setState(() {
      _image = picked;
      _imageBytes = bytes;
      _predictedClass = null;
      _confidence = null;
      _statusMessage = 'Image ready. Run analysis to detect bamboo disease.';
    });
  }

  Future<void> _uploadImage() async {
    if (_image == null || _imageBytes == null) {
      setState(() {
        _statusMessage = 'Please select an image first.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Analyzing leaf condition...';
      _predictedClass = null;
      _confidence = null;
    });

    try {
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        Uri.parse(_predictUrl),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _imageBytes!,
          filename: _image!.name,
        ),
      );

      final http.StreamedResponse response = await request.send();
      final http.Response res = await http.Response.fromStream(response);

      if (response.statusCode != 200) {
        setState(() {
          _statusMessage = 'Upload failed (${response.statusCode}): ${res.body}';
        });
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(res.body) as Map<String, dynamic>;
      final String predictedClass = data['class']?.toString() ?? 'Unknown';
      final double? confidence = (data['confidence'] as num?)?.toDouble();
      final String message = confidence != null
          ? 'Prediction complete. Confidence ${(confidence * 100).toStringAsFixed(1)}%.'
          : 'Prediction complete.';

      setState(() {
        _predictedClass = predictedClass;
        _confidence = confidence;
        _statusMessage = message;
        _history.insert(
          0,
          _PredictionRecord(
            label: predictedClass,
            confidence: confidence,
            imageName: _image!.name,
            analyzedAt: DateTime.now(),
          ),
        );
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Upload error: $error';
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _clearSession() {
    setState(() {
      _image = null;
      _imageBytes = null;
      _predictedClass = null;
      _confidence = null;
      _statusMessage = 'Session cleared. Select a new image to continue.';
    });
  }

  Future<void> _copyReport() async {
    if (_predictedClass == null) {
      setState(() {
        _statusMessage = 'Run an analysis first to copy the report.';
      });
      return;
    }

    final String report = _buildReportText();
    await Clipboard.setData(ClipboardData(text: report));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard.')),
    );
  }

  String _buildReportText() {
    final String confidenceText = _confidence == null
        ? 'N/A'
        : '${(_confidence! * 100).toStringAsFixed(1)}%';
    final String imageName = _image?.name ?? 'Unknown image';

    return 'Bamboo Disease Detector\n'
        'Image: $imageName\n'
        'Prediction: ${_predictedClass ?? 'Not available'}\n'
        'Confidence: $confidenceText\n'
        'Status: $_statusMessage';
  }

  List<String> _careTipsFor(String? label) {
    switch (label) {
      case 'Fungal_Rust':
        return <String>[
          'Remove heavily infected leaves to reduce fungal spread.',
          'Improve airflow and avoid wet foliage late in the day.',
          'Inspect nearby plants for matching rust spots.',
        ];
      case 'Mosaic_Virus':
        return <String>[
          'Isolate the plant quickly to reduce vector transmission.',
          'Sanitize cutting tools before touching healthy plants.',
          'Monitor new leaves for streaking and distorted growth.',
        ];
      case 'Sooty_Mold':
        return <String>[
          'Check for aphids or scale insects producing honeydew.',
          'Wash affected surfaces gently and improve plant hygiene.',
          'Control the insect source to prevent mold from returning.',
        ];
      case 'Yellow_Bamboo':
        return <String>[
          'Review watering consistency and soil drainage first.',
          'Check for nutrient imbalance or root stress.',
          'Track whether yellowing is localized or plant-wide.',
        ];
      case 'Healthy':
        return <String>[
          'Leaf appears healthy. Keep observing for color or texture shifts.',
          'Maintain balanced watering and good air circulation.',
          'Store this result as a visual baseline for future comparisons.',
        ];
      default:
        return <String>[
          'Capture a sharper close-up with good natural lighting.',
          'Avoid blurred images and keep one leaf dominant in frame.',
          'Run another scan if the result seems inconsistent.',
        ];
    }
  }

  Color _accentForLabel(String? label) {
    switch (label) {
      case 'Healthy':
        return const Color(0xFF56D66B);
      case 'Mosaic_Virus':
        return const Color(0xFFFFA94D);
      case 'Fungal_Rust':
        return const Color(0xFFFF7A59);
      case 'Sooty_Mold':
        return const Color(0xFF7C8EA6);
      case 'Yellow_Bamboo':
        return const Color(0xFFF3D34A);
      default:
        return const Color(0xFF59E3A7);
    }
  }

  String _severityLabel(double? confidence) {
    if (confidence == null) {
      return 'Awaiting result';
    }
    if (confidence >= 0.9) {
      return 'High certainty';
    }
    if (confidence >= 0.7) {
      return 'Moderate certainty';
    }
    return 'Low certainty';
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _accentForLabel(_predictedClass);
    final bool hasResult = _predictedClass != null;

    return Scaffold(
      backgroundColor: const Color(0xFF06110C),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF08140D),
              Color(0xFF0E2A1D),
              Color(0xFF07100B),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool isWide = constraints.maxWidth >= 980;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroPanel(
                          statusMessage: _statusMessage,
                          hasImage: _imageBytes != null,
                          imageName: _image?.name,
                          onPickImage: _showImageSourcePicker,
                          onAnalyze: _isUploading ? null : _uploadImage,
                          onClear: _clearSession,
                          isUploading: _isUploading,
                        ),
                        const SizedBox(height: 20),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  children: [
                                    _PreviewCard(
                                      imageBytes: _imageBytes,
                                      predictedClass: _predictedClass,
                                      accent: accent,
                                    ),
                                    const SizedBox(height: 20),
                                    _ResultInsightCard(
                                      predictedClass: _predictedClass,
                                      confidence: _confidence,
                                      accent: accent,
                                      severityLabel: _severityLabel(_confidence),
                                      onCopy: hasResult ? _copyReport : null,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _CareTipsCard(
                                      accent: accent,
                                      tips: _careTipsFor(_predictedClass),
                                    ),
                                    const SizedBox(height: 20),
                                    _HistoryCard(history: _history),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _PreviewCard(
                                imageBytes: _imageBytes,
                                predictedClass: _predictedClass,
                                accent: accent,
                              ),
                              const SizedBox(height: 20),
                              _ResultInsightCard(
                                predictedClass: _predictedClass,
                                confidence: _confidence,
                                accent: accent,
                                severityLabel: _severityLabel(_confidence),
                                onCopy: hasResult ? _copyReport : null,
                              ),
                              const SizedBox(height: 20),
                              _CareTipsCard(
                                accent: accent,
                                tips: _careTipsFor(_predictedClass),
                              ),
                              const SizedBox(height: 20),
                              _HistoryCard(history: _history),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.statusMessage,
    required this.hasImage,
    required this.imageName,
    required this.onPickImage,
    required this.onAnalyze,
    required this.onClear,
    required this.isUploading,
  });

  final String statusMessage;
  final bool hasImage;
  final String? imageName;
  final VoidCallback onPickImage;
  final VoidCallback? onAnalyze;
  final VoidCallback onClear;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF123322),
            Color(0xFF0B2016),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 20,
        spacing: 20,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1A9CF7BE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Plant Health Intelligence',
                    style: TextStyle(
                      color: Color(0xFF9CF7BE),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Bamboo disease detection with a sharper field-ready dashboard.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  statusMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                if (imageName != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Current sample: $imageName',
                    style: const TextStyle(
                      color: Color(0xFFE2FFEE),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: onPickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9CF7BE),
                    foregroundColor: const Color(0xFF052B17),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text(
                    'Select or capture image',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: hasImage ? onAnalyze : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF183F2B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF173224),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: Icon(
                    isUploading
                        ? Icons.autorenew_rounded
                        : Icons.biotech_rounded,
                  ),
                  label: Text(
                    isUploading ? 'Analyzing...' : 'Run diagnosis',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.16)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text(
                    'Reset session',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.imageBytes,
    required this.predictedClass,
    required this.accent,
  });

  final Uint8List? imageBytes;
  final String? predictedClass;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.eco_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Leaf Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      predictedClass == null
                          ? 'Upload an image to inspect its condition.'
                          : 'Latest classification: $predictedClass',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 16 / 10,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: imageBytes == null
                  ? Container(
                      key: const ValueKey<String>('empty'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color(0xFF10281C),
                            Color(0xFF0A1711),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_search_rounded,
                              color: Colors.white54,
                              size: 52,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No sample selected yet',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      key: const ValueKey<String>('image'),
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.58),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            bottom: 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.42),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.14),
                                ),
                              ),
                              child: Text(
                                predictedClass ?? 'Ready for analysis',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultInsightCard extends StatelessWidget {
  const _ResultInsightCard({
    required this.predictedClass,
    required this.confidence,
    required this.accent,
    required this.severityLabel,
    required this.onCopy,
  });

  final String? predictedClass;
  final double? confidence;
  final Color accent;
  final String severityLabel;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final String confidenceText = confidence == null
        ? '--'
        : '${(confidence! * 100).toStringAsFixed(1)}%';
    final double progressValue = confidence?.clamp(0.0, 1.0) ?? 0.0;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Diagnosis Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy report'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricChip(
                label: 'Prediction',
                value: predictedClass ?? 'Not analyzed',
                accent: accent,
              ),
              _MetricChip(
                label: 'Confidence',
                value: confidenceText,
                accent: accent,
              ),
              _MetricChip(
                label: 'Signal',
                value: severityLabel,
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Model confidence',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 14,
              value: progressValue,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            confidence == null
                ? 'Confidence will appear after analysis.'
                : 'Higher confidence suggests the model saw a stronger match with known patterns.',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CareTipsCard extends StatelessWidget {
  const _CareTipsCard({
    required this.accent,
    required this.tips,
  });

  final Color accent;
  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: accent),
              const SizedBox(width: 10),
              const Text(
                'Field Recommendations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final String tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.history,
  });

  final List<_PredictionRecord> history;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Scans',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Track your last diagnoses in the current session.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (history.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No history yet. Each completed analysis appears here.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            Column(
              children: history.take(5).map((record) {
                final String confidenceText = record.confidence == null
                    ? '--'
                    : '${(record.confidence! * 100).toStringAsFixed(1)}%';
                final String timeText =
                    '${record.analyzedAt.hour.toString().padLeft(2, '0')}:${record.analyzedAt.minute.toString().padLeft(2, '0')}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9CF7BE).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.analytics_rounded,
                          color: Color(0xFF9CF7BE),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              record.imageName,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            confidenceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeText,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF9CF7BE).withOpacity(0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF9CF7BE)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _PredictionRecord {
  const _PredictionRecord({
    required this.label,
    required this.confidence,
    required this.imageName,
    required this.analyzedAt,
  });

  final String label;
  final double? confidence;
  final String imageName;
  final DateTime analyzedAt;
}
