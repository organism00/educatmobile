import 'package:flutter/material.dart';
import '../models/teacher_note.dart';
import '../services/note_ai_service.dart';
import '../services/note_storage_service.dart';
import '../utils/app_colors.dart';

const kPrimary = Color(0xFFFF6B35);
const kSuccess = Color(0xFF2ECC71);
const kWarning = Color(0xFFF39C12);
const kDanger = Color(0xFFE74C3C);
const kInfo = Color(0xFF3498DB);
const kPurple = Color(0xFF9B59B6);
const kTextPrimary = Color(0xFF2C3E50);
const kTextSecondary = Color(0xFF7F8C8D);
const kBorder = Color(0xFFECF0F1);

class TeacherNotesScreen extends StatefulWidget {
  const TeacherNotesScreen({super.key});

  @override
  State<TeacherNotesScreen> createState() => _TeacherNotesScreenState();
}

class _TeacherNotesScreenState extends State<TeacherNotesScreen> {
  final _storage = NoteStorageService();
  List<TeacherNote> _notes = [];
  List<TeacherNote> _filtered = [];
  bool _isLoading = true;

  final _searchController = TextEditingController();
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final notes = await _storage.loadNotes();
    notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    setState(() {
      _notes = notes;
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    var result = _notes;

    if (_categoryFilter != null) {
      result = result.where((n) => n.category == _categoryFilter).toList();
    }

    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      result = NoteAiService.search(result, query);
    }

    setState(() => _filtered = result);
  }

  Future<void> _saveAll() async {
    await _storage.saveNotes(_notes);
  }

  // ==================== ADD / EDIT ====================

  Future<void> _openEditor({TeacherNote? existing}) async {
    final titleCtrl =
    TextEditingController(text: existing?.title ?? '');
    final contentCtrl =
    TextEditingController(text: existing?.content ?? '');

    String liveCategory = existing?.category ?? 'General';
    List<String> liveTags = existing?.tags ?? [];
    List<String> liveActions = [];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void recomputeAi() {
            final title = titleCtrl.text;
            final content = contentCtrl.text;
            setSheetState(() {
              liveCategory =
                  NoteAiService.detectCategory(title, content);
              liveTags = NoteAiService.extractTags(title, content);
              liveActions = NoteAiService.extractActionItems(content);
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        existing == null ? 'New Note' : 'Edit Note',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          final content = contentCtrl.text.trim();
                          if (title.isEmpty && content.isEmpty) {
                            Navigator.pop(context, false);
                            return;
                          }
                          final now = DateTime.now();
                          if (existing == null) {
                            _notes.add(TeacherNote(
                              id: now.millisecondsSinceEpoch.toString(),
                              title: title.isEmpty ? 'Untitled' : title,
                              content: content,
                              category: liveCategory,
                              tags: liveTags,
                              createdAt: now,
                              updatedAt: now,
                            ));
                          } else {
                            existing.title =
                            title.isEmpty ? 'Untitled' : title;
                            existing.content = content;
                            existing.category = liveCategory;
                            existing.tags = liveTags;
                            existing.updatedAt = now;
                          }
                          await _saveAll();
                          if (context.mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom:
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: titleCtrl,
                          onChanged: (_) => recomputeAi(),
                          decoration: const InputDecoration(
                            hintText: 'Note title...',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.title),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: contentCtrl,
                          onChanged: (_) => recomputeAi(),
                          minLines: 6,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            hintText:
                            'Write your note... "Don\'t forget to submit JSS 1A results by Friday"',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Auto-detected category
                        _buildAiChip(
                          icon: Icons.auto_awesome,
                          label: 'Category',
                          value: liveCategory,
                          color: kPurple,
                        ),
                        const SizedBox(height: 8),

                        // Tags
                        if (liveTags.isNotEmpty) ...[
                          const Text(
                            'Auto-detected tags',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: liveTags
                                .map((t) => Chip(
                              label: Text(t,
                                  style: const TextStyle(
                                      fontSize: 11)),
                              backgroundColor:
                              kInfo.withOpacity(0.1),
                              side: BorderSide(
                                  color: kInfo.withOpacity(0.3)),
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets
                                  .symmetric(horizontal: 8),
                              materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                            ))
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Action items
                        if (liveActions.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kWarning.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kWarning.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.task_alt,
                                        size: 16, color: kWarning),
                                    SizedBox(width: 6),
                                    Text(
                                      'Detected action items',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: kWarning,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ...liveActions.map((a) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ',
                                          style: TextStyle(
                                              color: kWarning)),
                                      Expanded(
                                        child: Text(a,
                                            style: const TextStyle(
                                                fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Suggestion prompts
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kInfo.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: kInfo.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.lightbulb_outline,
                                      size: 16, color: kInfo),
                                  SizedBox(width: 6),
                                  Text(
                                    'Suggestions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: kInfo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...NoteAiService.getSuggestionPrompts(
                                  liveCategory)
                                  .map((s) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 2),
                                child: Text('• $s',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color:
                                        kTextSecondary)),
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == true) {
      await _loadNotes();
    }
  }

  Widget _buildAiChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==================== ACTIONS ====================

  Future<void> _togglePin(TeacherNote note) async {
    setState(() => note.isPinned = !note.isPinned);
    await _saveAll();
    await _loadNotes();
  }

  Future<void> _toggleComplete(TeacherNote note) async {
    setState(() => note.isCompleted = !note.isCompleted);
    await _saveAll();
  }

  Future<void> _deleteNote(TeacherNote note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('"${note.title}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: kDanger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _notes.removeWhere((n) => n.id == note.id));
      await _saveAll();
      await _loadNotes();
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final categories = _notes.map((n) => n.category).toSet().toList()
      ..sort();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Notes'),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: kPrimary))
          : Column(
        children: [
          // Search + filter
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilter(),
                  decoration: InputDecoration(
                    hintText:
                    'Search notes, tags, subjects...',
                    prefixIcon:
                    const Icon(Icons.search, color: kPrimary),
                    suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilter();
                      },
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', null),
                        const SizedBox(width: 6),
                        ...categories.map((c) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _filterChip(c, c),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Notes list
          Expanded(
            child: _filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              itemBuilder: (context, index) =>
                  _buildNoteCard(_filtered[index]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: kPrimary,
        icon: const Icon(Icons.edit),
        label: const Text('New Note'),
      ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _categoryFilter == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : kTextPrimary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          )),
      selected: selected,
      selectedColor: kPrimary,
      backgroundColor: Colors.white,
      onSelected: (_) {
        setState(() => _categoryFilter = value);
        _applyFilter();
      },
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? kPrimary : kBorder,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 56, color: kPrimary),
            ),
            const SizedBox(height: 16),
            const Text(
              'No notes yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "New Note" to write your first note.\nIt will be auto-categorized.',
              style: TextStyle(fontSize: 13, color: kTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(TeacherNote note) {
    final related = NoteAiService.findRelated(note, _notes, 3);
    final sentiment = NoteAiService.detectSentiment(note.content);
    final summary = NoteAiService.summarize(note.content);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: note.isPinned
              ? kPrimary.withOpacity(0.4)
              : kBorder,
          width: note.isPinned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditor(existing: note),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  if (note.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                      Icon(Icons.push_pin, size: 14, color: kPrimary),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary,
                        decoration: note.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    icon: Icon(
                      note.isCompleted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: note.isCompleted ? kSuccess : kTextSecondary,
                      size: 20,
                    ),
                    onPressed: () => _toggleComplete(note),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: kTextSecondary),
                    onSelected: (value) {
                      if (value == 'pin') _togglePin(note);
                      if (value == 'delete') _deleteNote(note);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(children: [
                          Icon(
                              note.isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                              size: 16),
                          const SizedBox(width: 8),
                          Text(note.isPinned ? 'Unpin' : 'Pin'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: kDanger),
                          SizedBox(width: 8),
                          Text('Delete',
                              style: TextStyle(color: kDanger)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),

              // Summary
              if (summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 13,
                      color: kTextSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // Chips row
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _pill(note.category, kPurple,
                      icon: Icons.auto_awesome),
                  _sentimentPill(sentiment),
                  ...note.tags.take(4).map((t) => _pill(t, kInfo)),
                ],
              ),

              // Related notes
              if (related.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.link, size: 12, color: kTextSecondary),
                          SizedBox(width: 4),
                          Text('Related',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: kTextSecondary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...related.map((r) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• ${r.title}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: kTextSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentimentPill(String sentiment) {
    Color c;
    IconData i;
    switch (sentiment) {
      case 'positive':
        c = kSuccess;
        i = Icons.sentiment_satisfied_alt;
        break;
      case 'negative':
        c = kDanger;
        i = Icons.sentiment_dissatisfied;
        break;
      default:
        c = kTextSecondary;
        i = Icons.sentiment_neutral;
    }
    return _pill(sentiment, c, icon: i);
  }
}