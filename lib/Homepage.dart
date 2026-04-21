import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  XFile? _image;
  Uint8List? _imageBytes;
  String result = "";
  bool _isUploading = false;

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final bytes = await picked.readAsBytes();

      setState(() {
        _image = picked;
        _imageBytes = bytes;
        result = "";
      });
    }
  }

  Future<void> uploadImage() async {
    if (_image == null || _imageBytes == null) {
      setState(() {
        result = "Please select an image first.";
      });
      return;
    }

    setState(() {
      _isUploading = true;
      result = "";
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse("http://localhost:5000/predict"),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _imageBytes!,
          filename: _image!.name,
        ),
      );

      final response = await request.send();
      final res = await http.Response.fromStream(response);

      setState(() {
        if (response.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final predictedClass = data['class']?.toString() ?? 'Unknown';
          final confidence = (data['confidence'] as num?)?.toDouble();

          result = confidence != null
              ? 'Prediction: $predictedClass\nConfidence: ${(confidence * 100).toStringAsFixed(2)}%'
              : 'Prediction: $predictedClass';
        } else {
          result = "Upload failed (${response.statusCode}): ${res.body}";
        }
      });
    } catch (error) {
      setState(() {
        result = "Upload error: $error";
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bamboo Disease Detector")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: _imageBytes != null
                    ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                    : const Text("No image selected"),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: pickImage,
              child: const Text("Select Image"),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isUploading ? null : uploadImage,
              child: Text(_isUploading ? "Uploading..." : "Predict"),
            ),
            const SizedBox(height: 16),
            Text(
              result,
              style: const TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
