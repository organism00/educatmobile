import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'login_screen.dart';

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

  // Results data
  Map<String, Map<String, int>> _studentResults = {};
  List<String> _subjects = ['Mathematics', 'English', 'Science', 'Social Studies', 'Computer Studies'];
  bool _isSavingResults = false;

  // Chat messages
  Map<String, List<Map<String, dynamic>>> _chatMessages = {};

  // News data
  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  // Activity Slideshow
  final List<Map<String, dynamic>> _activitySlides = [
    {
      'title': '📝 Mark Attendance',
      'description': 'Don\'t forget to mark student attendance today',
      'icon': Icons.checklist,
      'color': Color(0xFF4CAF50),
      'action': 'Take Attendance',
    },
    {
      'title': '📊 Record Results',
      'description': 'Upload continuous assessment scores',
      'icon': Icons.grade,
      'color': Color(0xFFFF9800),
      'action': 'Record Results',
    },
    {
      'title': '💬 Message Parents',
      'description': 'Keep parents updated on student progress',
      'icon': Icons.message,
      'color': Color(0xFF2196F3),
      'action': 'Send Message',
    },
    {
      'title': '📚 Lesson Notes',
      'description': 'Prepare lesson notes for next class',
      'icon': Icons.menu_book,
      'color': Color(0xFF9C27B0),
      'action': 'View Notes',
    },
    {
      'title': '🎯 Weekly Goals',
      'description': 'Review and set teaching objectives',
      'icon': Icons.flag,
      'color': Color(0xFFE91E63),
      'action': 'Set Goals',
    },
    {
      'title': '👥 Parent Meeting',
      'description': 'Schedule parent-teacher conference',
      'icon': Icons.people,
      'color': Color(0xFF00BCD4),
      'action': 'Schedule',
    },
  ];

  int _currentSlideIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadUserData();
    _fetchDashboardData();
    _fetchNews();
    _pageController = PageController(initialPage: 0);

    Future.delayed(Duration.zero, () {
      if (mounted) {
        _startAutoScroll();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _pageController.hasClients) {
        if (_currentSlideIndex < _activitySlides.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          _pageController.jumpToPage(0);
        }
        _startAutoScroll();
      }
    });
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = widget.user ?? authProvider.currentUser!;
  }

  Future<void> _fetchDashboardData() async {
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

    // Step 1: Get teacher details
    final teacherResult = await _apiService.getTeacherById(
      token: token,
      teacherId: _currentUser.id,
    );

    if (teacherResult['success'] && mounted) {
      final teacherData = teacherResult['data'];
      setState(() {
        _currentUser = UserModel.fromTeacherData(teacherData, _currentUser);
      });
    }

    // Step 2: Get teacher's classrooms
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
          'capacity': c['capacity'],
        })).toList();
      });

      if (classrooms.isNotEmpty) {
        _selectedClassroomId = classrooms[0]['classroomId'];
        _selectedClassName = classrooms[0]['name'];
        await _fetchStudents(token, _selectedClassroomId);
      } else {
        setState(() {
          _errorMessage = 'No classroom assigned to you';
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

  void _filterStudents(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students.where((student) {
          final name = student['name'].toString().toLowerCase();
          final admissionNo = student['admissionNo'].toString().toLowerCase();
          final searchQuery = query.toLowerCase();
          return name.contains(searchQuery) || admissionNo.contains(searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _fetchStudents(String token, String classroomId) async {
    final studentsResult = await _apiService.getStudentsByClassroomId(
      token: token,
      classroomId: classroomId,
    );

    if (studentsResult['success'] && mounted) {
      final studentsData = studentsResult['data'] as List? ?? [];

      setState(() {
        _students = studentsData.map((student) => ({
          'id': student['studentId'] ?? '',
          'name': '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
          'admissionNo': student['studentNo'] ?? '',
          'className': _selectedClassName,
          'parentName': student['guardian']?['firstname'] ?? 'N/A',
          'parentEmail': student['guardian']?['email'] ?? 'N/A',
          'gender': student['gender'] ?? 'Not specified',
          'averageScore': 0,
          'attendance': 0,
        })).toList();
        _filteredStudents = List.from(_students);

        // Initialize attendance records
        for (var student in _students) {
          _attendanceRecords[student['id']] = {};
        }

        // Initialize results
        for (var student in _students) {
          _studentResults[student['id']] = {};
          for (var subject in _subjects) {
            _studentResults[student['id']]![subject] = 0;
          }
        }

        // Initialize chat messages
        for (var student in _students) {
          _chatMessages[student['parentName']] = [
            {'text': 'Hello, how is my child doing?', 'isMe': false, 'time': 'Yesterday', 'sender': student['parentName']},
            {'text': 'Your child is doing well in class!', 'isMe': true, 'time': 'Yesterday', 'sender': 'Me'},
          ];
        }

        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = studentsResult['message'] ?? 'Failed to load students';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchNews() async {
    setState(() {
      _isLoadingNews = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token != null) {
      final newsResult = await _apiService.getAllNews(token: token);
      if (newsResult['success'] && mounted) {
        setState(() {
          _news = (newsResult['data'] as List?)?.map((item) => ({
            'id': item['id'],
            'title': item['title'],
            'content': item['content'],
            'date': item['date'],
          })).toList() ?? [];
          _isLoadingNews = false;
        });
      } else {
        setState(() {
          _isLoadingNews = false;
        });
      }
    } else {
      setState(() {
        _isLoadingNews = false;
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token != null) {
      await _fetchStudents(token, _selectedClassroomId);
    }
    await _fetchNews();
    setState(() {
      _isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B35), Color(0xFFF7931E), Color(0xFFFFB347)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.white))
              : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _selectedIndex == 0
                ? _buildHomeScreen()
                : _buildScreenForIndex(_selectedIndex),
          ),
        ),
      ),
      bottomNavigationBar: _isLoading || _errorMessage != null ? null : _buildBottomNavigationBar(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.white),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: AppColors.white, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchDashboardData,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.white, foregroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey,
        currentIndex: _selectedIndex,
        elevation: 0,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Students'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Attendance'),
          BottomNavigationBarItem(icon: Icon(Icons.grade_rounded), label: 'Results'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildHomeScreen() {
    int presentToday = _getTodayAttendanceCount();
    int totalStudents = _students.length;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_classrooms.length > 1)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButton<String>(
                value: _selectedClassroomId,
                dropdownColor: AppColors.white,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                style: const TextStyle(color: AppColors.white),
                items: _classrooms.map<DropdownMenuItem<String>>((classroom) {
                  return DropdownMenuItem<String>(
                    value: classroom['id'] as String,
                    child: Text(classroom['name'] as String),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    setState(() {
                      _selectedClassroomId = value;
                      _selectedClassName = _classrooms.firstWhere((c) => c['id'] == value)['name'] as String;
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
            ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard('Total Students', '${_students.length}', Icons.people, AppColors.primary),
              _buildStatCard('Present Today', '$presentToday/$totalStudents', Icons.check_circle, AppColors.success),
              _buildStatCard('Class', _selectedClassName, Icons.class_, AppColors.warning),
              _buildStatCard('Subjects', '${_subjects.length}', Icons.book, AppColors.info),
            ],
          ),
          const SizedBox(height: 16),
          _buildActivitySlideshow(),
          const SizedBox(height: 16),
          _buildQuickActions(),
          const SizedBox(height: 16),
          _buildRecentActivities(),
          const SizedBox(height: 16),
          _buildNewsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActivitySlideshow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '✨ Teacher Activities',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentSlideIndex = index;
              });
            },
            itemCount: _activitySlides.length,
            itemBuilder: (context, index) {
              final slide = _activitySlides[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (slide['color'] as Color).withOpacity(0.9),
                      (slide['color'] as Color).withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (slide['color'] as Color).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _handleActivityTap(slide['action'] as String);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  slide['icon'] as IconData,
                                  size: 24,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '${index + 1}/${_activitySlides.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slide['title'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            slide['description'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slide['action'] as String,
                                  style: TextStyle(
                                    color: slide['color'] as Color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: slide['color'] as Color,
                                ),
                              ],
                            ),
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
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _activitySlides.length,
                (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentSlideIndex == index
                    ? AppColors.white
                    : AppColors.white.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleActivityTap(String action) {
    switch (action) {
      case 'Take Attendance':
        setState(() {
          _selectedIndex = 2;
        });
        break;
      case 'Record Results':
        setState(() {
          _selectedIndex = 3;
        });
        break;
      case 'Send Message':
        setState(() {
          _selectedIndex = 4;
        });
        break;
      default:
        _showComingSoon(action);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature coming soon!'),
        backgroundColor: AppColors.info,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: TextStyle(color: AppColors.white.withOpacity(0.9), fontSize: 14)),
            const SizedBox(height: 4),
            Text(_currentUser.name.isNotEmpty ? _currentUser.name : 'Teacher', style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            Text(_currentUser.schoolName, style: TextStyle(color: AppColors.white.withOpacity(0.8), fontSize: 14)),
          ],
        ),
        Container(
          width: 55, height: 55,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.white, AppColors.cream]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)]),
          child: const Icon(Icons.person, size: 30, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
          children: [
            _buildActionTile(Icons.checklist, 'Take\nAttendance', () => setState(() => _selectedIndex = 2)),
            _buildActionTile(Icons.grade, 'Record\nResults', () => setState(() => _selectedIndex = 3)),
            _buildActionTile(Icons.message, 'Send\nNotice', () => _showSendNoticeDialog()),
            _buildActionTile(Icons.people, 'View\nStudents', () => setState(() => _selectedIndex = 1)),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: AppColors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.white.withOpacity(0.3))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: AppColors.white),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivities() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => const ListTile(
              leading: CircleAvatar(child: Icon(Icons.notifications, size: 20)),
              title: Text('Assignment submitted'),
              subtitle: Text('2 hours ago'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection() {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_news.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('School News', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _news.length > 3 ? 3 : _news.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _news[index];
              return ListTile(
                leading: CircleAvatar(child: Icon(Icons.newspaper, size: 20, color: AppColors.primary)),
                title: Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item['date'] ?? 'Recent'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showNewsDetails(item),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 1: return _buildStudentsScreen();
      case 2: return _buildAttendanceScreen();
      case 3: return _buildResultsScreen();
      case 4: return _buildChatScreen();
      case 5: return _buildMoreScreen();
      default: return _buildHomeScreen();
    }
  }

  // ==================== STUDENTS SCREEN WITH SEARCH ====================

  Widget _buildStudentsScreen() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.white,
          child: TextField(
            controller: _searchController,
            onChanged: _filterStudents,
            decoration: InputDecoration(
              hintText: 'Search by name or admission number...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.grey),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearching && _filteredStudents.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: AppColors.grey),
                  SizedBox(height: 16),
                  Text('No students found', style: TextStyle(color: AppColors.grey)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) => _buildStudentCard(_filteredStudents[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), shape: BoxShape.circle),
                child: Center(child: Text((student['name'] as String)[0], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.white))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(student['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Admission: ${student['admissionNo']}', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  Text('Parent: ${student['parentName']}', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _getScoreColor(student['averageScore']).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('${student['averageScore']}%', style: TextStyle(color: _getScoreColor(student['averageScore']), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStudentInfo('Attendance', '${student['attendance']}%', Icons.calendar_today),
              _buildStudentInfo('Average', '${student['averageScore']}%', Icons.grade),
              _buildStudentInfo('Gender', student['gender'], Icons.person),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _showStudentDetails(student), icon: const Icon(Icons.visibility), label: const Text('Details'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: () => _sendMessageToParent(student), icon: const Icon(Icons.message), label: const Text('Message Parent'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.grey)),
      ],
    );
  }

  // ==================== ATTENDANCE SCREEN ====================

  Widget _buildAttendanceScreen() {
    bool isAttendanceTaken = _isAttendanceTakenForToday();
    int presentCount = _getAttendanceCountForDate(_attendanceDate);
    int absentCount = _students.length - presentCount;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: AppColors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Take Attendance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  if (isAttendanceTaken)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Row(children: const [Icon(Icons.check_circle, color: AppColors.success, size: 16), SizedBox(width: 4), Text('Completed', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12))]),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [Icon(Icons.calendar_today, color: AppColors.primary), SizedBox(width: 12), Text('Select Date', style: TextStyle(fontSize: 16))]),
                    Row(children: [Text('${_attendanceDate.day}/${_attendanceDate.month}/${_attendanceDate.year}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)), IconButton(icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary), onPressed: () => _selectDate())]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () => _markAllAttendance(true), icon: const Icon(Icons.check_circle), label: const Text('All Present'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.success))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: () => _markAllAttendance(false), icon: const Icon(Icons.cancel), label: const Text('All Absent'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)))),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Present', presentCount.toString(), Icons.check_circle, AppColors.success),
              _buildSummaryItem('Absent', absentCount.toString(), Icons.cancel, AppColors.error),
              _buildSummaryItem('Total', _students.length.toString(), Icons.people, AppColors.primary),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _students.length,
            itemBuilder: (context, index) => _buildAttendanceItem(_students[index]),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          color: AppColors.white,
          child: SafeArea(
            child: ElevatedButton(
              onPressed: isAttendanceTaken || _isSavingAttendance ? null : _saveAttendance,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 50)),
              child: _isSavingAttendance
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : (isAttendanceTaken ? const Text('Attendance Already Taken Today') : const Text('Save Attendance', style: TextStyle(fontSize: 16))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(children: [Icon(icon, color: color), const SizedBox(height: 4), Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)), Text(label, style: const TextStyle(fontSize: 11, color: AppColors.grey))]);
  }

  Widget _buildAttendanceItem(Map<String, dynamic> student) {
    String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
    bool isPresent = _attendanceRecords[student['id']]?[dateKey] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Admission: ${student['admissionNo']}', style: const TextStyle(fontSize: 12, color: AppColors.grey)),
              ],
            ),
          ),
          if (_isSavingAttendance)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            )
          else
            Switch(
              value: isPresent,
              onChanged: (value) {
                setState(() {
                  _attendanceRecords[student['id']]![dateKey] = value;
                });
              },
              activeColor: AppColors.success,
            ),
          const SizedBox(width: 8),
          Text(
            isPresent ? 'Present' : 'Absent',
            style: TextStyle(
              color: isPresent ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== RESULTS SCREEN ====================

  Widget _buildResultsScreen() {
    return DefaultTabController(
      length: _students.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Record Results', style: TextStyle(color: AppColors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.white,
            labelColor: AppColors.white,
            unselectedLabelColor: AppColors.white,
            tabs: _students.map((student) => Tab(text: student['name'].split(' ')[0])).toList(),
          ),
        ),
        body: TabBarView(
          children: _students.map((student) => _buildResultForm(student)).toList(),
        ),
      ),
    );
  }

  Widget _buildResultForm(Map<String, dynamic> student) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Row(children: [
              Container(width: 50, height: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), shape: BoxShape.circle), child: Center(child: Text(student['name'][0], style: const TextStyle(fontSize: 20, color: AppColors.white)))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(student['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('Admission: ${student['admissionNo']}', style: const TextStyle(color: AppColors.grey))])),
            ]),
            const SizedBox(height: 20),
            const Text('Enter Subject Scores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._subjects.map((subject) => _buildScoreInput(student['id'], subject)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSavingResults ? null : () => _saveStudentResults(student['id']),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 50)),
              child: _isSavingResults
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : const Text('Save Results'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreInput(String studentId, String subject) {
    int currentScore = _studentResults[studentId]?[subject] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(subject, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Score (0-100)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onChanged: (value) {
                int score = int.tryParse(value) ?? 0;
                if (score >= 0 && score <= 100) {
                  setState(() {
                    _studentResults[studentId]![subject] = score;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _getScoreColor(currentScore).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$currentScore%', textAlign: TextAlign.center, style: TextStyle(color: _getScoreColor(currentScore), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==================== CHAT SCREEN ====================

  Widget _buildChatScreen() {
    List<Map<String, dynamic>> parents = [];
    for (var student in _students) {
      if (!parents.any((p) => p['name'] == student['parentName'])) {
        parents.add({'name': student['parentName'], 'student': student['name'], 'unread': 0});
      }
    }

    return Column(
      children: [
        Container(padding: const EdgeInsets.all(20), color: AppColors.white, child: const Center(child: Text('Parent Chats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)))),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: parents.length,
            itemBuilder: (context, index) => _buildChatCard(parents[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildChatCard(Map<String, dynamic> parent) {
    List<Map<String, dynamic>> messages = _chatMessages[parent['name']] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => _openChat(parent),
        child: Row(
          children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), shape: BoxShape.circle), child: Center(child: Text(parent['name'][0], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.white)))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(parent['name'], style: const TextStyle(fontWeight: FontWeight.bold)), Text('Parent of ${parent['student']}', style: const TextStyle(fontSize: 12, color: AppColors.grey)), if (messages.isNotEmpty) Text(messages.last['text'], style: TextStyle(fontSize: 14, color: AppColors.grey), maxLines: 1)])),
            if (messages.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(messages.last['time'], style: const TextStyle(fontSize: 12, color: AppColors.grey))]),
          ],
        ),
      ),
    );
  }

  // ==================== MORE SCREEN WITH LOGOUT ====================

  Widget _buildMoreScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'More Options',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _buildMoreOption(Icons.history, 'Attendance History', 'View all attendance records', () => _showAttendanceHistory()),
                _buildMoreOption(Icons.settings, 'Settings', 'App preferences and notifications', () {
                  _showComingSoon('Settings');
                }),
                _buildMoreOption(Icons.help, 'Help & Support', 'FAQs and contact support', () {
                  _showComingSoon('Help & Support');
                }),
                _buildMoreOption(Icons.privacy_tip, 'Privacy Policy', 'Read our privacy policy', () {
                  _showComingSoon('Privacy Policy');
                }),
                _buildMoreOption(Icons.description, 'Terms & Conditions', 'Terms of service', () {
                  _showComingSoon('Terms & Conditions');
                }),
                _buildMoreOption(Icons.logout, 'Logout', 'Sign out of your account', _showLogoutDialog, isDestructive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreOption(IconData icon, String title, String subtitle, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.error : AppColors.black,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  void _showAttendanceHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance History',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder(
                    future: _fetchAttendanceHistoryData(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                      }

                      if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: AppColors.grey),
                              SizedBox(height: 16),
                              Text('No attendance records found', style: TextStyle(color: AppColors.grey)),
                            ],
                          ),
                        );
                      }

                      final history = snapshot.data as List;
                      return ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final record = history[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: record['status'] == 1
                                        ? AppColors.success.withOpacity(0.1)
                                        : AppColors.error.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    record['status'] == 1 ? Icons.check_circle : Icons.cancel,
                                    color: record['status'] == 1 ? AppColors.success : AppColors.error,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record['studentName'] ?? 'Student',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Date: ${record['date']?.split('T')[0] ?? 'N/A'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: record['status'] == 1
                                        ? AppColors.success.withOpacity(0.1)
                                        : AppColors.error.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    record['status'] == 1 ? 'Present' : 'Absent',
                                    style: TextStyle(
                                      color: record['status'] == 1 ? AppColors.success : AppColors.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAttendanceHistoryData() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return [];

    final result = await _apiService.getAttendanceByActiveTerm(
      token: token,
      schoolId: _currentUser.schoolId,
      classroomId: _selectedClassroomId,
    );

    if (result['success'] && result['data'] != null) {
      return (result['data'] as List).map((record) => {
        'studentId': record['studentId'],
        'studentName': record['studentName'],
        'date': record['date'],
        'status': record['status'],
      }).toList();
    }

    return [];
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ==================== HELPER METHODS ====================

  int _getTodayAttendanceCount() {
    String todayKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    int count = 0;
    for (var student in _students) {
      if (_attendanceRecords[student['id']]?[todayKey] == true) count++;
    }
    return count;
  }

  int _getAttendanceCountForDate(DateTime date) {
    String dateKey = '${date.year}-${date.month}-${date.day}';
    int count = 0;
    for (var student in _students) {
      if (_attendanceRecords[student['id']]?[dateKey] == true) count++;
    }
    return count;
  }

  int _getClassAverageScore() {
    if (_students.isEmpty) return 0;
    int total = 0;
    for (var student in _students) {
      total += student['averageScore'] as int;
    }
    return total ~/ _students.length;
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  bool _isAttendanceTakenForToday() {
    String todayKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    for (var student in _students) {
      if (_attendanceRecords[student['id']]?.containsKey(todayKey) == true) {
        return true;
      }
    }
    return false;
  }

  // ==================== ACTION METHODS ====================

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _attendanceDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _attendanceDate = picked;
      });
    }
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

    setState(() {
      _isSavingAttendance = true;
    });

    String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
    int successCount = 0;
    int failureCount = 0;
    List<String> failedStudents = [];

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving attendance...'),
        duration: Duration(seconds: 1),
      ),
    );

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

      if (result['success']) {
        successCount++;
      } else {
        failureCount++;
        failedStudents.add(student['name']);
      }
    }

    setState(() {
      _isSavingAttendance = false;
    });

    if (failureCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Attendance saved successfully for $successCount students!'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Saved: $successCount, Failed: $failureCount. Failed: ${failedStudents.join(', ')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _saveStudentResults(String studentId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() {
      _isSavingResults = true;
    });

    List<Map<String, dynamic>> results = _subjects.map((subject) {
      return {
        'subjectName': subject,
        'score': _studentResults[studentId]?[subject] ?? 0,
      };
    }).toList();

    final result = await _apiService.saveTeacherResults(
      token: token,
      schoolId: _currentUser.schoolId,
      classroomId: _selectedClassroomId,
      studentId: studentId,
      sessionId: _currentUser.sessionId,
      termId: _currentUser.termId,
      results: results,
    );

    setState(() {
      _isSavingResults = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['success'] ? 'Results saved successfully!' : result['message']),
        backgroundColor: result['success'] ? AppColors.success : AppColors.error,
      ),
    );
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(student['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admission No: ${student['admissionNo']}'),
            Text('Class: ${student['className']}'),
            Text('Gender: ${student['gender']}'),
            Text('Parent: ${student['parentName']}'),
            Text('Parent Email: ${student['parentEmail']}'),
            const Divider(),
            Text('Average Score: ${student['averageScore']}%'),
            Text('Attendance Rate: ${student['attendance']}%'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _sendMessageToParent(Map<String, dynamic> student) {
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Message ${student['parentName']}'),
        content: TextField(
          controller: messageController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Type your message here...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (messageController.text.isNotEmpty) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Message sent to ${student['parentName']}!'), backgroundColor: AppColors.success),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _openChat(Map<String, dynamic> parent) {
    final messageController = TextEditingController();
    List<Map<String, dynamic>> messages = _chatMessages[parent['name']] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), shape: BoxShape.circle), child: Center(child: Text(parent['name'][0]))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(parent['name'], style: const TextStyle(fontWeight: FontWeight.bold)), Text('Parent of ${parent['student']}', style: const TextStyle(fontSize: 12, color: AppColors.grey))])),
                ]),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: message['isMe'] ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: message['isMe'] ? AppColors.primary : Colors.grey[300], borderRadius: BorderRadius.circular(12)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(message['text'], style: TextStyle(color: message['isMe'] ? Colors.white : Colors.black87)), Text(message['time'], style: TextStyle(fontSize: 10, color: message['isMe'] ? Colors.white70 : Colors.grey[600]))]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: messageController, decoration: InputDecoration(hintText: 'Type a message...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))))),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: () {
                        if (messageController.text.isNotEmpty) {
                          setState(() {
                            messages.insert(0, {'text': messageController.text, 'isMe': true, 'time': 'Just now', 'sender': 'Me'});
                            _chatMessages[parent['name']] = messages;
                            messageController.clear();
                          });
                        }
                      }),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSendNoticeDialog() {
    final noticeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Notice to Parents'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This notice will be sent to all parents in your class.'),
            const SizedBox(height: 16),
            TextField(controller: noticeController, maxLines: 5, decoration: const InputDecoration(hintText: 'Type your notice here...', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (noticeController.text.isNotEmpty) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notice sent to all parents!'), backgroundColor: AppColors.success),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Send Notice'),
          ),
        ],
      ),
    );
  }

  void _showNewsDetails(Map<String, dynamic> news) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(news['title']),
        content: SingleChildScrollView(child: Text(news['content'])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}