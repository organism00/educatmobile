import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _subjectsKey = 'teacher_subjects';
  static const String _pendingSubjectsKey = 'pending_subjects';
  static const String _pendingScoresKey = 'pending_scores';

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);


  /// Get subjects for a classroom
  Future<List<Map<String, dynamic>>> getSubjects(String classroomId) async {
    final key = 'subjects_$classroomId';
    final jsonString = _prefs.getString(key);
    if (jsonString != null) {
      try {
        final List<dynamic> data = jsonDecode(jsonString);
        return data.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing subjects: $e');
        return [];
      }
    }
    return [];
  }

  /// Add a subject locally
  Future<void> addSubjectLocally(String classroomId, Map<String, dynamic> subject) async {
    final subjects = await getSubjects(classroomId);
    subjects.add(subject);
    await saveSubjects(classroomId, subjects);
    print('📚 Added subject locally: ${subject['name']}');
  }

  // Queue pending subject for sync
  Future<void> queuePendingSubject(Map<String, dynamic> subject) async {
    final pendingSubjects = await getPendingSubjects();
    pendingSubjects.add(subject);
    final subjectsJson = pendingSubjects.map((s) => jsonEncode(s)).toList();
    await _prefs.setStringList(_pendingSubjectsKey, subjectsJson);
  }

  // Get pending subjects
  Future<List<Map<String, dynamic>>> getPendingSubjects() async {
    final subjectsJson = _prefs.getStringList(_pendingSubjectsKey);
    if (subjectsJson == null) return [];
    return subjectsJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  // Clear pending subjects after successful sync
  Future<void> clearPendingSubjects() async {
    await _prefs.remove(_pendingSubjectsKey);
  }

  // Queue pending scores for sync
  Future<void> queuePendingScores(Map<String, dynamic> scoreData) async {
    final pendingScores = await getPendingScores();
    pendingScores.add(scoreData);
    final scoresJson = pendingScores.map((s) => jsonEncode(s)).toList();
    await _prefs.setStringList(_pendingScoresKey, scoresJson);
  }

  // Get pending scores
  Future<List<Map<String, dynamic>>> getPendingScores() async {
    final scoresJson = _prefs.getStringList(_pendingScoresKey);
    if (scoresJson == null) return [];
    return scoresJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  // Clear pending scores after successful sync
  Future<void> clearPendingScores() async {
    await _prefs.remove(_pendingScoresKey);
  }

  /// Save subjects for a classroom
  Future<void> saveSubjects(String classroomId, List<Map<String, dynamic>> subjects) async {
    final key = 'subjects_$classroomId';
    final jsonString = jsonEncode(subjects);
    await _prefs.setString(key, jsonString);
    print('💾 Saved ${subjects.length} subjects for classroom $classroomId');
  }

  // Sync pending subjects with API
  Future<Map<String, dynamic>> syncPendingSubjects(Function(Map<String, dynamic>) apiCall) async {
    final pendingSubjects = await getPendingSubjects();
    int successCount = 0;
    int failureCount = 0;

    for (var subject in pendingSubjects) {
      try {
        final result = await apiCall(subject);
        if (result['success']) {
          successCount++;
        } else {
          failureCount++;
        }
      } catch (e) {
        failureCount++;
      }
    }

    if (failureCount == 0) {
      await clearPendingSubjects();
    }

    return {
      'success': failureCount == 0,
      'synced': successCount,
      'failed': failureCount,
    };
  }
}