import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_colors.dart';
import '../screens/conversation_screen.dart';
import '../screens/messages_screen.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';

class TeacherDashboard extends StatefulWidget {
  final UserModel? user;
  const TeacherDashboard({super.key, this.user});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  int _selectedIndex = 0;
  late UserModel _currentUser;
  late ApiService _apiService;
  late LocalStorageService _localStorage;

  // Data states
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _classrooms = [];
  String _selectedClassroomId = '';
  String _selectedClassName = '';
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Attendance data
  Map<String, Map<String, bool>> _attendanceRecords = {};
  DateTime _attendanceDate = DateTime.now();
  bool _isSavingAttendance = false;
  Set<String> _savedAttendanceDates = {};

  // Results data - Using local storage
  List<Map<String, dynamic>> _subjects = [];
  Map<String, Map<String, Map<String, dynamic>>> _studentScores = {};
  bool _isSavingResults = false;
  bool _isLoadingSubjects = false;
  bool _isSyncing = false;

  // News data
  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  // Add Subject
  bool _isAddingSubject = false;
  final TextEditingController _subjectNameController = TextEditingController();
  final TextEditingController _subjectDescriptionController = TextEditingController();

  // Assignment data
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoadingAssignments = false;
  String? _selectedAssignmentClassId;

  // Messages - Unread count
  int _unreadMessageCount = 0;

  // Activity Slideshow
  final List<Map<String, dynamic>> _activitySlides = [
    {'title': '📝 Mark Attendance', 'description': 'Mark student attendance', 'icon': Icons.checklist, 'action': 'Take Attendance'},
    {'title': '📊 Record Results', 'description': 'Upload assessment scores', 'icon': Icons.grade, 'action': 'Record Results'},
    {'title': '📚 Add Subject', 'description': 'Add new subject to classroom', 'icon': Icons.library_add, 'action': 'Add Subject'},
    {'title': '📋 Create Assignment', 'description': 'Post new assignment', 'icon': Icons.assignment_add, 'action': 'Create Assignment'},
    {'title': '💬 Chat with Parents', 'description': 'Message parents of your students', 'icon': Icons.chat, 'action': 'Chat with Parents'},
    {'title': '👥 View Students', 'description': 'View all students in class', 'icon': Icons.people, 'action': 'View Students'},
  ];

  int _currentSlideIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadLocalStorage();
    _loadUserData();
    _fetchDashboardData();
    _fetchNews();
    _fetchUnreadMessages();
    _pageController = PageController(initialPage: 0);
    _startAutoScroll();
    NotificationService().onNotificationTap = (data) async {
      print('📱 Notification tapped: $data');
      if (data.containsKey('senderId') && data.containsKey('senderRole')) {
        final senderId = data['senderId'];
        final senderRole = data['senderRole'];
        final senderName = data['senderName'] ?? 'User';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ConversationScreen(
                userId: senderId,
                userRole: senderRole,
                userName: senderName,
              ),
            ),
          );
        }
      }
    };
  }

  void _startAutoScroll() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _pageController.hasClients) {
        if (_currentSlideIndex < _activitySlides.length - 1) {
          _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        } else {
          _pageController.jumpToPage(0);
        }
        _startAutoScroll();
      }
    });
  }

  // Get responsive values based on screen size
  ResponsiveData _getResponsiveData(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final isTablet = width >= 600 && width < 1200;
    final isDesktop = width >= 1200;

    return ResponsiveData(
      isMobile: isMobile,
      isTablet: isTablet,
      isDesktop: isDesktop,
      padding: isMobile ? 12.0 : (isTablet ? 20.0 : 24.0),
      gridCrossAxisCount: isMobile ? 2 : (isTablet ? 3 : 4),
      quickActionsCount: isMobile ? 4 : (isTablet ? 6 : 8),
      fontSizeSmall: isMobile ? 10.0 : (isTablet ? 12.0 : 13.0),
      fontSizeMedium: isMobile ? 14.0 : (isTablet ? 16.0 : 18.0),
      fontSizeLarge: isMobile ? 20.0 : (isTablet ? 24.0 : 28.0),
      fontSizeHeader: isMobile ? 22.0 : (isTablet ? 28.0 : 32.0),
      slideshowHeight: isMobile ? 150.0 : (isTablet ? 180.0 : 200.0),
      cardElevation: isMobile ? 2 : (isTablet ? 3 : 4),
    );
  }

  Future<void> _loadLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _localStorage = LocalStorageService(prefs);
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = widget.user ?? authProvider.currentUser!;
  }

  Future<void> _fetchUnreadMessages() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    final result = await _apiService.getInboxMessages(
      token: token,
      userId: _currentUser.id,
      userRole: 'Teacher',
    );

    if (result['success'] && mounted) {
      final messages = result['data'] as List? ?? [];
      final unreadCount = messages.where((m) => m['isRead'] == false).length;
      setState(() {
        _unreadMessageCount = unreadCount;
      });
    }
  }

  Future<void> _fetchDashboardData() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      setState(() { _errorMessage = 'Not authenticated'; _isLoading = false; });
      return;
    }

    final teacherResult = await _apiService.getTeacherById(token: token, teacherId: _currentUser.id);
    if (teacherResult['success'] && mounted) {
      final teacherData = teacherResult['data'];
      setState(() { _currentUser = UserModel.fromTeacherData(teacherData, _currentUser); });
    }

    final classroomsResult = await _apiService.getTeacherClassrooms(token: token, teacherId: _currentUser.id);
    if (classroomsResult['success'] && mounted) {
      final classrooms = classroomsResult['data'] as List? ?? [];
      setState(() {
        _classrooms = classrooms.map((c) => ({
          'id': c['classroomId'],
          'name': c['name'],
          'capacity': c['capacity'],
        })).toList();
      });

      if (_classrooms.isNotEmpty) {
        _selectedClassroomId = _classrooms[0]['id'];
        _selectedClassName = _classrooms[0]['name'];
        _selectedAssignmentClassId = _selectedClassroomId;
        await _fetchStudents(token, _selectedClassroomId);
        await _loadSubjectsFromLocal();
        await _fetchAssignments(token);
      } else {
        setState(() { _errorMessage = 'No classroom assigned'; _isLoading = false; });
        return;
      }
    } else {
      setState(() { _errorMessage = classroomsResult['message'] ?? 'Failed to load classrooms'; _isLoading = false; });
      return;
    }
    setState(() { _isLoading = false; });
  }

  Future<void> _fetchStudents(String token, String classroomId) async {
    setState(() { _isLoading = true; });

    final studentsResult = await _apiService.getStudentsByClassroomId(token: token, classroomId: classroomId);

    if (studentsResult['success'] && mounted) {
      final studentsData = studentsResult['data'] as List? ?? [];
      List<Map<String, dynamic>> enrichedStudents = [];

      for (var student in studentsData) {
        final guardianId = student['guardianId'] ?? student['guardian']?['guardianId'] ?? '';
        String parentName = 'N/A';
        String parentEmail = '';
        String parentPhone = '';

        if (guardianId.isNotEmpty) {
          try {
            final guardianResult = await _apiService.getGuardianById(
              token: token,
              guardianId: guardianId,
            ).timeout(const Duration(seconds: 10));

            if (guardianResult['success'] && guardianResult['data'] != null) {
              final guardian = guardianResult['data'];
              final firstName = guardian['firstname'] ?? '';
              final lastName = guardian['lastname'] ?? '';
              parentName = '$firstName $lastName'.trim();
              if (parentName.isEmpty) parentName = 'N/A';
              parentEmail = guardian['email'] ?? '';
              parentPhone = guardian['phone'] ?? '';
            }
          } catch (e) {
            print('Error fetching guardian $guardianId: $e');
          }
        }

        enrichedStudents.add({
          'id': student['studentId'] ?? '',
          'name': '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
          'admissionNo': student['studentNo'] ?? '',
          'className': _selectedClassName,
          'parentId': guardianId,
          'parentName': parentName,
          'parentEmail': parentEmail,
          'parentPhone': parentPhone,
          'gender': student['gender'] ?? 'Not specified',
          'averageScore': 0,
          'attendance': 0,
        });
      }

      setState(() {
        _students = enrichedStudents;
        _filteredStudents = List.from(_students);
        for (var student in _students) {
          _attendanceRecords[student['id']] = {};
        }
        _initializeStudentScores();
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = studentsResult['message'] ?? 'Failed to load students';
        _isLoading = false;
      });
    }
  }

  void _initializeStudentScores() {
    for (var student in _students) {
      final studentId = student['id'].toString();
      _studentScores[studentId] = {};
      for (var subject in _subjects) {
        final subjectId = subject['id'].toString();
        _studentScores[studentId]![subjectId] = {
          'ca': 0,
          'exam': 0,
          'total': 0,
          'subjectName': subject['name'].toString(),
        };
      }
    }
  }

  Future<void> _fetchAssignments(String token) async {
    if (_selectedClassroomId.isEmpty) return;
    setState(() { _isLoadingAssignments = true; });
    final result = await _apiService.getAssignmentsByClassId(
      token: token,
      classroomId: _selectedClassroomId,
    );
    if (result['success'] && mounted) {
      _assignments = List<Map<String, dynamic>>.from(result['data'] ?? []);
    } else {
      _assignments = [];
    }
    setState(() { _isLoadingAssignments = false; });
  }

  Future<void> _fetchAssignmentsForClass(String token, String classroomId) async {
    setState(() { _isLoadingAssignments = true; });
    final result = await _apiService.getAssignmentsByClassId(
      token: token,
      classroomId: classroomId,
    );
    if (result['success'] && mounted) {
      _assignments = List<Map<String, dynamic>>.from(result['data'] ?? []);
    } else {
      _assignments = [];
    }
    setState(() { _isLoadingAssignments = false; });
  }

  Future<void> _loadSubjectsFromLocal() async {
    setState(() { _isLoadingSubjects = true; });
    final subjects = await _localStorage.getSubjects(_selectedClassroomId);
    _subjects = subjects;
    setState(() { _isLoadingSubjects = false; });
    _initializeStudentScores();
  }

  void _filterStudents(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students.where((student) {
          final name = student['name'].toString().toLowerCase();
          final admissionNo = student['admissionNo'].toString().toLowerCase();
          final parentName = student['parentName'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              admissionNo.contains(query.toLowerCase()) ||
              parentName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _fetchNews() async {
    setState(() { _isLoadingNews = true; });
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token != null) {
      final newsResult = await _apiService.getAllNews(token: token);
      if (newsResult['success'] && mounted) {
        _news = (newsResult['data'] as List?)?.map((item) => ({
          'id': item['id'],
          'title': item['title'],
          'content': item['content'],
          'date': _formatDate(item['date']),
        })).toList() ?? [];
      }
    }
    setState(() { _isLoadingNews = false; });
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'Recent';
    try {
      DateTime dateTime = DateTime.parse(dateValue.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'Recent';
    }
  }

  Future<void> _refreshData() async {
    setState(() { _isRefreshing = true; });
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token != null) {
      await _fetchStudents(token, _selectedClassroomId);
      await _fetchAssignments(token);
    }
    await _fetchNews();
    await _fetchUnreadMessages();
    setState(() { _isRefreshing = false; });
  }

  // Navigation methods
  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MessagesScreen()),
    ).then((_) => _fetchUnreadMessages());
  }

  void _navigateToChatList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TeacherChatListScreen()),
    );
  }

  void _startConversationWithParent(Map<String, dynamic> student) {
    final parentId = student['parentId']?.toString() ?? '';
    final parentName = student['parentName']?.toString() ?? 'Parent';
    if (parentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parent ID not found'), backgroundColor: AppColors.error),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          userId: parentId,
          userRole: 'Guardian',
          userName: parentName,
          userEmail: student['parentEmail']?.toString(),
          userPhone: student['parentPhone']?.toString(),
        ),
      ),
    ).then((_) => _fetchUnreadMessages());
  }

  // Assignment methods
  void _showCreateAssignmentDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? dueDate;
    String? selectedClassId = _selectedClassroomId;
    final responsive = _getResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create Assignment', style: TextStyle(color: AppColors.primary)),
            content: SingleChildScrollView(
              child: Container(
                width: responsive.isMobile ? null : 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_classrooms.length > 1)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          value: selectedClassId,
                          decoration: const InputDecoration(
                            labelText: 'Select Class',
                            border: OutlineInputBorder(),
                          ),
                          items: _classrooms.map((classroom) {
                            return DropdownMenuItem<String>(
                              value: classroom['id'],
                              child: Text(classroom['name']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedClassId = value;
                            });
                          },
                        ),
                      ),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Assignment Title *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() {
                            dueDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Due Date *'),
                                  const SizedBox(height: 4),
                                  Text(
                                    dueDate != null
                                        ? '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
                                        : 'Select a date',
                                    style: TextStyle(
                                      fontWeight: dueDate != null ? FontWeight.bold : FontWeight.normal,
                                      color: dueDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Assignment will be visible to all students in the selected class',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  final description = descriptionController.text.trim();
                  if (title.isEmpty || description.isEmpty || dueDate == null || selectedClassId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all fields'), backgroundColor: AppColors.warning),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  await _createAssignment(
                    title: title,
                    description: description,
                    classroomId: selectedClassId!,
                    dueDate: dueDate!,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Create Assignment'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createAssignment({
    required String title,
    required String description,
    required String classroomId,
    required DateTime dueDate,
  }) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final result = await _apiService.createAssignment(
        token: token,
        title: title,
        description: description,
        teacherId: _currentUser.id,
        classroomId: classroomId,
        dueDate: dueDate,
        termId: _currentUser.termId,
      );

      Navigator.pop(context);

      if (result['success']) {
        await _fetchAssignmentsForClass(token, classroomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']), backgroundColor: AppColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  void _showViewAssignmentsScreen() {
    final responsive = _getResponsiveData(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: responsive.isMobile ? 0.9 : 0.7,
        minChildSize: 0.5,
        maxChildSize: responsive.isMobile ? 0.95 : 0.85,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, bottomSheetSetState) {
              return Container(
                padding: EdgeInsets.all(responsive.padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Assignments',
                          style: TextStyle(
                            fontSize: responsive.fontSizeLarge,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, size: responsive.fontSizeMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_classrooms.length > 1)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedAssignmentClassId,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          style: TextStyle(
                            fontSize: responsive.fontSizeSmall,
                            color: AppColors.textPrimary,
                          ),
                          items: _classrooms.map((classroom) {
                            return DropdownMenuItem<String>(
                              value: classroom['id'],
                              child: Text(classroom['name']),
                            );
                          }).toList(),
                          onChanged: (value) async {
                            if (value != null) {
                              bottomSheetSetState(() {
                                _selectedAssignmentClassId = value;
                                _isLoadingAssignments = true;
                              });
                              final token = Provider.of<AuthProvider>(context, listen: false).token;
                              if (token != null) {
                                await _fetchAssignmentsForClass(token, value);
                                bottomSheetSetState(() { _isLoadingAssignments = false; });
                              }
                            }
                          },
                        ),
                      ),
                    Expanded(
                      child: _isLoadingAssignments
                          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                          : _assignments.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.assignment_turned_in, size: 64, color: AppColors.grey),
                            const SizedBox(height: 16),
                            const Text('No assignments yet', style: TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showCreateAssignmentDialog();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create Assignment'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        controller: scrollController,
                        itemCount: _assignments.length,
                        itemBuilder: (context, index) {
                          final assignment = _assignments[index];
                          return _buildAssignmentCard(assignment, responsive);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment, ResponsiveData responsive) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(responsive.padding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isOverdue ? AppColors.error.withOpacity(0.3) : AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(responsive.isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment, color: isOverdue ? AppColors.error : AppColors.primary, size: responsive.fontSizeMedium),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment['title'] ?? 'Untitled',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: responsive.fontSizeSmall,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: ${_formatDate(assignment['dueDate'])}',
                      style: TextStyle(
                        fontSize: responsive.fontSizeSmall - 2,
                        color: isOverdue ? AppColors.error : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isOverdue ? 'Overdue' : 'Active',
                  style: TextStyle(
                    fontSize: responsive.fontSizeSmall - 2,
                    color: isOverdue ? AppColors.error : AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            assignment['description'] ?? 'No description',
            style: TextStyle(fontSize: responsive.fontSizeSmall - 1, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.class_, size: responsive.fontSizeSmall, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  assignment['classroom']?['name'] ?? _selectedClassName,
                  style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAssignmentDetails(assignment, responsive),
                icon: Icon(Icons.visibility, size: responsive.fontSizeSmall),
                label: Text('Details', style: TextStyle(fontSize: responsive.fontSizeSmall - 2)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment, ResponsiveData responsive) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(assignment['title'] ?? 'Assignment Details', style: const TextStyle(color: AppColors.primary)),
        content: SizedBox(
          width: responsive.isMobile ? null : 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(assignment['description'] ?? 'No description', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: isOverdue ? AppColors.error : AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Due Date'),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(assignment['dueDate']),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isOverdue ? AppColors.error : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(isOverdue ? Icons.warning : Icons.check_circle, color: isOverdue ? AppColors.error : AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isOverdue ? 'This assignment is overdue' : 'This assignment is active',
                        style: TextStyle(color: isOverdue ? AppColors.error : AppColors.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  // Attendance methods
  bool _isAttendanceSavedForDate(DateTime date) {
    return _savedAttendanceDates.contains('${date.year}-${date.month}-${date.day}');
  }

  int _getTodayAttendanceCount() {
    String todayKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    return _students.where((s) => _attendanceRecords[s['id']]?[todayKey] == true).length;
  }

  int _getAttendanceCountForDate(DateTime date) {
    String dateKey = '${date.year}-${date.month}-${date.day}';
    return _students.where((s) => _attendanceRecords[s['id']]?[dateKey] == true).length;
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _attendanceDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() { _attendanceDate = picked; });
  }

  void _markAllAttendance(bool present) {
    setState(() {
      String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
      for (var student in _students) {
        _attendanceRecords[student['id']]![dateKey] = present;
      }
    });
  }

  Future<void> _saveAttendance() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() { _isSavingAttendance = true; });

    String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
    int successCount = 0;

    for (var student in _students) {
      bool isPresent = _attendanceRecords[student['id']]?[dateKey] ?? false;
      final result = await _apiService.saveTeacherAttendance(
        token: token,
        studentId: student['id'],
        classroomId: _selectedClassroomId,
        sessionId: _currentUser.sessionId,
        termId: _currentUser.termId,
        status: isPresent ? 1 : 0,
        date: _attendanceDate,
      );
      if (result['success']) successCount++;
    }

    setState(() {
      _isSavingAttendance = false;
      if (successCount == _students.length) _savedAttendanceDates.add(dateKey);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Attendance saved for $successCount students!'), backgroundColor: AppColors.success),
    );
  }

  // Results methods
  Future<void> _saveSubjectScores(Map<String, dynamic> subject) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    setState(() { _isSavingResults = true; });

    final subjectId = subject['id'].toString();
    final subjectName = subject['name'].toString();

    List<Map<String, dynamic>> scores = [];
    for (var student in _students) {
      final studentId = student['id'].toString();
      final studentScores = _studentScores[studentId]?[subjectId];
      if (studentScores != null && (studentScores['ca'] > 0 || studentScores['exam'] > 0)) {
        scores.add({
          'studentId': studentId,
          'ca': studentScores['ca'],
          'examScore': studentScores['exam'],
          'remarks': 'Good performance',
        });
      }
    }

    if (scores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No scores to save'), backgroundColor: AppColors.warning));
      setState(() { _isSavingResults = false; });
      return;
    }

    if (token == null) {
      await _localStorage.queuePendingScores({
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classroomId': _selectedClassroomId,
        'scores': scores,
        'timestamp': DateTime.now().toIso8601String(),
      });
      setState(() { _isSavingResults = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scores saved locally! Will sync when online.'), backgroundColor: AppColors.success));
      return;
    }

    final result = await _apiService.addSubjectScores(
      token: token,
      schoolId: _currentUser.schoolId,
      classroomId: _selectedClassroomId,
      subjectId: subjectId,
      sessionId: _currentUser.sessionId,
      sessionTermId: _currentUser.termId,
      term: _currentUser.term,
      scores: scores,
    );

    setState(() { _isSavingResults = false; });

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scores for $subjectName saved!'), backgroundColor: AppColors.success));
    } else {
      await _localStorage.queuePendingScores({
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classroomId': _selectedClassroomId,
        'scores': scores,
        'timestamp': DateTime.now().toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}. Saved locally.'), backgroundColor: AppColors.warning));
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  // UI Build methods
  void _handleActivityTap(String action) {
    switch (action) {
      case 'Take Attendance': setState(() => _selectedIndex = 2); break;
      case 'Record Results':
        if (_subjects.isEmpty) {
          _showAddSubjectDialog();
        } else {
          setState(() => _selectedIndex = 3);
        }
        break;
      case 'Add Subject': _showAddSubjectDialog(); break;
      case 'Create Assignment': _showCreateAssignmentDialog(); break;
      case 'Chat with Parents': _navigateToChatList(); break;
      case 'View Students': setState(() => _selectedIndex = 1); break;
    }
  }

  void _showAddSubjectDialog() {
    _subjectNameController.clear();
    _subjectDescriptionController.clear();
    final responsive = _getResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Subject', style: TextStyle(color: AppColors.primary)),
        content: SizedBox(
          width: responsive.isMobile ? null : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _subjectNameController,
                decoration: const InputDecoration(labelText: 'Subject Name *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subjectDescriptionController,
                decoration: const InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final subjectName = _subjectNameController.text.trim();
              if (subjectName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a subject name'), backgroundColor: AppColors.warning));
                return;
              }

              setState(() { _isAddingSubject = true; });

              final token = Provider.of<AuthProvider>(context, listen: false).token;
              if (token == null) {
                setState(() { _isAddingSubject = false; });
                return;
              }

              final result = await _apiService.addSubject(
                token: token,
                schoolId: _currentUser.schoolId,
                classroomId: _selectedClassroomId,
                teacherId: _currentUser.id,
                sessionTermId: _currentUser.termId,
                subjectName: subjectName,
                description: _subjectDescriptionController.text.trim().isEmpty ? 'No description' : _subjectDescriptionController.text.trim(),
              );

              setState(() { _isAddingSubject = false; });

              if (result['success']) {
                final subjectData = result['data'];
                final newSubject = {
                  'id': subjectData['subjectId'],
                  'name': subjectName,
                  'description': _subjectDescriptionController.text.trim().isEmpty ? 'No description' : _subjectDescriptionController.text.trim(),
                };
                await _localStorage.addSubjectLocally(_selectedClassroomId, newSubject);
                await _loadSubjectsFromLocal();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subject "$subjectName" added!'), backgroundColor: AppColors.success));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']), backgroundColor: AppColors.error));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: _isAddingSubject ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add Subject'),
          ),
        ],
      ),
    );
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    final responsive = _getResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(student['name'], style: const TextStyle(color: AppColors.primary)),
        content: SizedBox(
          width: responsive.isMobile ? null : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Admission', student['admissionNo'], responsive),
              _buildDetailRow('Class', student['className'], responsive),
              const SizedBox(height: 12),
              const Text('Parent Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              _buildDetailRow('Name', student['parentName'], responsive),
              _buildDetailRow('Email', student['parentEmail'], responsive),
              InkWell(
                onTap: () => _makePhoneCall(student['parentPhone']),
                child: _buildDetailRow('Phone', student['parentPhone'], responsive, isClickable: true),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _startConversationWithParent(student);
            },
            icon: const Icon(Icons.message),
            label: const Text('Message Parent'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          if (student['parentPhone'] != null && student['parentPhone'].toString().isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _makePhoneCall(student['parentPhone']),
              icon: const Icon(Icons.phone),
              label: const Text('Call Parent'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ResponsiveData responsive, {bool isClickable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: responsive.isMobile ? 70 : 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: responsive.fontSizeSmall - 1,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: responsive.fontSizeSmall - 1,
                color: isClickable ? AppColors.primary : AppColors.textPrimary,
                decoration: isClickable ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (isClickable && value.isNotEmpty && value != 'N/A')
            Icon(Icons.phone, size: 16, color: AppColors.primary),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == 'N/A') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available'), backgroundColor: AppColors.warning),
      );
      return;
    }

    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanNumber.startsWith('0') && cleanNumber.length == 11) {
      cleanNumber = '+234${cleanNumber.substring(1)}';
    } else if (!cleanNumber.startsWith('+')) {
      cleanNumber = '+$cleanNumber';
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        throw 'Could not launch $phoneUri';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dial $phoneNumber'), backgroundColor: AppColors.error),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout', style: TextStyle(color: AppColors.error)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showAttendanceHistory() {
    final responsive = _getResponsiveData(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * (responsive.isMobile ? 0.7 : 0.6),
        width: responsive.isDesktop ? 800 : double.infinity,
        padding: EdgeInsets.all(responsive.padding),
        child: FutureBuilder(
          future: _apiService.getAttendanceByActiveTerm(
            token: Provider.of<AuthProvider>(context, listen: false).token!,
            schoolId: _currentUser.schoolId,
            classroomId: _selectedClassroomId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (!snapshot.hasData || snapshot.data == null || !snapshot.data!['success']) {
              return const Center(child: Text('No attendance records found'));
            }
            final records = snapshot.data!['data'] as List? ?? [];
            if (records.isEmpty) {
              return const Center(child: Text('No attendance records found'));
            }
            return Column(
              children: [
                Text('Attendance History', style: TextStyle(fontSize: responsive.fontSizeLarge, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(record['status'] == 1 ? Icons.check_circle : Icons.cancel, color: record['status'] == 1 ? AppColors.success : AppColors.error),
                          title: Text(record['studentName'] ?? 'Student'),
                          subtitle: Text('Date: ${record['date']?.toString().split('T')[0] ?? 'N/A'}'),
                          trailing: Text(record['status'] == 1 ? 'Present' : 'Absent', style: TextStyle(color: record['status'] == 1 ? AppColors.success : AppColors.error)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = _getResponsiveData(context);

    return Scaffold(
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _errorMessage != null
              ? _buildErrorView(responsive)
              : RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _selectedIndex == 0
                ? _buildHomeScreen(responsive)
                : _buildScreenForIndex(_selectedIndex, responsive),
          ),
        ),
      ),
      bottomNavigationBar: _isLoading || _errorMessage != null ? null : _buildBottomNavigationBar(responsive),
    );
  }

  Widget _buildErrorView(ResponsiveData responsive) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: AppColors.textSecondary, fontSize: responsive.fontSizeMedium)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _fetchDashboardData, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(ResponsiveData responsive) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: BottomNavigationBar(
        type: responsive.isMobile ? BottomNavigationBarType.fixed : BottomNavigationBarType.shifting,
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey,
        currentIndex: _selectedIndex,
        elevation: 0,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Students'),
          const BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Attendance'),
          const BottomNavigationBarItem(icon: Icon(Icons.grade_rounded), label: 'Results'),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.message_rounded),
                if (_unreadMessageCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '$_unreadMessageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildHomeScreen(ResponsiveData responsive) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(responsive.padding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: responsive.isDesktop ? 1400 : double.infinity,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(responsive),
              const SizedBox(height: 16),
              if (_classrooms.length > 1)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(20)),
                  child: DropdownButton<String>(
                    value: _selectedClassroomId,
                    dropdownColor: AppColors.white,
                    underline: const SizedBox(),
                    icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: responsive.fontSizeSmall),
                    items: _classrooms.map((classroom) => DropdownMenuItem<String>(value: classroom['id'], child: Text(classroom['name']))).toList(),
                    onChanged: (value) async {
                      if (value != null) {
                        setState(() {
                          _selectedClassroomId = value;
                          _selectedClassName = _classrooms.firstWhere((c) => c['id'] == value)['name'];
                          _isLoading = true;
                        });
                        final token = Provider.of<AuthProvider>(context, listen: false).token;
                        if (token != null) {
                          await _fetchStudents(token, value);
                          await _loadSubjectsFromLocal();
                          await _fetchAssignments(token);
                        }
                        setState(() { _isLoading = false; });
                      }
                    },
                  ),
                ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: responsive.gridCrossAxisCount,
                mainAxisSpacing: responsive.padding,
                crossAxisSpacing: responsive.padding,
                childAspectRatio: responsive.isMobile ? 1.4 : 1.6,
                children: [
                  _buildStatCard('Total Students', _students.length.toString(), Icons.people, AppColors.primary, responsive),
                  _buildStatCard('Present Today', '${_getTodayAttendanceCount()}/${_students.length}', Icons.check_circle, AppColors.success, responsive),
                  _buildStatCard('Class', _selectedClassName, Icons.class_, AppColors.warning, responsive),
                  _buildStatCard('Subjects', _subjects.length.toString(), Icons.book, AppColors.info, responsive),
                  _buildStatCard('Assignments', _assignments.length.toString(), Icons.assignment, AppColors.info, responsive),
                  _buildStatCard('Messages', _unreadMessageCount.toString(), Icons.message, AppColors.primary, responsive),
                ],
              ),
              const SizedBox(height: 16),
              _buildActivitySlideshow(responsive),
              const SizedBox(height: 16),
              _buildQuickActions(responsive),
              const SizedBox(height: 16),
              _buildAssignmentsPreview(responsive),
              const SizedBox(height: 16),
              _buildNewsSection(responsive),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ResponsiveData responsive) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: TextStyle(color: AppColors.textSecondary, fontSize: responsive.fontSizeSmall)),
              const SizedBox(height: 4),
              Text(
                _currentUser.name.isNotEmpty ? _currentUser.name : 'Teacher',
                style: TextStyle(color: AppColors.textPrimary, fontSize: responsive.fontSizeHeader, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _currentUser.schoolName,
                style: TextStyle(color: AppColors.textSecondary, fontSize: responsive.fontSizeSmall),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Stack(
          children: [
            Container(
              width: responsive.isMobile ? 45 : 55,
              height: responsive.isMobile ? 45 : 55,
              decoration: BoxDecoration(gradient: AppColors.cardGradient, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)]),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.message, size: responsive.fontSizeMedium + 4, color: Colors.white),
                onPressed: _navigateToMessages,
              ),
            ),
            if (_unreadMessageCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$_unreadMessageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ResponsiveData responsive) {
    return Container(
      padding: EdgeInsets.all(responsive.padding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(responsive.isMobile ? 14 : 16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: responsive.cardElevation * 2)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: responsive.fontSizeMedium + 4, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(fontSize: responsive.fontSizeSmall - 1, color: AppColors.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildActivitySlideshow(ResponsiveData responsive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('✨ Teacher Activities', style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold))),
        SizedBox(
          height: responsive.slideshowHeight,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentSlideIndex = index),
            itemCount: _activitySlides.length,
            itemBuilder: (context, index) {
              final slide = _activitySlides[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(gradient: AppColors.cardGradient, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)]),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleActivityTap(slide['action'] as String),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.all(responsive.padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(responsive.isMobile ? 8 : 10),
                                decoration: BoxDecoration(color: AppColors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                child: Icon(slide['icon'] as IconData, size: responsive.fontSizeMedium, color: AppColors.white),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                child: Text('${index + 1}/${_activitySlides.length}', style: TextStyle(color: AppColors.white, fontSize: responsive.fontSizeSmall - 1)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(slide['title'] as String, style: TextStyle(fontSize: responsive.fontSizeSmall + 2, fontWeight: FontWeight.bold, color: AppColors.white)),
                          const SizedBox(height: 4),
                          Text(slide['description'] as String, style: TextStyle(fontSize: responsive.fontSizeSmall - 1, color: AppColors.white.withOpacity(0.9))),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(8)),
                            child: Text(slide['action'] as String, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: responsive.fontSizeSmall - 1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _activitySlides.length,
                (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: responsive.isMobile ? 5 : 6,
              height: responsive.isMobile ? 5 : 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _currentSlideIndex == index ? AppColors.primary : AppColors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(ResponsiveData responsive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: responsive.quickActionsCount,
          mainAxisSpacing: responsive.padding,
          crossAxisSpacing: responsive.padding,
          childAspectRatio: 1,
          children: [
            _buildActionTile(Icons.checklist, 'Take\nAttendance', () => setState(() => _selectedIndex = 2), responsive),
            _buildActionTile(Icons.grade, 'Record\nResults', () => _subjects.isEmpty ? _showAddSubjectDialog() : setState(() => _selectedIndex = 3), responsive),
            _buildActionTile(Icons.library_add, 'Add\nSubject', _showAddSubjectDialog, responsive),
            _buildActionTile(Icons.assignment_add, 'Create\nAssignment', _showCreateAssignmentDialog, responsive),
            _buildActionTile(Icons.chat, 'Chat with\nParents', _navigateToChatList, responsive),
            _buildActionTile(Icons.people, 'View\nStudents', () => setState(() => _selectedIndex = 1), responsive),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap, ResponsiveData responsive) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: responsive.padding),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: responsive.fontSizeMedium + 4, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: responsive.fontSizeSmall - 1, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsPreview(ResponsiveData responsive) {
    if (_isLoadingAssignments) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_assignments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(Icons.assignment_turned_in, size: 48, color: AppColors.grey),
            const SizedBox(height: 12),
            Text('No assignments yet', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: _showCreateAssignmentDialog, icon: const Icon(Icons.add), label: const Text('Create First Assignment'), style: TextButton.styleFrom(foregroundColor: AppColors.primary)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Assignments', style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold)),
            TextButton(onPressed: _showViewAssignmentsScreen, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(16)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _assignments.length > 3 ? 3 : _assignments.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildAssignmentCard(_assignments[index], responsive),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection(ResponsiveData responsive) {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_news.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('School News', style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(14)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _news.length > 3 ? 3 : _news.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _news[index];
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.primary.withOpacity(0.1), child: Icon(Icons.newspaper, color: AppColors.primary)),
                title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(item['date'] ?? 'Recent', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                trailing: Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.primary),
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(item['title']),
                    content: SingleChildScrollView(child: Text(item['content'])),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Screens based on index
  Widget _buildScreenForIndex(int index, ResponsiveData responsive) {
    switch (index) {
    case 1: return _buildStudentsScreen(responsive);
    case 2: return _buildAttendanceScreen(responsive);
    case 3: return _buildResultsScreen(responsive);
      case 4: return _buildMessagesScreen(responsive);
      case 5: return _buildMoreScreen(responsive);
      default: return _buildHomeScreen(responsive);
    }
  }

  Widget _buildStudentsScreen(ResponsiveData responsive) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(responsive.padding),
          color: AppColors.white,
          child: TextField(
            controller: _searchController,
            onChanged: _filterStudents,
            decoration: InputDecoration(
              hintText: 'Search by name or admission...',
              prefixIcon: Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filterStudents(''); })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: AppColors.greyLight,
              contentPadding: EdgeInsets.symmetric(horizontal: responsive.padding, vertical: responsive.isMobile ? 12 : 16),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearching && _filteredStudents.isEmpty
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off, size: 48, color: AppColors.grey), SizedBox(height: 12), Text('No students found')]))
                : responsive.isDesktop
                ? _buildStudentsTable(responsive)
                : ListView.builder(
              padding: EdgeInsets.all(responsive.padding),
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) => _buildStudentCard(_filteredStudents[index], responsive),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentsTable(ResponsiveData responsive) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
        columns: const [
          DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Admission No', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Parent Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Contact', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _filteredStudents.map((student) {
          return DataRow(cells: [
            DataCell(Text(student['name'])),
            DataCell(Text(student['admissionNo'])),
            DataCell(Text(student['parentName'])),
            DataCell(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (student['parentPhone'] != 'N/A')
                  InkWell(
                    onTap: () => _makePhoneCall(student['parentPhone']),
                    child: Row(
                      children: [
                        Icon(Icons.phone, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(student['parentPhone'], style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                if (student['parentEmail'] != 'N/A')
                  Text(student['parentEmail'], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            )),
            DataCell(Row(
              children: [
                IconButton(
                  icon: Icon(Icons.message, color: AppColors.primary),
                  onPressed: () => _startConversationWithParent(student),
                  tooltip: 'Message Parent',
                ),
                IconButton(
                  icon: Icon(Icons.visibility, color: AppColors.info),
                  onPressed: () => _showStudentDetails(student),
                  tooltip: 'View Details',
                ),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, ResponsiveData responsive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(responsive.padding),
      decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: responsive.isMobile ? 40 : 45,
                height: responsive.isMobile ? 40 : 45,
                decoration: BoxDecoration(gradient: AppColors.cardGradient, shape: BoxShape.circle),
                child: Center(child: Text(student['name'][0], style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold, color: AppColors.white))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(student['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: responsive.fontSizeSmall)),
                  Text('Admission: ${student['admissionNo']}', style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
                  Text('Parent: ${student['parentName']}', style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.message, color: AppColors.primary, size: responsive.fontSizeMedium),
                onPressed: () => _startConversationWithParent(student),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStudentInfo('Attendance', '${student['attendance']}%', Icons.calendar_today, responsive),
              _buildStudentInfo('Average', '${student['averageScore']}%', Icons.grade, responsive),
              _buildStudentInfo('Gender', student['gender'], Icons.person, responsive),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showStudentDetails(student),
                  icon: Icon(Icons.visibility, size: responsive.fontSizeSmall),
                  label: Text('Details', style: TextStyle(fontSize: responsive.fontSizeSmall - 1)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _startConversationWithParent(student),
                  icon: Icon(Icons.message, size: responsive.fontSizeSmall),
                  label: Text('Message Parent', style: TextStyle(fontSize: responsive.fontSizeSmall - 1)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfo(String label, String value, IconData icon, ResponsiveData responsive) {
    return Column(
      children: [
        Icon(icon, size: responsive.fontSizeSmall, color: AppColors.primary),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: responsive.fontSizeSmall)),
        Text(label, style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildAttendanceScreen(ResponsiveData responsive) {
    int presentCount = _getAttendanceCountForDate(_attendanceDate);
    bool isAttendanceSaved = _isAttendanceSavedForDate(_attendanceDate);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(responsive.padding),
          color: AppColors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Take Attendance', style: TextStyle(fontSize: responsive.fontSizeLarge, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  if (isAttendanceSaved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                      child: const Text('Completed', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(responsive.padding),
                decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [Icon(Icons.calendar_today, color: AppColors.primary), const SizedBox(width: 10), Text('Select Date')]),
                    Row(
                      children: [
                        Text('${_attendanceDate.day}/${_attendanceDate.month}/${_attendanceDate.year}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                        IconButton(icon: Icon(Icons.arrow_drop_down, color: AppColors.primary), onPressed: isAttendanceSaved ? null : _selectDate),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isAttendanceSaved ? null : () => _markAllAttendance(true),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('All Present'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isAttendanceSaved ? null : () => _markAllAttendance(false),
                      icon: const Icon(Icons.cancel),
                      label: const Text('All Absent'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(responsive.padding),
          margin: EdgeInsets.all(responsive.padding),
          decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Present', presentCount.toString(), Icons.check_circle, AppColors.success, responsive),
              _buildSummaryItem('Absent', (_students.length - presentCount).toString(), Icons.cancel, AppColors.error, responsive),
              _buildSummaryItem('Total', _students.length.toString(), Icons.people, AppColors.primary, responsive),
            ],
          ),
        ),
        Expanded(
          child: responsive.isDesktop
              ? _buildAttendanceTable(responsive, isAttendanceSaved)
              : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: responsive.padding),
            itemCount: _students.length,
            itemBuilder: (context, index) => _buildAttendanceItem(_students[index], responsive, isAttendanceSaved),
          ),
        ),
        Container(
          padding: EdgeInsets.all(responsive.padding),
          color: AppColors.white,
          child: SafeArea(
            child: ElevatedButton(
              onPressed: (isAttendanceSaved || _isSavingAttendance) ? null : _saveAttendance,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAttendanceSaved ? AppColors.grey : AppColors.primary,
                minimumSize: const Size(double.infinity, 45),
              ),
              child: _isSavingAttendance
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : (isAttendanceSaved ? const Text('Attendance Completed') : const Text('Save Attendance')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceTable(ResponsiveData responsive, bool isAttendanceSaved) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: EdgeInsets.all(responsive.padding),
        child: DataTable(
          columnSpacing: 20,
          headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
          columns: const [
            DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Admission No', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _students.map((student) {
            String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
            bool isPresent = _attendanceRecords[student['id']]?[dateKey] ?? false;

            return DataRow(cells: [
              DataCell(Text(student['name'])),
              DataCell(Text(student['admissionNo'])),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPresent ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPresent ? 'Present' : 'Absent',
                    style: TextStyle(color: isPresent ? AppColors.success : AppColors.error, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              DataCell(
                Switch(
                  value: isPresent,
                  onChanged: isAttendanceSaved ? null : (value) {
                    setState(() {
                      _attendanceRecords[student['id']]![dateKey] = value;
                    });
                  },
                  activeColor: AppColors.success,
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color, ResponsiveData responsive) {
    return Column(children: [
      Icon(icon, color: color, size: responsive.fontSizeMedium),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: responsive.fontSizeMedium)),
      Text(label, style: TextStyle(fontSize: responsive.fontSizeSmall - 1, color: AppColors.textSecondary)),
    ]);
  }

  Widget _buildAttendanceItem(Map<String, dynamic> student, ResponsiveData responsive, bool isAttendanceSaved) {
    String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
    bool isPresent = _attendanceRecords[student['id']]?[dateKey] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(responsive.padding),
      decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(student['name'], style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Admission: ${student['admissionNo']}', style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
            ]),
          ),
          if (_isSavingAttendance)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(
              value: isPresent,
              onChanged: isAttendanceSaved ? null : (value) => setState(() { _attendanceRecords[student['id']]![dateKey] = value; }),
              activeColor: AppColors.success,
            ),
          const SizedBox(width: 6),
          Text(isPresent ? 'Present' : 'Absent', style: TextStyle(color: isPresent ? AppColors.success : AppColors.error, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(ResponsiveData responsive) {
    if (_subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.warning),
            const SizedBox(height: 16),
            const Text('No subjects added yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Please add subjects to this classroom first', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddSubjectDialog,
              icon: const Icon(Icons.library_add),
              label: const Text('Add Subject'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: _subjects.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Record Results'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: _subjects.map((subject) => Tab(text: subject['name'])).toList(),
          ),
        ),
        body: TabBarView(
          children: _subjects.map((subject) => _buildSubjectScoreForm(subject, responsive)).toList(),
        ),
      ),
    );
  }

  Widget _buildSubjectScoreForm(Map<String, dynamic> subject, ResponsiveData responsive) {
    final subjectId = subject['id'].toString();

    return SingleChildScrollView(
      padding: EdgeInsets.all(responsive.padding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.isDesktop ? 1200 : double.infinity),
          child: Container(
            padding: EdgeInsets.all(responsive.padding),
            decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: responsive.isMobile ? 50 : 60,
                      height: responsive.isMobile ? 50 : 60,
                      decoration: BoxDecoration(gradient: AppColors.cardGradient, shape: BoxShape.circle),
                      child: const Icon(Icons.book, color: AppColors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(subject['name'], style: TextStyle(fontSize: responsive.fontSizeLarge, fontWeight: FontWeight.bold)),
                        Text('Enter scores for all students', style: TextStyle(color: AppColors.textSecondary, fontSize: responsive.fontSizeSmall)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Student Scores', style: TextStyle(fontSize: responsive.fontSizeMedium, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                responsive.isDesktop
                    ? _buildScoresTable(subject, responsive)
                    : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _students.length,
                  itemBuilder: (context, index) {
                    final student = _students[index];
                    final studentId = student['id'].toString();
                    final scores = _studentScores[studentId]?[subjectId];
                    return _buildStudentScoreCard(student, subject, scores, responsive);
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSavingResults ? null : () => _saveSubjectScores(subject),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: Size(double.infinity, responsive.isMobile ? 45 : 50),
                    padding: EdgeInsets.symmetric(vertical: responsive.isMobile ? 12 : 16),
                  ),
                  child: _isSavingResults
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                      : const Text('Save All Scores'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoresTable(Map<String, dynamic> subject, ResponsiveData responsive) {
    final subjectId = subject['id'].toString();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
        columns: const [
          DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Admission No', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('CA Score (0-100)', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Exam Score (0-100)', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _students.map((student) {
          final studentId = student['id'].toString();
          final scores = _studentScores[studentId]?[subjectId];
          int caScore = scores?['ca'] ?? 0;
          int examScore = scores?['exam'] ?? 0;
          int total = caScore + examScore;

          TextEditingController caController = TextEditingController(text: caScore == 0 ? '' : caScore.toString());
          TextEditingController examController = TextEditingController(text: examScore == 0 ? '' : examScore.toString());

          return DataRow(cells: [
            DataCell(Text(student['name'])),
            DataCell(Text(student['admissionNo'])),
            DataCell(
              SizedBox(
                width: 100,
                child: TextField(
                  controller: caController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'CA',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (value) {
                    int newCa = int.tryParse(value) ?? 0;
                    if (newCa >= 0 && newCa <= 100) {
                      setState(() {
                        if (_studentScores[studentId] == null) _studentScores[studentId] = {};
                        if (_studentScores[studentId]![subjectId] == null) _studentScores[studentId]![subjectId] = {};
                        _studentScores[studentId]![subjectId]!['ca'] = newCa;
                      });
                    }
                  },
                ),
              ),
            ),
            DataCell(
              SizedBox(
                width: 100,
                child: TextField(
                  controller: examController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Exam',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (value) {
                    int newExam = int.tryParse(value) ?? 0;
                    if (newExam >= 0 && newExam <= 100) {
                      setState(() {
                        if (_studentScores[studentId] == null) _studentScores[studentId] = {};
                        if (_studentScores[studentId]![subjectId] == null) _studentScores[studentId]![subjectId] = {};
                        _studentScores[studentId]![subjectId]!['exam'] = newExam;
                      });
                    }
                  },
                ),
              ),
            ),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(total).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$total%', style: TextStyle(color: _getScoreColor(total), fontWeight: FontWeight.bold)),
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildStudentScoreCard(Map<String, dynamic> student, Map<String, dynamic> subject, Map<String, dynamic>? scores, ResponsiveData responsive) {
    int caScore = scores?['ca'] ?? 0;
    int examScore = scores?['exam'] ?? 0;
    int total = caScore + examScore;
    final subjectId = subject['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(responsive.padding),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.greyLight)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: responsive.isMobile ? 40 : 45,
                height: responsive.isMobile ? 40 : 45,
                decoration: BoxDecoration(gradient: AppColors.cardGradient, shape: BoxShape.circle),
                child: Center(child: Text(student['name'][0], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.white))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(student['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: responsive.fontSizeSmall)),
                  Text('Admission: ${student['admissionNo']}', style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _getScoreColor(total).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('Total: $total%', style: TextStyle(color: _getScoreColor(total), fontWeight: FontWeight.bold, fontSize: responsive.fontSizeSmall - 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CA Score', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: caScore == 0 ? '' : caScore.toString()),
                      onChanged: (value) {
                        int newCa = int.tryParse(value) ?? 0;
                        if (newCa >= 0 && newCa <= 100) {
                          setState(() {
                            if (_studentScores[student['id']] == null) _studentScores[student['id']] = {};
                            if (_studentScores[student['id']]![subjectId] == null) _studentScores[student['id']]![subjectId] = {};
                            _studentScores[student['id']]![subjectId]!['ca'] = newCa;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'CA Score (0-100)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Exam Score', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: examScore == 0 ? '' : examScore.toString()),
                      onChanged: (value) {
                        int newExam = int.tryParse(value) ?? 0;
                        if (newExam >= 0 && newExam <= 100) {
                          setState(() {
                            if (_studentScores[student['id']] == null) _studentScores[student['id']] = {};
                            if (_studentScores[student['id']]![subjectId] == null) _studentScores[student['id']]![subjectId] = {};
                            _studentScores[student['id']]![subjectId]!['exam'] = newExam;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Exam Score (0-100)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesScreen(ResponsiveData responsive) {
    return const MessagesScreen();
  }

  Widget _buildMoreScreen(ResponsiveData responsive) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(responsive.padding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.isDesktop ? 800 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More Options', style: TextStyle(fontSize: responsive.fontSizeLarge, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(gradient: AppColors.cardGradientLight, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildMoreOption(Icons.assignment, 'All Assignments', 'View all assignments', _showViewAssignmentsScreen, responsive),
                    _buildMoreOption(Icons.history, 'Attendance History', 'View records', _showAttendanceHistory, responsive),
                    _buildMoreOption(Icons.message, 'Messages', 'View all messages', _navigateToMessages, responsive),
                    _buildMoreOption(Icons.logout, 'Logout', 'Sign out', _showLogoutDialog, responsive, isDestructive: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOption(IconData icon, String title, String subtitle, VoidCallback onTap, ResponsiveData responsive, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary, size: responsive.fontSizeMedium + 4),
      title: Text(title, style: TextStyle(color: isDestructive ? AppColors.error : AppColors.textPrimary, fontSize: responsive.fontSizeSmall)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: responsive.fontSizeSmall - 2, color: AppColors.textSecondary)),
      trailing: Icon(Icons.arrow_forward_ios, size: responsive.fontSizeSmall, color: AppColors.primary),
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: responsive.padding, vertical: responsive.isMobile ? 8 : 12),
    );
  }
}

// Responsive data class
class ResponsiveData {
  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;
  final double padding;
  final int gridCrossAxisCount;
  final int quickActionsCount;
  final double fontSizeSmall;
  final double fontSizeMedium;
  final double fontSizeLarge;
  final double fontSizeHeader;
  final double slideshowHeight;
  final double cardElevation;

  ResponsiveData({
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
    required this.padding,
    required this.gridCrossAxisCount,
    required this.quickActionsCount,
    required this.fontSizeSmall,
    required this.fontSizeMedium,
    required this.fontSizeLarge,
    required this.fontSizeHeader,
    required this.slideshowHeight,
    required this.cardElevation,
  });
}

// WhatsApp-style Chat List Screen for Teachers
class TeacherChatListScreen extends StatefulWidget {
  const TeacherChatListScreen({super.key});

  @override
  State<TeacherChatListScreen> createState() => _TeacherChatListScreenState();
}

class _TeacherChatListScreenState extends State<TeacherChatListScreen> {
  late ApiService _apiService;
  late UserModel _currentUser;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _classrooms = [];
  String _selectedClassroomId = '';
  String _selectedClassName = '';
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadUserData();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      setState(() {
        _errorMessage = 'Not authenticated';
        _isLoading = false;
      });
      return;
    }

    final classroomsResult = await _apiService.getTeacherClassrooms(
      token: token,
      teacherId: _currentUser.id,
    );

    if (classroomsResult['success'] && mounted) {
      final classrooms = classroomsResult['data'] as List? ?? [];
      setState(() {
        _classrooms = classrooms.map((c) => ({
          'id': c['classroomId'],
          'name': c['name'],
        })).toList();
      });

      if (_classrooms.isNotEmpty) {
        _selectedClassroomId = _classrooms[0]['id'];
        _selectedClassName = _classrooms[0]['name'];
        await _fetchStudents(token, _selectedClassroomId);
      } else {
        setState(() {
          _errorMessage = 'No classrooms assigned';
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _errorMessage = classroomsResult['message'] ?? 'Failed to load classrooms';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchStudents(String token, String classroomId) async {
    final studentsResult = await _apiService.getStudentsByClassroomId(token: token, classroomId: classroomId);

    if (studentsResult['success'] && mounted) {
      final studentsData = studentsResult['data'] as List? ?? [];

      setState(() {
        _students = studentsData.map((student) {
          final guardian = student['guardian'];
          final firstName = guardian?['firstname'] ?? '';
          final lastName = guardian?['lastname'] ?? '';
          final fullName = '$firstName $lastName'.trim();

          return {
            'id': student['studentId'] ?? '',
            'name': '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
            'admissionNo': student['studentNo'] ?? '',
            'className': _selectedClassName,
            'parentId': guardian?['guardianId'] ?? '',
            'parentName': fullName.isNotEmpty ? fullName : 'N/A',
            'parentEmail': guardian?['email'] ?? 'N/A',
            'parentPhone': guardian?['phone'] ?? 'N/A',
          };
        }).toList();
        _filteredStudents = List.from(_students);
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = studentsResult['message'] ?? 'Failed to load students';
        _isLoading = false;
      });
    }
  }

  void _filterStudents(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students.where((student) {
          final name = student['name'].toString().toLowerCase();
          final parentName = student['parentName'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              parentName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _startChat(Map<String, dynamic> student) {
    if (student['parentId'].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parent ID not found'), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          userId: student['parentId'],
          userRole: 'Guardian',
          userName: student['parentName'],
          userEmail: student['parentEmail'],
          userPhone: student['parentPhone'],
        ),
      ),
    );
  }

  ResponsiveData _getResponsiveData(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final isTablet = width >= 600 && width < 1200;
    final isDesktop = width >= 1200;

    return ResponsiveData(
      isMobile: isMobile,
      isTablet: isTablet,
      isDesktop: isDesktop,
      padding: isMobile ? 12.0 : (isTablet ? 20.0 : 24.0),
      gridCrossAxisCount: isMobile ? 2 : (isTablet ? 3 : 4),
      quickActionsCount: isMobile ? 4 : (isTablet ? 6 : 8),
      fontSizeSmall: isMobile ? 10.0 : (isTablet ? 12.0 : 13.0),
      fontSizeMedium: isMobile ? 14.0 : (isTablet ? 16.0 : 18.0),
      fontSizeLarge: isMobile ? 20.0 : (isTablet ? 24.0 : 28.0),
      fontSizeHeader: isMobile ? 22.0 : (isTablet ? 28.0 : 32.0),
      slideshowHeight: isMobile ? 150.0 : (isTablet ? 180.0 : 200.0),
      cardElevation: isMobile ? 2 : (isTablet ? 3 : 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = _getResponsiveData(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parents Chat'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_classrooms.length > 1)
            DropdownButton<String>(
              value: _selectedClassroomId,
              dropdownColor: Colors.white,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              style: const TextStyle(color: Colors.black),
              items: _classrooms.map((classroom) {
                return DropdownMenuItem<String>(
                  value: classroom['id'],
                  child: Text(classroom['name']),
                );
              }).toList(),
              onChanged: (value) async {
                if (value != null) {
                  setState(() {
                    _selectedClassroomId = value;
                    _selectedClassName = _classrooms.firstWhere((c) => c['id'] == value)['name'];
                    _isLoading = true;
                  });
                  final token = Provider.of<AuthProvider>(context, listen: false).token;
                  if (token != null) {
                    await _fetchStudents(token, value);
                  }
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: AppColors.textSecondary, fontSize: responsive.fontSizeMedium)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchData,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Container(
            padding: EdgeInsets.all(responsive.padding),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: _filterStudents,
              decoration: InputDecoration(
                hintText: 'Search by student or parent name...',
                hintStyle: TextStyle(fontSize: responsive.fontSizeSmall, color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppColors.primary, size: responsive.fontSizeMedium),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, size: responsive.fontSizeSmall),
                  onPressed: () {
                    _searchController.clear();
                    _filterStudents('');
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.greyLight,
                contentPadding: EdgeInsets.symmetric(
                  vertical: responsive.isMobile ? 10 : 12,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          if (_isSearching)
            Container(
              padding: EdgeInsets.symmetric(horizontal: responsive.padding, vertical: 8),
              color: AppColors.primary.withOpacity(0.05),
              child: Text(
                'Found ${_filteredStudents.length} student${_filteredStudents.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: responsive.fontSizeSmall,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(
            child: _filteredStudents.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.grey),
                  const SizedBox(height: 16),
                  Text(
                    _isSearching ? 'No parents found' : 'No students in this class',
                    style: TextStyle(
                      fontSize: responsive.fontSizeMedium,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : responsive.isDesktop
                ? _buildChatTable(responsive)
                : ListView.builder(
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) {
                final student = _filteredStudents[index];
                return InkWell(
                  onTap: () => _startChat(student),
                  child: Container(
                    padding: EdgeInsets.all(responsive.padding),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: AppColors.greyLight, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: responsive.isMobile ? 50 : 55,
                          height: responsive.isMobile ? 50 : 55,
                          decoration: BoxDecoration(
                            gradient: AppColors.cardGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              student['parentName'][0].toUpperCase(),
                              style: TextStyle(
                                fontSize: responsive.fontSizeMedium + 4,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student['parentName'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: responsive.fontSizeSmall,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Student: ${student['name']} • Class: ${student['className']}',
                                style: TextStyle(
                                  fontSize: responsive.fontSizeSmall - 2,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(Icons.message, color: Colors.white, size: responsive.fontSizeMedium),
                            onPressed: () => _startChat(student),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTable(ResponsiveData responsive) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: EdgeInsets.all(responsive.padding),
        child: DataTable(
          columnSpacing: 20,
          headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
          columns: const [
            DataColumn(label: Text('Parent Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Class', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Contact', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _filteredStudents.map((student) {
            return DataRow(cells: [
              DataCell(Text(student['parentName'])),
              DataCell(Text(student['name'])),
              DataCell(Text(student['className'])),
              DataCell(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (student['parentPhone'] != 'N/A')
                    InkWell(
                      onTap: () {
                        final phoneUri = Uri(scheme: 'tel', path: student['parentPhone']);
                        canLaunchUrl(phoneUri).then((canLaunch) {
                          if (canLaunch) launchUrl(phoneUri);
                        });
                      },
                      child: Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(student['parentPhone'], style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  if (student['parentEmail'] != 'N/A')
                    Text(student['parentEmail'], style: const TextStyle(fontSize: 11)),
                ],
              )),
              DataCell(
                ElevatedButton.icon(
                  onPressed: () => _startChat(student),
                  icon: const Icon(Icons.message),
                  label: const Text('Chat'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}