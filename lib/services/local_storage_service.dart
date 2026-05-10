import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _subjectsKey = 'teacher_subjects';
  static const String _pendingSubjectsKey = 'pending_subjects';
  static const String _pendingScoresKey = 'pending_scores';

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);

  // Save subjects for a classroom
  Future<void> saveSubjects(String classroomId, List<Map<String, dynamic>> subjects) async {
    final key = '${_subjectsKey}_$classroomId';
    final subjectsJson = subjects.map((s) => jsonEncode(s)).toList();
    await _prefs.setStringList(key, subjectsJson);
  }

  // Get subjects for a classroom
  Future<List<Map<String, dynamic>>> getSubjects(String classroomId) async {
    final key = '${_subjectsKey}_$classroomId';
    final subjectsJson = _prefs.getStringList(key);
    if (subjectsJson == null) return [];
    return subjectsJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  // Add a subject (saves locally and queues for sync)
  // Add a subject (saves locally and queues for sync)
  Future<void> addSubjectLocally(String classroomId, Map<String, dynamic> subject) async {
    // Get existing subjects
    final subjects = await getSubjects(classroomId);

    // Check if subject already exists
    final exists = subjects.any((s) => s['name'] == subject['name']);
    if (!exists) {
      subjects.add(subject);
      await saveSubjects(classroomId, subjects);
    }

    // Queue for sync with API
    await queuePendingSubject(subject);
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