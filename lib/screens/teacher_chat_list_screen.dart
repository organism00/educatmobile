import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'conversation_screen.dart';


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

      // Debug: Print first student to see structure
      if (studentsData.isNotEmpty) {
        print('===== First student data =====');
        print(studentsData[0]);
        print('Guardian object: ${studentsData[0]['guardian']}');
        print('Guardian ID: ${studentsData[0]['guardian']?['guardianId']}');
      }

      setState(() {
        // Use the EXACT same mapping as the Teacher Dashboard
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
    final parentId = student['parentId']?.toString() ?? '';

    print('Starting chat with parent ID: $parentId'); // Debug

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
          userName: student['parentName'],
          userEmail: student['parentEmail'],
          userPhone: student['parentPhone'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

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
            Text(_errorMessage!, style: TextStyle(color: AppColors.textSecondary)),
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
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: _filterStudents,
              decoration: InputDecoration(
                hintText: 'Search by student or parent name...',
                hintStyle: TextStyle(fontSize: isSmallScreen ? 13 : 14, color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppColors.primary, size: isSmallScreen ? 20 : 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, size: isSmallScreen ? 18 : 20),
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
                  vertical: isSmallScreen ? 10 : 12,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          if (_isSearching)
            Container(
              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16, vertical: 8),
              color: AppColors.primary.withOpacity(0.05),
              child: Text(
                'Found ${_filteredStudents.length} student${_filteredStudents.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 13,
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
                      fontSize: isSmallScreen ? 14 : 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) {
                final student = _filteredStudents[index];
                return InkWell(
                  onTap: () => _startChat(student),
                  child: Container(
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: AppColors.greyLight, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: isSmallScreen ? 50 : 55,
                          height: isSmallScreen ? 50 : 55,
                          decoration: BoxDecoration(
                            gradient: AppColors.cardGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              student['parentName'] != 'N/A' && student['parentName'].isNotEmpty
                                  ? student['parentName'][0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 20 : 24,
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
                                  fontSize: isSmallScreen ? 15 : 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Student: ${student['name']} • Class: ${student['className']}',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 11 : 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: student['parentId'].isNotEmpty && student['parentId'] != 'N/A'
                                ? AppColors.primary
                                : AppColors.grey,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(Icons.message, color: Colors.white, size: isSmallScreen ? 18 : 20),
                            onPressed: student['parentId'].isNotEmpty && student['parentId'] != 'N/A'
                                ? () => _startChat(student)
                                : null,
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
}