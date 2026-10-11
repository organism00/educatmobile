import '../models/teacher_note.dart';

/// Fully offline "AI" helper for teacher notes.
/// No API calls, no network, no server.
class NoteAiService {
  // ==================== AUTO-CATEGORIZATION ====================

  /// Keyword maps for each category. First matching keyword wins.
  static const Map<String, List<String>> _categoryKeywords = {
    'Lesson Plan': [
      'lesson', 'plan', 'topic', 'objective', 'curriculum', 'syllabus',
      'teaching', 'explain', 'demonstrate', 'exercise', 'activity',
    ],
    'Homework': [
      'homework', 'assignment', 'task', 'exercise', 'practice', 'due',
      'submit', 'submission',
    ],
    'Exam': [
      'exam', 'test', 'quiz', 'assessment', 'score', 'mark', 'grade',
      'result', 'ca', 'continuous assessment',
    ],
    'Student Issue': [
      'student', 'behaviour', 'behavior', 'discipline', 'late', 'absent',
      'problem', 'issue', 'report', 'concern', 'struggling', 'guardian',
      'parent',
    ],
    'Meeting': [
      'meeting', 'staff', 'administration', 'head teacher', 'principal',
      'department', 'conference', 'briefing',
    ],
    'Reminder': [
      'remember', 'remind', 'don\'t forget', 'dont forget', 'todo', 'to-do',
      'to do', 'pending', 'urgent',
    ],
    'Finance': [
      'fee', 'payment', 'salary', 'invoice', 'receipt', 'transaction',
      'money', 'naira', '₦',
    ],
    'Ideas': [
      'idea', 'suggestion', 'improve', 'brainstorm', 'inspire', 'creative',
    ],
  };

  /// Detects the most likely category for a note.
  static String detectCategory(String title, String content) {
    final text = '$title $content'.toLowerCase();

    // Score each category
    final Map<String, int> scores = {};
    _categoryKeywords.forEach((category, keywords) {
      int score = 0;
      for (final kw in keywords) {
        if (text.contains(kw)) score++;
      }
      if (score > 0) scores[category] = score;
    });

    if (scores.isEmpty) return 'General';

    // Return highest-scoring category
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  // ==================== AUTO-TAGGING ====================

  /// Extracts likely tags: proper nouns (capitalized words),
  /// dates, and named entities.
  static List<String> extractTags(String title, String content) {
    final text = '$title $content';
    final Set<String> tags = {};

    // 1. Capitalized words (proper nouns like names, places)
    final capitalWords =
    RegExp(r'\b[A-Z][a-z]{2,}\b').allMatches(text).map((m) => m.group(0)!);
    for (final word in capitalWords) {
      // Skip common starting words
      if (!_stopWords.contains(word.toLowerCase())) {
        tags.add(word);
      }
    }

    // 2. Class names (JSS 1A, SS 2B, Primary 5, etc.)
    final classRegex = RegExp(
        r'\b(JSS\s?\d+[A-Z]?|SS\s?\d+[A-Z]?|Primary\s?\d+|Pry\s?\d+|Grade\s?\d+)\b',
        caseSensitive: false);
    for (final m in classRegex.allMatches(text)) {
      tags.add(m.group(0)!.toUpperCase().replaceAll(' ', ''));
    }

    // 3. Dates (12/05, 12-05-2024, 5th May, etc.)
    final dateRegex = RegExp(
        r'\b(\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?|\d{1,2}(st|nd|rd|th)?\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*)\b',
        caseSensitive: false);
    for (final m in dateRegex.allMatches(text)) {
      tags.add(m.group(0)!);
    }

    // 4. Subject names commonly taught
    final subjectRegex = RegExp(
        r'\b(maths?|mathematics|english|science|physics|chemistry|biology|history|geography|economics|literature|civics|ict|computer|agric|arts?|music)\b',
        caseSensitive: false);
    for (final m in subjectRegex.allMatches(text)) {
      tags.add(m.group(0)![0].toUpperCase() + m.group(0)!.substring(1));
    }

    return tags.take(8).toList();
  }

  static const Set<String> _stopWords = {
    'the', 'this', 'that', 'and', 'but', 'for', 'with', 'from',
    'today', 'tomorrow', 'yesterday', 'monday', 'tuesday', 'wednesday',
    'thursday', 'friday', 'saturday', 'sunday', 'note', 'notes',
  };

  // ==================== ACTION ITEM EXTRACTION ====================

  /// Looks for "reminder" phrases and extracts the actionable sentence.
  static List<String> extractActionItems(String content) {
    final sentences = content
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final actionTriggers = [
      'remember to',
      'don\'t forget',
      'dont forget',
      'must',
      'should',
      'need to',
      'have to',
      'todo',
      'to-do',
      'to do',
      'pending',
      'due',
      'submit',
      'call',
      'send',
      'email',
      'check',
      'follow up',
      'remind',
    ];

    final actions = <String>[];
    for (final s in sentences) {
      final lower = s.toLowerCase();
      for (final trigger in actionTriggers) {
        if (lower.contains(trigger)) {
          actions.add(s.trim());
          break;
        }
      }
    }
    return actions;
  }

  // ==================== SUMMARY ====================

  /// Very simple extractive summary: first sentence + word count.
  static String summarize(String content) {
    if (content.trim().isEmpty) return '';

    final sentences = content
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (sentences.isEmpty) return '';

    // First sentence, trimmed to 120 chars
    var summary = sentences.first.trim();
    if (summary.length > 120) {
      summary = '${summary.substring(0, 117)}...';
    }
    return summary;
  }

  // ==================== SENTIMENT ====================

  /// Rough sentiment: returns 'positive', 'negative', or 'neutral'.
  static String detectSentiment(String content) {
    final lower = content.toLowerCase();
    const positives = [
      'good', 'great', 'excellent', 'improved', 'progress', 'happy',
      'success', 'well', 'positive', 'outstanding', 'best', 'well done',
    ];
    const negatives = [
      'bad', 'poor', 'failed', 'struggling', 'problem', 'issue',
      'concern', 'worried', 'behaviour', 'late', 'absent', 'difficult',
    ];

    int pos = 0, neg = 0;
    for (final w in positives) {
      if (lower.contains(w)) pos++;
    }
    for (final w in negatives) {
      if (lower.contains(w)) neg++;
    }

    if (pos > neg) return 'positive';
    if (neg > pos) return 'negative';
    return 'neutral';
  }

  // ==================== SUGGESTIONS ====================

  /// Suggests next-step prompts based on the note category.
  static List<String> getSuggestionPrompts(String category) {
    switch (category) {
      case 'Lesson Plan':
        return [
          'Add learning objectives',
          'List required materials',
          'Set homework for this topic',
        ];
      case 'Homework':
        return [
          'Set a due date',
          'Add marking criteria',
          'Notify students',
        ];
      case 'Exam':
        return [
          'Note the exam date',
          'List topics to cover',
          'Prepare answer key',
        ];
      case 'Student Issue':
        return [
          'Contact the guardian',
          'Document the behavior',
          'Follow up next week',
        ];
      case 'Meeting':
        return [
          'Add attendees',
          'Note action items',
          'Schedule follow-up',
        ];
      case 'Reminder':
        return [
          'Set a due date',
          'Mark as high priority',
        ];
      default:
        return [
          'Add more details',
          'Set a reminder',
          'Pin this note',
        ];
    }
  }

  // ==================== RELATED NOTES ====================

  /// Finds notes that share tags/category with the given note.
  static List<TeacherNote> findRelated(
      TeacherNote note,
      List<TeacherNote> all,
      int limit,
      ) {
    final scored = <MapEntry<TeacherNote, int>>[];

    for (final other in all) {
      if (other.id == note.id) continue;
      int score = 0;

      // Same category → +2
      if (other.category == note.category) score += 2;

      // Shared tags → +1 each
      for (final tag in note.tags) {
        if (other.tags.contains(tag)) score += 1;
      }

      // Same words in title → +1 per shared word
      final noteWords = note.title.toLowerCase().split(' ');
      final otherWords = other.title.toLowerCase().split(' ');
      for (final w in noteWords) {
        if (w.length > 3 && otherWords.contains(w)) score += 1;
      }

      if (score > 0) scored.add(MapEntry(other, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  // ==================== FUZZY SEARCH ====================

  /// Search across title, content, tags, category with simple scoring.
  static List<TeacherNote> search(
      List<TeacherNote> notes,
      String query,
      ) {
    if (query.trim().isEmpty) return notes;
    final q = query.toLowerCase();
    final terms = q.split(' ').where((t) => t.isNotEmpty).toList();

    final scored = <MapEntry<TeacherNote, int>>[];
    for (final note in notes) {
      int score = 0;
      final titleLower = note.title.toLowerCase();
      final contentLower = note.content.toLowerCase();
      final tagsLower = note.tags.map((t) => t.toLowerCase()).toList();
      final categoryLower = note.category.toLowerCase();

      for (final term in terms) {
        if (titleLower.contains(term)) score += 5;
        if (categoryLower.contains(term)) score += 3;
        if (tagsLower.any((t) => t.contains(term))) score += 3;
        if (contentLower.contains(term)) score += 1;
      }

      if (score > 0) scored.add(MapEntry(note, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }
}