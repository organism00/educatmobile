import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

class FilePickerService {
  static Future<Map<String, dynamic>?> pickFile({
    List<String> allowedExtensions = const ['pdf', 'jpg', 'jpeg', 'png'],
  }) async {
    try {
      // For images, use image_picker for better UX
      if (allowedExtensions.any((ext) => ['jpg', 'jpeg', 'png'].contains(ext))) {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        );

        if (image != null) {
          final file = File(image.path);
          return {
            'path': image.path,
            'name': image.name,
            'bytes': await file.readAsBytes(),
            'size': await file.length(),
          };
        }
        return null;
      }

      // For PDFs, use file_selector
      final typeGroup = XTypeGroup(
        label: 'PDF Files',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
      );

      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

      if (file != null) {
        final fileObj = File(file.path);
        return {
          'path': file.path,
          'name': file.name,
          'bytes': await fileObj.readAsBytes(),
          'size': await fileObj.length(),
        };
      }
      return null;
    } catch (e) {
      print('Error picking file: $e');
      return null;
    }
  }
}