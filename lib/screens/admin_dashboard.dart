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

// ─── Constants ───────────────────────────────────────────────────────────────

const kOrange = Color(0xFFF7941D);
const kNavy = Color(0xFF1A2340);
const kLightOrange = Color(0xFFFFF3E8);
const kBlue = Color(0xFF4A90D9);
const kLightBlue = Color(0xFFEBF3FB);
const kGreen = Color(0xFF27AE60);
const kLightGreen = Color(0xFFE8F8EF);
const kPurple = Color(0xFF7B61FF);
const kLightPurple = Color(0xFFF0EEFF);
const kRed = Color(0xFFE74C3C);
const kBg = Color(0xFFF7F8FA);
const kBorder = Color(0xFFEEEEEE);
const kTextGrey = Color(0xFF888888);

// ─── Dashboard Screen ────────────────────────────────────────────────────────

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  // ==================== DATA STATES ====================
  late UserModel _currentUser;
  late ApiService _apiService;

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

  // ==================== DATA FETCHING METHODS ====================

  String _getCurrentSessionId() {
    String sessionId = _currentUser.sessionId ?? '';
    if (sessionId.isEmpty) {
      final now = DateTime.now();
      final year = now.year;
      final nextYear = year + 1;
      sessionId = '$year/$nextYear';
      print('⚠️ Using default session ID: $sessionId');
    }
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
      final sessionId = _getCurrentSessionId();
      final termId = _currentUser.termId ?? '1';

      print('📊 Fetching dashboard data...');
      print('📅 Session ID: $sessionId');
      print('📚 Term ID: $termId');

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
        }
        print('💰 Total Expected Revenue: ₦$totalExpectedRevenue');
      } else {
        print('❌ Failed to fetch expected revenue: ${expectedRevenueResult['message']}');
      }

      await _fetchClassrooms(token, expectedRevenueMap);

      await Future.wait([
        _fetchStudents(token),
        _fetchTeachers(token),
        _fetchGuardians(token),
        _fetchGuardianCount(token),
        _fetchGuardianTransactions(token),
      ]);

      await _fetchAllClassroomFinancialData(token, expectedRevenueMap, sessionId, termId);

      setState(() {
        _filteredStudents = List.from(_students);
        _filteredTeachers = List.from(_teachers);
        _filteredGuardians = List.from(_guardians);
        _filteredClassrooms = List.from(_classrooms);
        _isLoading = false;
      });

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

    for (var classroom in _classrooms) {
      await _fetchClassroomFinancialData(token, classroom, expectedRevenueMap, sessionId, termId);
    }

    if (mounted) {
      setState(() {
        _financialDataLoaded = true;
      });
      print('✅ All classroom financial data loaded');

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
      final paidResult = await _apiService.getTotalAmountPaidInClassByTerm(
        token: token,
        classroomId: classroomId,
        sessionId: sessionId,
        termId: termId,
      ).timeout(const Duration(seconds: 10));

      final totalPaid = (paidResult['data'] ?? 0.0).toDouble();
      print('   Total Paid from API: ₦$totalPaid');

      final debtResult = await _apiService.getTotalDebtOwedInClassByTerm(
        token: token,
        classroomId: classroomId,
        sessionId: sessionId,
        termId: termId,
      ).timeout(const Duration(seconds: 10));

      final totalOwed = (debtResult['data'] ?? 0.0).toDouble();
      print('   Total Owed from API: ₦$totalOwed');

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

  // ==================== HELPER METHODS ====================

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String _formatCurrencySimple(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  String _formatNumberWithCommas(int number) {
    final formatter = NumberFormat('#,###', 'en_US');
    return formatter.format(number);
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

  // ==================== NAVIGATION METHODS ====================

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

  // ==================== DETAILS MODALS ====================

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
                      color: kOrange,
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
                          backgroundColor: kOrange,
                          foregroundColor: Colors.white,
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
                      color: kOrange,
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
                            style: ElevatedButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
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
                      color: kOrange,
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
                          color: kOrange.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kOrange.withOpacity(0.2)),
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
                            style: ElevatedButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
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
                      color: kOrange,
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
                      feeAmount: feeAmount,
                      studentCount: studentCount,
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
                  color: isClickable ? kOrange : AppColors.textPrimary,
                  decoration: isClickable ? TextDecoration.underline : null,
                ),
              ),
            ),
            if (isClickable && value.isNotEmpty && value != 'N/A' && value != 'Not available')
              Icon(Icons.phone, size: 16, color: kOrange),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kLightOrange,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOrange.withOpacity(0.2)),
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
        color: kLightOrange,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOrange.withOpacity(0.2)),
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
                    border: Border.all(color: AppColors.info.withOpacity(0.2)),
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
                    border: Border.all(color: AppColors.success.withOpacity(0.2)),
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
                    border: Border.all(color: AppColors.error.withOpacity(0.2)),
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

  // ==================== UI BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isMobile = screenWidth < 600;
    _isTablet = screenWidth >= 600 && screenWidth < 1200;
    _isDesktop = screenWidth >= 1200;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kOrange))
            : _errorMessage != null
            ? _buildErrorView()
            : RefreshIndicator(
          onRefresh: _refreshData,
          color: kOrange,
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _selectedIndex == 0
                    ? _buildHomeScreen()
                    : _buildScreenWithBackButton(_selectedIndex),
              ),
            ],
          ),
        ),
      ),
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
            style: ElevatedButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    // Show back button if not on home screen
    final bool showBackButton = _selectedIndex != 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back Button (if not on home)
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: kOrange),
              onPressed: () => setState(() => _selectedIndex = 0),
              tooltip: 'Back to Dashboard',
            ),

          // Menu (only on home)
          if (!showBackButton)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder),
              ),
              child: const Icon(Icons.menu, color: kNavy, size: 20),
            ),

          const Spacer(),

          // Logo
          Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.school, color: kNavy, size: 20),
                  const SizedBox(width: 4),
                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Edu',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: kNavy,
                          ),
                        ),
                        TextSpan(
                          text: 'Cat',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: kOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Text(
                'Empowering Schools, Transforming Lives',
                style: TextStyle(fontSize: 9, color: kTextGrey),
              ),
            ],
          ),

          const Spacer(),

          // Screen Title (when back button is shown)
          if (showBackButton)
            Text(
              _getScreenTitle(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kNavy,
              ),
            ),

          if (!showBackButton)
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: kNavy, size: 20),
                    onPressed: _navigateToMessages,
                    padding: EdgeInsets.zero,
                  ),
                ),
                if (_unreadMessageCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: kRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),

          if (!showBackButton) const SizedBox(width: 10),

          // Avatar (only on home)
          if (!showBackButton)
            CircleAvatar(
              radius: 20,
              backgroundColor: kLightOrange,
              child: Icon(Icons.person, color: kOrange, size: 22),
            ),

          // Logout button (only when back button is shown)
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              onPressed: _showLogoutDialog,
            ),
        ],
      ),
    );
  }

  String _getScreenTitle() {
    switch (_selectedIndex) {
      case 1: return 'Classrooms';
      case 2: return 'Students';
      case 3: return 'Teachers';
      case 4: return 'Guardians';
      case 5: return 'Messages';
      case 6: return 'Settings';
      default: return '';
    }
  }

  Widget _buildScreenWithBackButton(int index) {
    // Wrap each screen with a back button handler
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe right to go back
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: _buildScreenForIndex(index),
    );
  }

  // ── Greeting Banner ────────────────────────────────────────────────────────

  Widget _buildGreetingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7941D), Color(0xFFFFB347)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            bottom: -10,
            child: Opacity(
              opacity: 0.2,
              child: Icon(
                Icons.account_balance,
                size: 140,
                color: Colors.white,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Hello, ${_currentUser.name.split(' ').first}!',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(' 👋', style: TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'School Administrator!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Here's what's happening at ${_currentUser.schoolName} today.",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _getCurrentSessionId(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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

  // ── Section Header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, String? actionLabel) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: kNavy,
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: actionLabel == 'View All' ? () => setState(() => _selectedIndex = 1) : null,
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: kPurple,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }

  // ── Stats Grid ─────────────────────────────────────────────────────────────

  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.group,
                iconColor: kOrange,
                iconBg: kLightOrange,
                count: _students.length.toString(),
                label: 'Students',
                subLabel: 'Across all classes',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.person,
                iconColor: kBlue,
                iconBg: kLightBlue,
                count: _teachers.length.toString(),
                label: 'Teachers',
                subLabel: 'Teaching your children',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.people_alt,
                iconColor: kGreen,
                iconBg: kLightGreen,
                count: _guardianCount.toString(),
                label: 'Guardians',
                subLabel: 'Linked to your children',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.menu_book,
                iconColor: kPurple,
                iconBg: kLightPurple,
                count: _classrooms.length.toString(),
                label: 'Classrooms',
                subLabel: 'Your children are in',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String count,
    required String label,
    required String subLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kNavy,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kNavy,
                  ),
                ),
                Text(
                  subLabel,
                  style: const TextStyle(fontSize: 11, color: kTextGrey),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: kTextGrey, size: 18),
        ],
      ),
    );
  }

  // ── Financial Overview ─────────────────────────────────────────────────────

  Widget _buildFinancialOverview() {
    double totalExpected = 0;
    double totalPaid = 0;
    double totalOwed = 0;

    for (var classroom in _classrooms) {
      final financialData = _classroomFinancialData[classroom['id']] ?? {};
      totalExpected += (financialData['expectedRevenue'] as double?) ?? 0;
      totalPaid += (financialData['totalPaid'] as double?) ?? 0;
      totalOwed += (financialData['totalOwed'] as double?) ?? 0;
    }

    double collectionRate = totalExpected > 0 ? (totalPaid / totalExpected) * 100 : 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kLightOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wallet, color: kOrange, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Financial Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kNavy,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: kOrange),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${collectionRate.toStringAsFixed(0)}% Collection',
                  style: TextStyle(
                    color: kOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildFinanceCard(
                  label: 'Expected',
                  amount: _formatCurrencySimple(totalExpected),
                  amountColor: kBlue,
                  icon: Icons.pie_chart_outline,
                  iconColor: kBlue,
                  bgColor: kLightBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFinanceCard(
                  label: 'Paid',
                  amount: _formatCurrencySimple(totalPaid),
                  amountColor: kGreen,
                  icon: Icons.check_circle_outline,
                  iconColor: kGreen,
                  bgColor: kLightGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFinanceCard(
                  label: 'Owed',
                  amount: _formatCurrencySimple(totalOwed),
                  amountColor: kRed,
                  icon: Icons.error_outline,
                  iconColor: kRed,
                  bgColor: const Color(0xFFFDEDEB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Outstanding Balance: ${_formatCurrencySimple(totalOwed)}',
                style: const TextStyle(fontSize: 12, color: kTextGrey),
              ),
              Text(
                '${collectionRate.toStringAsFixed(0)}% Paid',
                style: TextStyle(
                  fontSize: 12,
                  color: collectionRate >= 70 ? kGreen : kOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceCard({
    required String label,
    required String amount,
    required Color amountColor,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: kTextGrey),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
          const SizedBox(height: 8),
          Icon(icon, color: iconColor, size: 20),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.people, 'label': 'Students', 'color': kOrange, 'bg': kLightOrange, 'index': 2},
      {'icon': Icons.person, 'label': 'Teachers', 'color': kBlue, 'bg': kLightBlue, 'index': 3},
      {'icon': Icons.class_, 'label': 'Classes', 'color': kPurple, 'bg': kLightPurple, 'index': 1},
      {'icon': Icons.family_restroom, 'label': 'Guardians', 'color': kGreen, 'bg': kLightGreen, 'index': 4},
      {'icon': Icons.message, 'label': 'Messages', 'color': kOrange, 'bg': kLightOrange, 'index': 5},
      {'icon': Icons.settings, 'label': 'Settings', 'color': kNavy, 'bg': kLightOrange, 'index': 6},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((action) {
        return GestureDetector(
          onTap: () {
            final index = action['index'] as int;
            if (index == 5) {
              _navigateToMessages();
            } else {
              setState(() {
                _selectedIndex = index;
              });
            }
          },
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: (action['bg'] as Color),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (action['color'] as Color).withOpacity(0.2), width: 1),
                ),
                child: Icon(
                  action['icon'] as IconData,
                  color: action['color'] as Color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 70,
                child: Text(
                  action['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kNavy,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Classroom List ─────────────────────────────────────────────────────────

  Widget _buildClassroomList() {
    if (_classrooms.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: const Center(
          child: Text(
            'No classrooms available',
            style: TextStyle(color: kTextGrey),
          ),
        ),
      );
    }

    return Column(
      children: _classrooms.map((classroom) {
        final financialData = _classroomFinancialData[classroom['id']] ?? {};
        final expectedRevenue = (financialData['expectedRevenue'] ?? 0.0).toDouble();
        final totalPaid = (financialData['totalPaid'] ?? 0.0).toDouble();
        final totalOwed = (financialData['totalOwed'] ?? 0.0).toDouble();
        final studentCount = financialData['studentCount'] ?? 0;
        final collectionRate = expectedRevenue > 0 ? (totalPaid / expectedRevenue) * 100 : 0;

        return _buildClassroomItem(
          color: kOrange,
          className: classroom['name'],
          students: '$studentCount student${studentCount != 1 ? 's' : ''}',
          paid: _formatCurrencySimple(totalPaid),
          owed: _formatCurrencySimple(totalOwed),
          percent: '${collectionRate.toStringAsFixed(0)}%',
          onTap: () => _showClassroomDetails(classroom),
        );
      }).toList(),
    );
  }

  Widget _buildClassroomItem({
    required Color color,
    required String className,
    required String students,
    required String paid,
    required String owed,
    required String percent,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    className,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kNavy,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 12, color: kTextGrey),
                      const SizedBox(width: 3),
                      Text(
                        students,
                        style: const TextStyle(fontSize: 12, color: kTextGrey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Paid: $paid',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Owed: $owed',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: kOrange, width: 1.5),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  percent,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: kTextGrey, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Bottom Nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    final items = [
      _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0),
      _NavItem(icon: Icons.class_rounded, label: 'Classes', index: 1),
      _NavItem(icon: Icons.people_alt_outlined, label: 'Students', index: 2),
      _NavItem(icon: Icons.person_rounded, label: 'Teachers', index: 3),
      _NavItem(icon: Icons.family_restroom_rounded, label: 'Guardians', index: 4),
      _NavItem(icon: Icons.message_rounded, label: 'Messages', index: 5, isMessages: true),
      _NavItem(icon: Icons.settings_rounded, label: 'Settings', index: 6),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = _selectedIndex == item.index;
              return GestureDetector(
                onTap: () {
                  if (item.isMessages == true) {
                    _navigateToMessages();
                  } else {
                    setState(() {
                      _selectedIndex = item.index;
                    });
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 50,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: selected ? kOrange : kTextGrey,
                        size: 24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? kOrange : kTextGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ==================== SCREEN BUILDERS ====================

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(_isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGreetingBanner(),
          const SizedBox(height: 24),
          _buildSectionHeader('At a Glance', 'View All'),
          const SizedBox(height: 14),
          _buildStatsGrid(),
          const SizedBox(height: 24),
          _buildFinancialOverview(),
          const SizedBox(height: 24),
          _buildSectionHeader('Quick Actions', null),
          const SizedBox(height: 16),
          _buildQuickActions(),
          const SizedBox(height: 24),
          _buildSectionHeader('Classrooms', 'View All'),
          const SizedBox(height: 14),
          _buildClassroomList(),
          const SizedBox(height: 24),
        ],
      ),
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

  Widget _buildClassroomsScreen() {
    if (_classrooms.isEmpty) {
      return _buildEmptyScreen('No classrooms found', 'Classrooms will appear here once added', Icons.class_rounded);
    }

    int classroomsColumns = _isMobile ? 1 : (_isTablet ? 2 : 3);

    return Column(
      children: [
        _buildSearchBar(
          controller: _classroomSearchController,
          onChanged: _filterClassrooms,
          hint: 'Search by class name or teacher name...',
          isSearching: _isSearchingClassrooms,
          count: _filteredClassrooms.length,
          label: 'classroom',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: kOrange,
            child: _isSearchingClassrooms && _filteredClassrooms.isEmpty
                ? _buildEmptySearchResults()
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
                  return _buildClassroomItem(
                    color: kOrange,
                    className: classroom['name'],
                    students: '${classroom['studentCount'] ?? 0} students',
                    paid: _formatCurrencySimple(totalPaid),
                    owed: _formatCurrencySimple(totalOwed),
                    percent: '${financialData['collectionRate']?.toStringAsFixed(0) ?? 0}%',
                    onTap: () => _showClassroomDetails(classroom),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentsScreen() {
    if (_students.isEmpty) {
      return _buildEmptyScreen('No students found', 'Students will appear here once added', Icons.school_rounded);
    }

    return Column(
      children: [
        _buildSearchBar(
          controller: _studentSearchController,
          onChanged: _filterStudents,
          hint: 'Search by name, admission, class, guardian, or teacher...',
          isSearching: _isSearchingStudents,
          count: _filteredStudents.length,
          label: 'student',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: kOrange,
            child: _isSearchingStudents && _filteredStudents.isEmpty
                ? _buildEmptySearchResults()
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOrange.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    color: kNavy,
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
                    Icon(Icons.class_, size: _isMobile ? 12 : 14, color: kOrange),
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
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _startConversationWithUser(
                  student['guardianId'],
                  'Guardian',
                  student['guardianName'],
                  student['guardianEmail'],
                  student['guardianPhone'],
                ),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _showStudentDetails(student),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeachersScreen() {
    if (_teachers.isEmpty) {
      return _buildEmptyScreen('No teachers found', 'Teachers will appear here once added', Icons.person_off);
    }

    return Column(
      children: [
        _buildSearchBar(
          controller: _teacherSearchController,
          onChanged: _filterTeachers,
          hint: 'Search by name, email, phone, or class...',
          isSearching: _isSearchingTeachers,
          count: _filteredTeachers.length,
          label: 'teacher',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: kOrange,
            child: _isSearchingTeachers && _filteredTeachers.isEmpty
                ? _buildEmptySearchResults()
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOrange.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    color: kNavy,
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
                    Icon(Icons.class_, size: _isMobile ? 14 : 16, color: kOrange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        teacher['className'],
                        style: TextStyle(
                          fontSize: _isMobile ? 12 : 13,
                          fontWeight: FontWeight.w500,
                          color: kNavy,
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
                icon: Icon(Icons.message, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _showTeacherDetails(teacher),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _showTeacherDetails(teacher),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuardiansScreen() {
    if (_guardians.isEmpty) {
      return _buildEmptyScreen('No guardians found', 'Guardians will appear here once added', Icons.family_restroom);
    }

    return Column(
      children: [
        _buildSearchBar(
          controller: _guardianSearchController,
          onChanged: _filterGuardians,
          hint: 'Search by name, email, phone, or address...',
          isSearching: _isSearchingGuardians,
          count: _filteredGuardians.length,
          label: 'guardian',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: kOrange,
            child: _isSearchingGuardians && _filteredGuardians.isEmpty
                ? _buildEmptySearchResults()
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOrange.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    color: kNavy,
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
                icon: Icon(Icons.message, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _showGuardianDetails(guardian),
              ),
              IconButton(
                icon: Icon(Icons.visibility, color: kOrange, size: _isMobile ? 20 : 22),
                onPressed: () => _showGuardianDetails(guardian),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesScreen() {
    return const MessagesScreen();
  }

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
              color: kNavy,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kOrange.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
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
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isDestructive ? AppColors.error : kOrange).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isDestructive ? AppColors.error : kOrange).withOpacity(0.2),
              ),
            ),
            child: Icon(icon, color: isDestructive ? AppColors.error : kOrange, size: 20),
          ),
          title: Text(title, style: TextStyle(color: isDestructive ? AppColors.error : kNavy)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap ?? _showComingSoon,
        ),
        const Divider(height: 1),
      ],
    );
  }

  // ==================== COMMON WIDGETS ====================

  Widget _buildSearchBar({
    required TextEditingController controller,
    required Function(String) onChanged,
    required String hint,
    required bool isSearching,
    required int count,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          color: Colors.white,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: _isMobile ? 13 : 14, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: kOrange, size: _isMobile ? 20 : 22),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _isMobile ? 18 : 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kOrange.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kOrange.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kOrange, width: 2),
              ),
              filled: true,
              fillColor: kLightOrange,
              contentPadding: EdgeInsets.symmetric(
                vertical: _isMobile ? 10 : 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
        if (isSearching)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 16, vertical: 8),
            color: kOrange.withOpacity(0.05),
            child: Text(
              'Found $count $label${count != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: _isMobile ? 12 : 13,
                color: kOrange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyScreen(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kOrange.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: kOrange.withOpacity(0.2)),
            ),
            child: Icon(icon, size: 64, color: kOrange.withOpacity(0.3)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: _isMobile ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: _isMobile ? 12 : 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: kOrange.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: _isMobile ? 14 : 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kOrange.withOpacity(0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.logout, color: AppColors.error),
            const SizedBox(width: 8),
            const Text('Logout', style: TextStyle(color: AppColors.error)),
          ],
        ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ─── Data Models ──────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  final bool? isMessages;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    this.isMessages,
  });
}