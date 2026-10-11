import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/teacher_note.dart';

class NoteStorageService {
  static const String _key = 'teacher_notes_v1';

  Future<List<TeacherNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => TeacherNote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotes(List<TeacherNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}