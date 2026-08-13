import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../screens/conversation_screen.dart';
import '../screens/messages_screen.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  late UserModel _currentUser;
  late ApiService _apiService;

  // Data states
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filteredTeachers = [];
  List<Map<String, dynamic>> _guardians = [];
  List<Map<String, dynamic>> _filteredGuardians = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _filteredClassrooms = [];
  List<Map<String, dynamic>> _guardianTransactions = [];
  int _guardianCount = 0;

  // Classroom financial data cache
  Map<String, Map<String, dynamic>> _classroomFinancialData = {};
  bool _financialDataLoaded = false;

  // Guardian to students mapping
  Map<String, List<Map<String, dynamic>>> _guardianStudentsMap = {};

  // Messages - Unread count
  int _unreadMessageCount = 0;

  // Search Controllers
  final TextEditingController _studentSearchController = TextEditingController();
  final TextEditingController _teacherSearchController = TextEditingController();
  final TextEditingController _guardianSearchController = TextEditingController();
  final TextEditingController _classroomSearchController = TextEditingController();

  bool _isSearchingStudents = false;
  bool _isSearchingTeachers = false;
  bool _isSearchingGuardians = false;
  bool _isSearchingClassrooms = false;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Responsive variables
  late bool _isMobile;
  late bool _isTablet;
  late bool _isDesktop;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadUserData();
    _fetchDashboardData();
    _fetchUnreadMessages();

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
// Add this method to your Admin Dashboard class

  String _getCurrentSessionId() {
    // Try to get session ID from current user
    String sessionId = _currentUser.sessionId ?? '';

    if (sessionId.isEmpty) {
      // Try to get from user model's sessionId
      sessionId = _currentUser.sessionId ?? '';
    }

    if (sessionId.isEmpty) {
      // Default to current academic year
      final now = DateTime.now();
      final year = now.year;
      final nextYear = year + 1;
      sessionId = '$year/$nextYear';
      print('⚠️ Using default session ID: $sessionId');
    }

    print('📅 Session ID being used: $sessionId');
    return sessionId;
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;
  }

  Future<void> _fetchUnreadMessages() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    final result = await _apiService.getInboxMessages(
      token: token,
      userId: _currentUser.id,
      userRole: 'SchoolAdmin',
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

    try {
      // Get the session ID
      final sessionId = _getCurrentSessionId();
      final termId = _currentUser.termId ?? '1';

      print('📊 Fetching dashboard data...');
      print('📅 Session ID: $sessionId');
      print('📚 Term ID: $termId');

      // First, get expected revenue data directly
      print('💰 Fetching expected revenue...');
      final expectedRevenueResult = await _apiService.getExpectedRevenueForTerm(
        token: token,
        sessionId: sessionId,
        termId: termId,
      );

      Map<String, Map<String, dynamic>> expectedRevenueMap = {};
      double totalExpectedRevenue = 0;

      if (expectedRevenueResult['success'] && expectedRevenueResult['data'] != null) {
        final data = expectedRevenueResult['data'];
        final classroomDetails = data['classroomDetails'] as List? ?? [];
        print('📊 Found ${classroomDetails.length} classroom details');

        for (var classroom in classroomDetails) {
          final classFee = (classroom['classFee'] ?? 0.0).toDouble();
          final numberOfStudents = (classroom['numberOfStudents'] ?? 0).toInt();
          final expectedRevenue = (classroom['expectedRevenue'] ?? 0.0).toDouble();
          totalExpectedRevenue += expectedRevenue;

          expectedRevenueMap[classroom['classroomId']] = {
            'expectedRevenue': expectedRevenue,
            'classFee': classFee,
            'numberOfStudents': numberOfStudents,
          };

          print('   📚 ${classroom['className']}: Fee=₦$classFee, Students=$numberOfStudents, Expected=₦$expectedRevenue');
        }
        print('💰 Total Expected Revenue: ₦$totalExpectedRevenue');
      } else {
        print('❌ Failed to fetch expected revenue: ${expectedRevenueResult['message']}');
        // Continue with empty expected revenue map
      }

      // Then fetch classrooms with the expected revenue map
      await _fetchClassrooms(token, expectedRevenueMap);

      // Then fetch all other data in parallel
      await Future.wait([
        _fetchStudents(token),
        _fetchTeachers(token),
        _fetchGuardians(token),
        _fetchGuardianCount(token),
        _fetchGuardianTransactions(token),
      ]);

      // After classrooms are loaded, fetch financial data for each
      await _fetchAllClassroomFinancialData(token, expectedRevenueMap, sessionId, termId);

      setState(() {
        _filteredStudents = List.from(_students);
        _filteredTeachers = List.from(_teachers);
        _filteredGuardians = List.from(_guardians);
        _filteredClassrooms = List.from(_classrooms);
        _isLoading = false;
      });

      // Fetch guardian students mappings
      _fetchGuardianStudentsMappings(token);

    } catch (e) {
      print('❌ Error in _fetchDashboardData: $e');
      setState(() {
        _errorMessage = 'Error loading data. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchStudents(String token) async {
    try {
      final result = await _apiService.getAllStudentsBySchool(
        token: token,
        schoolId: _currentUser.schoolId,
      );
      if (result['success'] && mounted) {
        final studentsData = result['data'] as List? ?? [];
        setState(() {
          _students = studentsData.map((s) => ({
            'id': s['studentId'] ?? '',
            'name': '${s['firstname'] ?? ''} ${s['lastname'] ?? ''}'.trim(),
            'admissionNo': s['studentNo'] ?? s['admissionNo'] ?? '',
            'classroomId': s['classroomId'] ?? '',
            'className': s['classroomName'] ?? 'Not Assigned',
            'guardianId': s['guardianId'] ?? '',
            'guardianName': s['guardianName'] ?? 'N/A',
            'guardianPhone': s['guardianPhone'] ?? 'N/A',
            'guardianEmail': s['guardianEmail'] ?? 'N/A',
            'teacherId': s['teacherId'] ?? '',
            'teacherName': s['teacher']?['firstname'] != null
                ? '${s['teacher']['firstname']} ${s['teacher']['lastname']}'.trim()
                : 'Not Assigned',
            'gender': s['gender'] ?? 'Not specified',
            'dateOfBirth': s['dateOfBirth'] ?? '',
          })).toList();
          _filteredStudents = List.from(_students);
        });
      }
    } catch (e) {
      print('Error fetching students: $e');
    }
  }

  void _filterStudents(String query) {
    setState(() {
      _isSearchingStudents = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students.where((student) {
          final name = student['name'].toString().toLowerCase();
          final admissionNo = student['admissionNo'].toString().toLowerCase();
          final className = student['className'].toString().toLowerCase();
          final guardianName = student['guardianName'].toString().toLowerCase();
          final teacherName = student['teacherName'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              admissionNo.contains(query.toLowerCase()) ||
              className.contains(query.toLowerCase()) ||
              guardianName.contains(query.toLowerCase()) ||
              teacherName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _fetchTeachers(String token) async {
    try {
      final result = await _apiService.getAllTeachersBySchool(
        token: token,
        schoolId: _currentUser.schoolId,
      );
      if (result['success'] && mounted) {
        final teachersData = result['data'] as List? ?? [];

        final Map<String, String> teacherClassMap = {};
        for (var classroom in _classrooms) {
          if (classroom['teacherId'] != null && classroom['teacherId'].toString().isNotEmpty) {
            teacherClassMap[classroom['teacherId'].toString()] = classroom['name'];
          }
        }

        setState(() {
          _teachers = teachersData.map((t) => ({
            'id': t['teacherId'],
            'name': '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.trim(),
            'email': t['email'] ?? '',
            'phone': t['phone'] ?? '',
            'className': teacherClassMap[t['teacherId']] ?? 'Not Assigned',
            'subjects': t['subjects']?.length ?? 0,
            'employmentDate': t['employmentDate'],
            'address': t['homeAddress'] ?? 'N/A',
          })).toList();
          _filteredTeachers = List.from(_teachers);
        });
      }
    } catch (e) {
      print('Error fetching teachers: $e');
    }
  }

  void _filterTeachers(String query) {
    setState(() {
      _isSearchingTeachers = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredTeachers = List.from(_teachers);
      } else {
        _filteredTeachers = _teachers.where((teacher) {
          final name = teacher['name'].toString().toLowerCase();
          final email = teacher['email'].toString().toLowerCase();
          final phone = teacher['phone'].toString().toLowerCase();
          final className = teacher['className'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              email.contains(query.toLowerCase()) ||
              phone.contains(query.toLowerCase()) ||
              className.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _fetchGuardians(String token) async {
    try {
      final result = await _apiService.getAllGuardiansBySchool(
        token: token,
        schoolId: _currentUser.schoolId,
      );
      if (result['success'] && mounted) {
        final guardiansData = result['data'] as List? ?? [];
        setState(() {
          _guardians = guardiansData.map((g) => ({
            'id': g['guardianId'],
            'name': '${g['firstname'] ?? ''} ${g['lastname'] ?? ''}'.trim(),
            'email': g['email'] ?? '',
            'phone': g['phone'] ?? '',
            'address': g['homeAddress'] ?? 'N/A',
          })).toList();
          _filteredGuardians = List.from(_guardians);
        });
      }
    } catch (e) {
      print('Error fetching guardians: $e');
    }
  }

  void _filterGuardians(String query) {
    setState(() {
      _isSearchingGuardians = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredGuardians = List.from(_guardians);
      } else {
        _filteredGuardians = _guardians.where((guardian) {
          final name = guardian['name'].toString().toLowerCase();
          final email = guardian['email'].toString().toLowerCase();
          final phone = guardian['phone'].toString().toLowerCase();
          final address = guardian['address'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              email.contains(query.toLowerCase()) ||
              phone.contains(query.toLowerCase()) ||
              address.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _filterClassrooms(String query) {
    setState(() {
      _isSearchingClassrooms = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredClassrooms = List.from(_classrooms);
      } else {
        _filteredClassrooms = _classrooms.where((classroom) {
          final name = classroom['name'].toString().toLowerCase();
          final teacherName = classroom['teacherName'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              teacherName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _fetchClassrooms(String token, Map<String, Map<String, dynamic>> expectedRevenueMap) async {
    try {
      print('📚 Fetching classrooms...');

      final result = await _apiService.getClassroomsBySchoolId(
        token: token,
        schoolId: _currentUser.schoolId,
      );

      if (result['success'] && mounted) {
        final classroomsData = result['data'] as List? ?? [];
        print('📚 Found ${classroomsData.length} classrooms');

        final List<Map<String, dynamic>> basicClassrooms = [];

        for (var c in classroomsData) {
          String teacherName = 'Not Assigned';
          String teacherId = '';

          // Get fee amount from the expected revenue map
          final classroomInfo = expectedRevenueMap[c['classroomId']];
          double feeAmount = classroomInfo?['classFee'] ?? 0.0;
          int studentCount = classroomInfo?['numberOfStudents'] ?? 0;

          print('   📚 ${c['name']}: Fee=₦$feeAmount, Students=$studentCount');

          try {
            final teacherResult = await _apiService.getTeacherByClass(
              token: token,
              classroomId: c['classroomId'],
            ).timeout(const Duration(seconds: 5));

            if (teacherResult['success'] && teacherResult['data'] != null) {
              final data = teacherResult['data'];
              teacherId = data['teacherId']?.toString() ?? '';
              final firstName = data['firstname'] ?? '';
              final lastName = data['lastname'] ?? '';
              teacherName = '$firstName $lastName'.trim();
              if (teacherName.isEmpty) teacherName = 'Not Assigned';
            }
          } catch (e) {
            print('Error getting teacher for ${c['name']}: $e');
          }

          basicClassrooms.add({
            'id': c['classroomId'],
            'name': c['name'] ?? 'Unknown',
            'capacity': (c['capacity'] ?? 0) as int,
            'teacherId': teacherId,
            'teacherName': teacherName,
            'feeAmount': feeAmount,
            'studentCount': studentCount,
          });
        }

        setState(() {
          _classrooms = basicClassrooms;
          _filteredClassrooms = List.from(basicClassrooms);
        });

        print('✅ Classrooms loaded: ${_classrooms.length}');
      } else {
        print('❌ Failed to fetch classrooms: ${result['message']}');
      }
    } catch (e) {
      print('❌ Error fetching classrooms: $e');
      setState(() {
        _classrooms = [];
        _filteredClassrooms = [];
      });
    }
  }

  Future<void> _fetchGuardianStudentsMappings(String token) async {
    Map<String, List<Map<String, dynamic>>> tempMap = {};
    for (var guardian in _guardians) {
      try {
        final result = await _apiService.getGuardianStudentsMapping(
          token: token,
          guardianId: guardian['id'],
        ).timeout(const Duration(seconds: 5));

        if (result['success'] && result['data'] != null) {
          tempMap[guardian['id']] = List<Map<String, dynamic>>.from(result['data']);
        } else {
          tempMap[guardian['id']] = [];
        }
      } catch (e) {
        tempMap[guardian['id']] = [];
      }
    }
    if (mounted) {
      setState(() {
        _guardianStudentsMap = tempMap;
      });
    }
  }

  Future<void> _fetchGuardianCount(String token) async {
    try {
      final result = await _apiService.getGuardianCountBySchool(
        token: token,
        schoolId: _currentUser.schoolId,
      );
      if (result['success'] && mounted) {
        setState(() {
          _guardianCount = result['data'] ?? 0;
        });
      }
    } catch (e) {
      print('Error fetching guardian count: $e');
    }
  }

  Future<void> _fetchGuardianTransactions(String token) async {
    try {
      final result = await _apiService.getGuardianTransactionsBySchool(
        token: token,
        schoolId: _currentUser.schoolId,
      );
      if (result['success'] && mounted) {
        final transactionsData = result['data'] as List? ?? [];
        setState(() {
          _guardianTransactions = transactionsData.map((t) => ({
            'id': t['transactionId'],
            'guardianId': t['guardianId'],
            'guardianName': t['guardianName'],
            'amount': t['amount'] ?? 0.0,
            'type': t['transactionType'] ?? 'payment',
            'status': t['status'] ?? 'completed',
            'date': t['transactionDate'],
            'reference': t['reference'],
          })).toList();
        });
      }
    } catch (e) {
      print('Error fetching guardian transactions: $e');
    }
  }

  Future<void> _fetchAllClassroomFinancialData(
      String token,
      Map<String, Map<String, dynamic>> expectedRevenueMap,
      String sessionId,
      String termId,
      ) async {
    if (_classrooms.isEmpty) {
      print('⚠️ No classrooms to fetch financial data for');
      return;
    }

    setState(() {
      _financialDataLoaded = false;
    });

    print('💰 Fetching financial data for ${_classrooms.length} classrooms...');
    print('📅 Using Session: $sessionId, Term: $termId');

    // Process each classroom
    for (var classroom in _classrooms) {
      await _fetchClassroomFinancialData(token, classroom, expectedRevenueMap, sessionId, termId);
    }

    if (mounted) {
      setState(() {
        _financialDataLoaded = true;
      });
      print('✅ All classroom financial data loaded');

      // Print summary
      double totalExpected = 0;
      double totalPaid = 0;
      double totalOwed = 0;
      for (var classroom in _classrooms) {
        final financialData = _classroomFinancialData[classroom['id']] ?? {};
        totalExpected += (financialData['expectedRevenue'] as double?) ?? 0;
        totalPaid += (financialData['totalPaid'] as double?) ?? 0;
        totalOwed += (financialData['totalOwed'] as double?) ?? 0;
      }
      print('📊 Financial Summary:');
      print('   Total Expected: ₦$totalExpected');
      print('   Total Paid: ₦$totalPaid');
      print('   Total Owed: ₦$totalOwed');
    }
  }

  Future<void> _fetchClassroomFinancialData(
      String token,
      Map<String, dynamic> classroom,
      Map<String, Map<String, dynamic>> expectedRevenueMap,
      String sessionId,
      String termId,
      ) async {
    final classroomId = classroom['id'];
    final classroomName = classroom['name'] ?? 'Unknown';

    // Get expected revenue from the pre-fetched data
    final expectedData = expectedRevenueMap[classroomId];
    final expectedRevenue = (expectedData?['expectedRevenue'] as double?) ?? 0.0;
    final feePerStudent = (expectedData?['classFee'] as double?) ?? 0.0;
    final studentCount = (expectedData?['numberOfStudents'] as int?) ?? 0;

    print('💰 Fetching financial data for $classroomName');
    print('   Session: $sessionId, Term: $termId');
    print('   Expected Revenue: ₦$expectedRevenue');
    print('   Fee per Student: ₦$feePerStudent');
    print('   Student Count: $studentCount');

    try {
      // Get total paid amount from API
      final paidResult = await _apiService.getTotalAmountPaidInClassByTerm(
        token: token,
        classroomId: classroomId,
        sessionId: sessionId,
        termId: termId,
      ).timeout(const Duration(seconds: 10));

      final totalPaid = (paidResult['data'] ?? 0.0).toDouble();
      print('   Total Paid from API: ₦$totalPaid');

      // Get total debt/owed amount from API
      final debtResult = await _apiService.getTotalDebtOwedInClassByTerm(
        token: token,
        classroomId: classroomId,
        sessionId: sessionId,
        termId: termId,
      ).timeout(const Duration(seconds: 10));

      final totalOwed = (debtResult['data'] ?? 0.0).toDouble();
      print('   Total Owed from API: ₦$totalOwed');

      // Get students owing list
      final studentsOwingResult = await _apiService.getStudentsOwingInClassByTerm(
        token: token,
        classroomId: classroomId,
        sessionId: sessionId,
        termId: termId,
      ).timeout(const Duration(seconds: 10));

      List<Map<String, dynamic>> studentsOwing = [];
      if (studentsOwingResult['success'] && studentsOwingResult['data'] != null) {
        final data = studentsOwingResult['data'];
        studentsOwing = List<Map<String, dynamic>>.from(data['students'] ?? []);
        print('   Students Owing: ${studentsOwing.length}');
      }

      // Calculate collection rate
      final collectionRate = expectedRevenue > 0 ? (totalPaid / expectedRevenue) * 100 : 0;

      print('   ✅ Final - Expected: ₦$expectedRevenue, Paid: ₦$totalPaid, Owed: ₦$totalOwed, Rate: ${collectionRate.toStringAsFixed(1)}%');

      if (mounted) {
        setState(() {
          _classroomFinancialData[classroomId] = {
            'studentCount': studentCount,
            'feePerStudent': feePerStudent,
            'expectedRevenue': expectedRevenue,
            'totalPaid': totalPaid,
            'totalOwed': totalOwed,
            'studentsOwing': studentsOwing,
            'collectionRate': collectionRate,
          };
        });
      }
    } catch (e) {
      print('❌ Error fetching financial data for $classroomName: $e');
      if (mounted) {
        setState(() {
          _classroomFinancialData[classroomId] = {
            'studentCount': studentCount,
            'feePerStudent': feePerStudent,
            'expectedRevenue': expectedRevenue,
            'totalPaid': 0.0,
            'totalOwed': 0.0,
            'studentsOwing': [],
            'collectionRate': 0.0,
          };
        });
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    await _fetchDashboardData();
    await _fetchUnreadMessages();
    setState(() {
      _isRefreshing = false;
    });
  }

  String _formatCurrency(double amount) {
    // Format with commas and 2 decimal places
    final formatter = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }


  // Also add a simpler version for whole numbers (no decimal places)
  String _formatCurrencySimple(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }


  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      DateTime dateTime = DateTime.parse(dateValue.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  // Navigation methods
  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MessagesScreen()),
    ).then((_) => _fetchUnreadMessages());
  }

  void _startConversationWithUser(String userId, String userRole, String userName, String? userEmail, String? userPhone) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          userId: userId,
          userRole: userRole,
          userName: userName,
          userEmail: userEmail,
          userPhone: userPhone,
        ),
      ),
    ).then((_) => _fetchUnreadMessages());
  }

  // Details Modals
  void _showStudentDetails(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    student['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard([
                      _buildInfoRow('Admission No', student['admissionNo']),
                      _buildInfoRow('Class', student['className']),
                      _buildInfoRow('Teacher', student['teacherName']),
                      _buildInfoRow('Guardian', student['guardianName']),
                      _buildInfoRow('Guardian Phone', student['guardianPhone']),
                      _buildInfoRow('Guardian Email', student['guardianEmail']),
                      _buildInfoRow('Gender', student['gender']),
                      _buildInfoRow('Date of Birth', _formatDate(student['dateOfBirth'])),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _startConversationWithUser(
                            student['guardianId'],
                            'Guardian',
                            student['guardianName'],
                            student['guardianEmail'],
                            student['guardianPhone'],
                          );
                        },
                        icon: const Icon(Icons.message),
                        label: const Text('Message Guardian'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTeacherDetails(Map<String, dynamic> teacher) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    teacher['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard([
                      _buildInfoRow('Email', teacher['email']),
                      _buildInfoRow('Phone', teacher['phone'], isClickable: true, onTap: () => _makePhoneCall(teacher['phone'])),
                      _buildInfoRow('Class', teacher['className']),
                      _buildInfoRow('Subjects', teacher['subjects'].toString()),
                      _buildInfoRow('Address', teacher['address']),
                    ]),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _startConversationWithUser(
                                teacher['id'],
                                'Teacher',
                                teacher['name'],
                                teacher['email'],
                                teacher['phone'],
                              );
                            },
                            icon: const Icon(Icons.message),
                            label: const Text('Message'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (teacher['phone'] != null && teacher['phone'].toString().isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _makePhoneCall(teacher['phone']),
                              icon: const Icon(Icons.phone),
                              label: const Text('Call'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGuardianDetails(Map<String, dynamic> guardian) {
    final guardianTransactions = _guardianTransactions
        .where((t) => t['guardianId'] == guardian['id'])
        .toList();

    final guardianStudents = _guardianStudentsMap[guardian['id']] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    guardian['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard([
                      _buildInfoRow('Email', guardian['email']),
                      _buildInfoRow('Phone', guardian['phone'], isClickable: true, onTap: () => _makePhoneCall(guardian['phone'])),
                      _buildInfoRow('Address', guardian['address']),
                      _buildInfoRow('Children', guardianStudents.length.toString()),
                    ]),
                    const SizedBox(height: 16),
                    if (guardianStudents.isNotEmpty) ...[
                      const Text(
                        'Children',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...guardianStudents.map((student) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 35,
                              height: 35,
                              decoration: BoxDecoration(
                                gradient: AppColors.cardGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  student['firstname']?[0]?.toUpperCase() ?? '?',
                                  style: const TextStyle(
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
                                    '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Admission: ${student['studentNo'] ?? 'N/A'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Transactions (${guardianTransactions.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    guardianTransactions.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No transactions found'),
                      ),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: guardianTransactions.length,
                      itemBuilder: (context, index) {
                        final transaction = guardianTransactions[index];
                        return _buildTransactionCard(transaction);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _startConversationWithUser(
                                guardian['id'],
                                'Guardian',
                                guardian['name'],
                                guardian['email'],
                                guardian['phone'],
                              );
                            },
                            icon: const Icon(Icons.message),
                            label: const Text('Message'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (guardian['phone'] != null && guardian['phone'].toString().isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _makePhoneCall(guardian['phone']),
                              icon: const Icon(Icons.phone),
                              label: const Text('Call'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isClickable = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isClickable ? onTap : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isClickable ? AppColors.primary : AppColors.textPrimary,
                  decoration: isClickable ? TextDecoration.underline : null,
                ),
              ),
            ),
            if (isClickable && value.isNotEmpty && value != 'N/A' && value != 'Not available')
              Icon(Icons.phone, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == 'N/A' || phoneNumber == 'Not available') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available'), backgroundColor: AppColors.warning),
      );
      return;
    }

    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanNumber.startsWith('0') && cleanNumber.length == 11) {
      cleanNumber = '+234${cleanNumber.substring(1)}';
    } else if (cleanNumber.startsWith('234') && cleanNumber.length == 13) {
      cleanNumber = '+$cleanNumber';
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

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: transaction['type'] == 'payment'
            ? AppColors.success.withOpacity(0.05)
            : AppColors.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: transaction['type'] == 'payment'
              ? AppColors.success.withOpacity(0.3)
              : AppColors.warning.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: transaction['type'] == 'payment'
                  ? AppColors.success.withOpacity(0.2)
                  : AppColors.warning.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              transaction['type'] == 'payment' ? Icons.payment : Icons.receipt,
              color: transaction['type'] == 'payment' ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction['type']?.toUpperCase() ?? 'TRANSACTION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: transaction['type'] == 'payment' ? AppColors.success : AppColors.warning,
                  ),
                ),
                Text(
                  'Ref: ${transaction['reference']?.substring(0, 8) ?? 'N/A'}...',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCurrencySimple(transaction['amount']),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: transaction['type'] == 'payment' ? AppColors.success : AppColors.warning,
                ),
              ),
              Text(
                _formatDate(transaction['date']),
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }


  void _showClassroomDetails(Map<String, dynamic> classroom) {
    final financialData = _classroomFinancialData[classroom['id']] ?? {};
    final studentsOwing = List<Map<String, dynamic>>.from(financialData['studentsOwing'] ?? []);
    final studentCount = financialData['studentCount'] ?? 0;
    final feeAmount = classroom['feeAmount'] ?? 0.0;
    final expectedRevenue = financialData['expectedRevenue'] ?? 0.0;
    final totalPaid = financialData['totalPaid'] ?? 0.0;
    final totalOwed = financialData['totalOwed'] ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    classroom['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard([
                      _buildInfoRow('Teacher', classroom['teacherName']),
                      _buildInfoRow('Total Students', studentCount.toString()),
                      _buildInfoRow('Fee per Student', _formatCurrency(feeAmount)),
                    ]),
                    const SizedBox(height: 16),
                    _buildFinancialSummaryCard(
                      expectedRevenue: expectedRevenue,
                      totalPaid: totalPaid,
                      totalOwed: totalOwed,
                      feeAmount: feeAmount,  // Pass feeAmount
                      studentCount: studentCount,  // Pass studentCount
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Students Owing (${studentsOwing.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    studentsOwing.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle, size: 48, color: AppColors.success),
                            SizedBox(height: 8),
                            Text('No students are owing!'),
                          ],
                        ),
                      ),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: studentsOwing.length,
                      itemBuilder: (context, index) {
                        final student = studentsOwing[index];
                        return _buildStudentOwingCard(student);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialSummaryCard({
    required double expectedRevenue,
    required double totalPaid,
    required double totalOwed,
    double feeAmount = 0.0,
    int studentCount = 0,
  }) {
    final collectionRate = expectedRevenue > 0 ? (totalPaid / expectedRevenue) * 100 : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Financial Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Expected',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrencySimple(expectedRevenue),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.info,
                        ),
                      ),
                      if (feeAmount > 0 && studentCount > 0)
                        Text(
                          '${_formatCurrencySimple(feeAmount)} × ${_formatNumberWithCommas(studentCount)} students',
                          style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Paid',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrencySimple(totalPaid),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Owed',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrencySimple(totalOwed),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Collection Rate', style: TextStyle(fontSize: 12)),
                  Text(
                    '${collectionRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: collectionRate >= 70 ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: collectionRate / 100,
                  backgroundColor: AppColors.greyLight,
                  color: collectionRate >= 70 ? AppColors.success : AppColors.warning,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentOwingCard(Map<String, dynamic> student) {
    final amountOwed = (student['balance']?.toDouble() ?? 0);
    final totalPaid = (student['totalPaid']?.toDouble() ?? 0);
    final classFee = (student['classFee']?.toDouble() ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                student['studentName'] != null && student['studentName'].isNotEmpty
                    ? student['studentName'][0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
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
                  student['studentName'] ?? 'Unknown Student',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Fee: ${_formatCurrencySimple(classFee)} • Paid: ${_formatCurrencySimple(totalPaid)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Owing',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatCurrencySimple(amountOwed),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isMobile = screenWidth < 600;
    _isTablet = screenWidth >= 600 && screenWidth < 1200;
    _isDesktop = screenWidth >= 1200;

    return Scaffold(
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: Row(
              children: [
                if (_isDesktop || _isTablet)
                  Container(
                    width: _isDesktop ? 280 : 250,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: _buildSideNavigation(),
                  ),
                Expanded(
                  child: _selectedIndex == 0
                      ? _buildHomeScreen()
                      : _buildScreenForIndex(_selectedIndex),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: (_isLoading || _errorMessage != null || _isDesktop || _isTablet)
          ? null
          : _buildBottomNavigationBar(),
    );
  }

  Widget _buildSideNavigation() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.dashboard_rounded, 'label': 'Overview', 'index': 0},
      {'icon': Icons.class_rounded, 'label': 'Classrooms', 'index': 1},
      {'icon': Icons.school_rounded, 'label': 'Students', 'index': 2},
      {'icon': Icons.person_rounded, 'label': 'Teachers', 'index': 3},
      {'icon': Icons.family_restroom_rounded, 'label': 'Guardians', 'index': 4},
      {'icon': Icons.message_rounded, 'label': 'Messages', 'index': 5},
      {'icon': Icons.settings_rounded, 'label': 'Settings', 'index': 6},
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.school, size: 30, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _currentUser.schoolName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _currentUser.schoolReg,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: navItems.length,
            itemBuilder: (context, index) {
              final item = navItems[index];
              final isSelected = _selectedIndex == item['index'];
              return ListTile(
                leading: Icon(
                  item['icon'],
                  color: isSelected ? AppColors.primary : AppColors.grey,
                  size: 24,
                ),
                title: Text(
                  item['label'],
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedTileColor: AppColors.primary.withOpacity(0.05),
                onTap: () => setState(() => _selectedIndex = item['index']),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: AppColors.error),
          title: const Text('Logout', style: TextStyle(color: AppColors.error)),
          onTap: _showLogoutDialog,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchDashboardData,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
            items: [
        const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
    const BottomNavigationBarItem(icon: Icon(Icons.class_rounded), label: 'Classrooms'),
    const BottomNavigationBarItem(icon: Icon(Icons.school_rounded), label: 'Students'),
    const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Teachers'),
    const BottomNavigationBarItem(icon: Icon(Icons.family_restroom_rounded), label: 'Guardians'),
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
    const BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
    ],
    ),
    );
  }
  Widget _buildHomeScreen() {
    int totalStudents = _students.length;
    int totalTeachers = _teachers.length;
    int totalGuardians = _guardianCount;
    int totalClassrooms = _classrooms.length;

    double totalExpected = 0;
    double totalPaid = 0;
    double totalOwed = 0;

    // Calculate totals from classroom financial data
    for (var classroom in _classrooms) {
      final financialData = _classroomFinancialData[classroom['id']] ?? {};
      final expected = (financialData['expectedRevenue'] as double?) ?? 0;
      final paid = (financialData['totalPaid'] as double?) ?? 0;
      final owed = (financialData['totalOwed'] as double?) ?? 0;

      totalExpected += expected;
      totalPaid += paid;
      totalOwed += owed;

      print('📊 ${classroom['name']}: Expected=₦$expected, Paid=₦$paid, Owed=₦$owed');
    }

    print('📊 Dashboard Totals:');
    print('   Total Expected: ₦$totalExpected');
    print('   Total Paid: ₦$totalPaid');
    print('   Total Owed: ₦$totalOwed');

    double collectionRate = totalExpected > 0 ? (totalPaid / totalExpected) * 100 : 0;

    int statsColumns = _isMobile ? 2 : (_isTablet ? 3 : 4);
    int classroomsColumns = _isMobile ? 1 : (_isTablet ? 2 : 3);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildSchoolInfoCard(),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: statsColumns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: 8,
            itemBuilder: (context, index) {
              final stats = [
                {'title': 'Total Students', 'value': totalStudents.toString(), 'icon': Icons.people, 'color': AppColors.primary},
                {'title': 'Total Teachers', 'value': totalTeachers.toString(), 'icon': Icons.person, 'color': AppColors.info},
                {'title': 'Total Guardians', 'value': totalGuardians.toString(), 'icon': Icons.family_restroom, 'color': AppColors.success},
                {'title': 'Total Classes', 'value': totalClassrooms.toString(), 'icon': Icons.class_, 'color': AppColors.warning},
                {'title': 'Expected Revenue', 'value': _formatCurrency(totalExpected), 'icon': Icons.attach_money, 'color': AppColors.info},
                {'title': 'Amount Paid', 'value': _formatCurrency(totalPaid), 'icon': Icons.payment, 'color': AppColors.success},
                {'title': 'Amount Owed', 'value': _formatCurrency(totalOwed), 'icon': Icons.warning, 'color': AppColors.error},
                {'title': 'Collection Rate', 'value': '${collectionRate.toStringAsFixed(1)}%', 'icon': Icons.trending_up, 'color': AppColors.primary},
              ];
              final stat = stats[index];
              return _buildStatCard(stat['title'] as String, stat['value'] as String, stat['icon'] as IconData, stat['color'] as Color);
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Classrooms Overview',
                style: TextStyle(
                  fontSize: _isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (_classrooms.length > classroomsColumns)
                TextButton(
                  onPressed: () => setState(() => _selectedIndex = 1),
                  child: const Text('View All'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _classrooms.isEmpty
              ? Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.class_rounded, size: 48, color: AppColors.grey),
                const SizedBox(height: 12),
                Text(
                  'No classrooms added yet',
                  style: TextStyle(
                    fontSize: _isMobile ? 14 : 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Classrooms will appear here once added',
                  style: TextStyle(
                    fontSize: _isMobile ? 12 : 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
              : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: classroomsColumns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: _isMobile ? 1.2 : 1.3,
            ),
            itemCount: _classrooms.length > 3 ? 3 : _classrooms.length,
            itemBuilder: (context, index) {
              final classroom = _classrooms[index];
              final financialData = _classroomFinancialData[classroom['id']] ?? {};

              final expectedRevenue = (financialData['expectedRevenue'] ?? 0.0).toDouble();
              final totalPaid = (financialData['totalPaid'] ?? 0.0).toDouble();
              final totalOwed = (financialData['totalOwed'] ?? 0.0).toDouble();

              return _buildClassroomCard(classroom, expectedRevenue, totalPaid, totalOwed);
            },
          ),
        ],
      ),
    );
  }


  Widget _buildSchoolInfoCard() {
    final sessionId = _getCurrentSessionId();
    final termId = _currentUser.termId ?? '1';

    return Container(
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentUser.schoolName,
                      style: TextStyle(
                        fontSize: _isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Reg: ${_currentUser.schoolReg}',
                      style: TextStyle(
                        fontSize: _isMobile ? 11 : 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        termId,
                        style: TextStyle(
                          fontSize: _isMobile ? 11 : 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text('Term', style: TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        sessionId,
                        style: TextStyle(
                          fontSize: _isMobile ? 11 : 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text('Session', style: TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: TextStyle(color: AppColors.textSecondary, fontSize: _isMobile ? 12 : 14),
              ),
              const SizedBox(height: 4),
              Text(
                _currentUser.name.split(' ').first,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: _isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'School Administrator',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: _isMobile ? 11 : 12,
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            Container(
              width: _isMobile ? 45 : 55,
              height: _isMobile ? 45 : 55,
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.message, size: _isMobile ? 24 : 30, color: Colors.white),
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    // For currency values, format them nicely
    String displayValue = value;
    if (title.contains('Revenue') || title.contains('Paid') || title.contains('Owed')) {
      // If it's a currency value and starts with ₦, re-format it
      if (value.startsWith('₦')) {
        try {
          final numValue = double.parse(value.replaceAll('₦', '').replaceAll(',', ''));
          displayValue = _formatCurrencySimple(numValue);
        } catch (e) {
          displayValue = value;
        }
      }
    }

    return Container(
      padding: EdgeInsets.all(_isMobile ? 10 : 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: _isMobile ? 22 : 26, color: color),
          const SizedBox(height: 4),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: _isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: _isMobile ? 10 : 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildClassroomCard(Map<String, dynamic> classroom, double expectedRevenue, double totalPaid, double totalOwed) {
    final collectionRate = expectedRevenue > 0 ? (totalPaid / expectedRevenue) * 100 : 0;
    final studentCount = _classroomFinancialData[classroom['id']]?['studentCount'] ?? 0;
    final feeAmount = classroom['feeAmount'] ?? 0.0;

    return Container(
      padding: EdgeInsets.all(_isMobile ? 12 : 14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.class_, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      classroom['name'],
                      style: TextStyle(
                        fontSize: _isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Teacher: ${classroom['teacherName']}',
                      style: TextStyle(
                        fontSize: _isMobile ? 10 : 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_formatNumberWithCommas(studentCount)} Students × ${_formatCurrencySimple(feeAmount)}',
                      style: TextStyle(
                        fontSize: _isMobile ? 9 : 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: collectionRate >= 70
                      ? AppColors.success.withOpacity(0.1)
                      : (collectionRate >= 40
                      ? AppColors.warning.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${collectionRate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: collectionRate >= 70
                        ? AppColors.success
                        : (collectionRate >= 40
                        ? AppColors.warning
                        : AppColors.error),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildClassroomChip('Expected', _formatCurrencySimple(expectedRevenue), Icons.trending_up, color: AppColors.info),
              _buildClassroomChip('Paid', _formatCurrencySimple(totalPaid), Icons.payment, color: AppColors.success),
              _buildClassroomChip('Owed', _formatCurrencySimple(totalOwed), Icons.warning, color: AppColors.error),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showClassroomDetails(classroom),
              icon: Icon(Icons.visibility, size: _isMobile ? 16 : 18),
              label: const Text('View Details'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: EdgeInsets.symmetric(vertical: _isMobile ? 8 : 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

// Helper method to format numbers with commas
  String _formatNumberWithCommas(int number) {
    final formatter = NumberFormat('#,###', 'en_US');
    return formatter.format(number);
  }

  Widget _buildClassroomChip(String label, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.primary),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
  // ==================== STUDENTS SCREEN ====================

  Widget _buildStudentsScreen() {
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_rounded, size: 64, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text('No students found'),
            const SizedBox(height: 8),
            Text(
              'Students will appear here once added',
              style: TextStyle(fontSize: _isMobile ? 12 : 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          color: AppColors.white,
          child: TextField(
            controller: _studentSearchController,
            onChanged: _filterStudents,
            decoration: InputDecoration(
              hintText: 'Search by name, admission, class, guardian, or teacher...',
              hintStyle: TextStyle(fontSize: _isMobile ? 13 : 14, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: _isMobile ? 20 : 22),
              suffixIcon: _studentSearchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _isMobile ? 18 : 20),
                onPressed: () {
                  _studentSearchController.clear();
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
                vertical: _isMobile ? 10 : 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
        if (_isSearchingStudents)
          Container(
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredStudents.length} student${_filteredStudents.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: _isMobile ? 12 : 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearchingStudents && _filteredStudents.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No students found',
                    style: TextStyle(
                      fontSize: _isMobile ? 14 : 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(_isMobile ? 12 : 16),
              itemCount: _isSearchingStudents ? _filteredStudents.length : _students.length,
              itemBuilder: (context, index) {
                final student = _isSearchingStudents ? _filteredStudents[index] : _students[index];
                return _buildStudentCard(student);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_isMobile ? 12 : 14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Row(
        children: [
          Container(
            width: _isMobile ? 45 : 50,
            height: _isMobile ? 45 : 50,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                student['name'].isNotEmpty ? student['name'][0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: _isMobile ? 18 : 20,
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
                  student['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: _isMobile ? 14 : 16,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Admission: ${student['admissionNo']}',
                  style: TextStyle(
                    fontSize: _isMobile ? 10 : 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.class_, size: _isMobile ? 12 : 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        student['className'],
                        style: TextStyle(
                          fontSize: _isMobile ? 10 : 11,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.person, size: _isMobile ? 12 : 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Guardian: ${student['guardianName']}',
                        style: TextStyle(
                          fontSize: _isMobile ? 10 : 11,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _startConversationWithUser(
                  student['guardianId'],
                  'Guardian',
                  student['guardianName'],
                  student['guardianEmail'],
                  student['guardianPhone'],
                ),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _showStudentDetails(student),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TEACHERS SCREEN ====================

  Widget _buildTeachersScreen() {
    if (_teachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text('No teachers found'),
            const SizedBox(height: 8),
            Text(
              'Teachers will appear here once added',
              style: TextStyle(fontSize: _isMobile ? 12 : 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          color: AppColors.white,
          child: TextField(
            controller: _teacherSearchController,
            onChanged: _filterTeachers,
            decoration: InputDecoration(
              hintText: 'Search by name, email, phone, or class...',
              hintStyle: TextStyle(fontSize: _isMobile ? 13 : 14, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: _isMobile ? 20 : 22),
              suffixIcon: _teacherSearchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _isMobile ? 18 : 20),
                onPressed: () {
                  _teacherSearchController.clear();
                  _filterTeachers('');
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
                vertical: _isMobile ? 10 : 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
        if (_isSearchingTeachers)
          Container(
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredTeachers.length} teacher${_filteredTeachers.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: _isMobile ? 12 : 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearchingTeachers && _filteredTeachers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No teachers found',
                    style: TextStyle(
                      fontSize: _isMobile ? 14 : 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(_isMobile ? 12 : 16),
              itemCount: _isSearchingTeachers ? _filteredTeachers.length : _teachers.length,
              itemBuilder: (context, index) {
                final teacher = _isSearchingTeachers ? _filteredTeachers[index] : _teachers[index];
                return _buildTeacherCard(teacher);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> teacher) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher['name'],
                  style: TextStyle(
                    fontSize: _isMobile ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  teacher['email'],
                  style: TextStyle(
                    fontSize: _isMobile ? 11 : 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.class_, size: _isMobile ? 14 : 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        teacher['className'],
                        style: TextStyle(
                          fontSize: _isMobile ? 12 : 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _showTeacherDetails(teacher),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _showTeacherDetails(teacher),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== GUARDIANS SCREEN ====================

  Widget _buildGuardiansScreen() {
    if (_guardians.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.family_restroom, size: 64, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text('No guardians found'),
            const SizedBox(height: 8),
            Text(
              'Guardians will appear here once added',
              style: TextStyle(fontSize: _isMobile ? 12 : 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          color: AppColors.white,
          child: TextField(
            controller: _guardianSearchController,
            onChanged: _filterGuardians,
            decoration: InputDecoration(
              hintText: 'Search by name, email, phone, or address...',
              hintStyle: TextStyle(fontSize: _isMobile ? 13 : 14, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: _isMobile ? 20 : 22),
              suffixIcon: _guardianSearchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _isMobile ? 18 : 20),
                onPressed: () {
                  _guardianSearchController.clear();
                  _filterGuardians('');
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
                vertical: _isMobile ? 10 : 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
        if (_isSearchingGuardians)
          Container(
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredGuardians.length} guardian${_filteredGuardians.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: _isMobile ? 12 : 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearchingGuardians && _filteredGuardians.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No guardians found',
                    style: TextStyle(
                      fontSize: _isMobile ? 14 : 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(_isMobile ? 12 : 16),
              itemCount: _isSearchingGuardians ? _filteredGuardians.length : _guardians.length,
              itemBuilder: (context, index) {
                final guardian = _isSearchingGuardians ? _filteredGuardians[index] : _guardians[index];
                return _buildGuardianCard(guardian);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuardianCard(Map<String, dynamic> guardian) {
    final guardianStudents = _guardianStudentsMap[guardian['id']] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guardian['name'],
                  style: TextStyle(
                    fontSize: _isMobile ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  guardian['email'],
                  style: TextStyle(
                    fontSize: _isMobile ? 11 : 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${guardianStudents.length} Child${guardianStudents.length != 1 ? 'ren' : ''}',
                  style: TextStyle(
                    fontSize: _isMobile ? 11 : 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _showGuardianDetails(guardian),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: AppColors.primary, size: _isMobile ? 20 : 22),
                onPressed: () => _showGuardianDetails(guardian),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== CLASSROOMS SCREEN ====================

  Widget _buildClassroomsScreen() {
    if (_classrooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_rounded, size: 64, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text('No classrooms found'),
            const SizedBox(height: 8),
            Text(
              'Classrooms will appear here once added',
              style: TextStyle(fontSize: _isMobile ? 12 : 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    int classroomsColumns = _isMobile ? 1 : (_isTablet ? 2 : 3);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          color: AppColors.white,
          child: TextField(
            controller: _classroomSearchController,
            onChanged: _filterClassrooms,
            decoration: InputDecoration(
              hintText: 'Search by class name or teacher name...',
              hintStyle: TextStyle(fontSize: _isMobile ? 13 : 14, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: _isMobile ? 20 : 22),
              suffixIcon: _classroomSearchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _isMobile ? 18 : 20),
                onPressed: () {
                  _classroomSearchController.clear();
                  _filterClassrooms('');
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
                vertical: _isMobile ? 10 : 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
        if (_isSearchingClassrooms)
          Container(
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredClassrooms.length} classroom${_filteredClassrooms.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: _isMobile ? 12 : 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearchingClassrooms && _filteredClassrooms.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No classrooms found',
                    style: TextStyle(
                      fontSize: _isMobile ? 14 : 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(_isMobile ? 12 : 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: classroomsColumns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: _isMobile ? 1.2 : 1.3,
                ),
                itemCount: _isSearchingClassrooms ? _filteredClassrooms.length : _classrooms.length,
                itemBuilder: (context, index) {
                  final classroom = _isSearchingClassrooms ? _filteredClassrooms[index] : _classrooms[index];
                  final financialData = _classroomFinancialData[classroom['id']] ?? {};
                  final expectedRevenue = (financialData['expectedRevenue'] ?? 0.0).toDouble();
                  final totalPaid = (financialData['totalPaid'] ?? 0.0).toDouble();
                  final totalOwed = (financialData['totalOwed'] ?? 0.0).toDouble();
                  return _buildClassroomCard(classroom, expectedRevenue, totalPaid, totalOwed);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== MESSAGES SCREEN ====================

  Widget _buildMessagesScreen() {
    return const MessagesScreen();
  }

  // ==================== SETTINGS SCREEN ====================

  Widget _buildSettingsScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: _isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSettingsTile(Icons.person, 'Profile', 'View and edit your profile'),
                _buildSettingsTile(Icons.school, 'School Settings', 'Manage school information'),
                _buildSettingsTile(Icons.attach_money, 'Fee Structure', 'Set fees for each class'),
                _buildSettingsTile(Icons.calendar_today, 'Terms & Sessions', 'Manage academic terms'),
                _buildSettingsTile(Icons.logout, 'Logout', 'Sign out of your account', isDestructive: true, onTap: _showLogoutDialog),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle, {bool isDestructive = false, VoidCallback? onTap}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary),
          title: Text(title, style: TextStyle(color: isDestructive ? AppColors.error : AppColors.textPrimary)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap ?? _showComingSoon,
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 1:
        return _buildClassroomsScreen();
      case 2:
        return _buildStudentsScreen();
      case 3:
        return _buildTeachersScreen();
      case 4:
        return _buildGuardiansScreen();
      case 5:
        return _buildMessagesScreen();
      case 6:
        return _buildSettingsScreen();
      default:
        return _buildHomeScreen();
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feature coming soon!'), backgroundColor: AppColors.info),
    );
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
}