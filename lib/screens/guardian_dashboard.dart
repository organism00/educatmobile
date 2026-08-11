import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../models/result_model.dart';
import '../models/discount_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/discount_provider.dart';
import '../services/fee_provider.dart';
import '../utils/app_colors.dart';
import '../screens/conversation_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/student_discount_screen.dart';
import '../screens/fee_payment_screen.dart';
import 'login_screen.dart';

class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({super.key});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  int _selectedIndex = 0;
  late UserModel _currentUser;
  late ApiService _apiService;

  // Data states
  List<Map<String, dynamic>> _pupils = [];
  List<Map<String, dynamic>> _filteredPupils = [];
  double _walletBalance = 0.00;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Account details
  String _accountNumber = '';
  String _accountName = '';
  String _bankName = '';
  double _ledgerBalance = 0.00;

  // Loan data
  double _loanBalance = 0.00;
  int _activeLoans = 0;
  bool _isLoadingLoan = false;

  // Carousel
  int _currentCarouselIndex = 0;
  final PageController _pageController = PageController();

  // News data
  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  // HMO data
  List<Map<String, dynamic>> _hospitalRecords = [];
  bool _isLoadingHMO = false;
  int _selectedPupilForHMO = 0;

  // Results data
  bool _isLoadingResult = false;

  // Assignments data
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoadingAssignments = false;

  // Messages - Unread count
  int _unreadMessageCount = 0;

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchingPupils = false;

  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadUserData();
    _fetchDashboardData();
    _fetchNews();
    _fetchUnreadMessages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;

    // Debug: Print user session info
    print('👤 Current User: ${_currentUser.name}');
    print('📅 Session ID: ${_currentUser.sessionId}');
    print('📚 Term: ${_currentUser.term}');
    print('🏫 School ID: ${_currentUser.schoolId}');
  }

  Future<void> _fetchUnreadMessages() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    final result = await _apiService.getInboxMessages(
      token: token,
      userId: _currentUser.id,
      userRole: 'Guardian',
    );

    if (result['success'] && mounted) {
      final messages = result['data'] as List? ?? [];
      final unreadCount = messages.where((m) => m['isRead'] == false).length;
      setState(() {
        _unreadMessageCount = unreadCount;
      });
    }
  }

  // Helper method to get session ID
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

    print('📅 Final Session ID: $sessionId');
    return sessionId;
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
      print('🔍 Step 1: Fetching students...');
      final studentsResult = await _apiService.getGuardianStudents(
        token: token,
        guardianId: _currentUser.id,
      ).timeout(const Duration(seconds: 30));

      if (studentsResult['success'] && mounted) {
        print('✅ Step 2: Students fetched successfully');
        final studentsData = studentsResult['data'] as List? ?? [];

        final List<Map<String, dynamic>> mappedPupils = [];
        final String sessionId = _getCurrentSessionId();

        for (var student in studentsData) {
          final guardian = student['guardian'];
          final teacher = student['teacher'];
          final classroom = student['classroom'];
          final studentId = student['studentId'] ?? '';
          final classroomId = student['classroomId'] ?? '';

          // Extract fee from student data
          double feeAmount = 0.0;

          // Check various possible fee locations
          if (student['fee'] != null) {
            feeAmount = (student['fee'] as num?)?.toDouble() ?? 0.0;
          } else if (classroom != null) {
            feeAmount = (classroom['fee'] as num?)?.toDouble() ??
                (classroom['amount'] as num?)?.toDouble() ??
                (classroom['feeAmount'] as num?)?.toDouble() ??
                (classroom['schoolFee'] as num?)?.toDouble() ??
                0.0;
          }

          // If fee is still 0, fetch class fee for term
          if (feeAmount == 0.0 && classroomId.isNotEmpty && token != null && sessionId.isNotEmpty) {
            try {
              print('🔍 Fetching class fee for classroom: $classroomId with session: $sessionId');
              final feeResult = await _apiService.getClassFeeForTerm(
                token: token,
                classId: classroomId,
                sessionId: sessionId,
              );
              if (feeResult['success'] && feeResult['fee'] > 0) {
                feeAmount = feeResult['fee'];
                print('💰 Class fee fetched: $feeAmount');
              } else {
                print('⚠️ Class fee fetch failed: ${feeResult['message']}');
              }
            } catch (e) {
              print('⚠️ Error fetching class fee: $e');
            }
          }

          // If still 0, try student fee endpoint as fallback
          if (feeAmount == 0.0 && studentId.isNotEmpty && token != null && sessionId.isNotEmpty) {
            try {
              final feeResult = await _apiService.getStudentFee(
                token: token,
                studentId: studentId,
                sessionId: sessionId,
              );
              if (feeResult['success'] && feeResult['fee'] > 0) {
                feeAmount = feeResult['fee'];
                print('💰 Student fee fetched separately: $feeAmount');
              }
            } catch (e) {
              print('⚠️ Error fetching student fee separately: $e');
            }
          }

          print('💰 Student: ${student['firstname']} ${student['lastname']}, Fee: $feeAmount');

          mappedPupils.add({
            'id': studentId,
            'name': '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
            'class': classroom?['name'] ?? student['classroomId'] ?? 'N/A',
            'classroomId': classroomId,
            'classroomName': classroom?['name'] ?? 'N/A',
            'teacherId': teacher?['teacherId'] ?? '',
            'teacherName': teacher != null
                ? '${teacher['firstname'] ?? ''} ${teacher['lastname'] ?? ''}'.trim()
                : 'Not Assigned',
            'teacherEmail': teacher?['email'] ?? 'Not available',
            'teacherPhone': teacher?['phone'] ?? 'Not available',
            'feeStatus': 'Pending',
            'feeAmount': feeAmount,
            'averageScore': 0,
            'attendance': 0,
            'admissionNo': student['studentNo'] ?? '',
          });
        }

        setState(() {
          _pupils = mappedPupils;
          _filteredPupils = List.from(mappedPupils);
        });

        print('✅ Step 3: Pupils mapped: ${_pupils.length}');

        // Print fee summary
        _pupils.forEach((pupil) {
          print('📊 ${pupil['name']}: Fee = ${pupil['feeAmount']}');
        });

        // Load essential data first
        print('🔍 Step 4: Fetching wallet and account...');
        await _fetchWalletAndAccount(token);

        print('🔍 Step 5: Fetching loan data...');
        await _fetchLoanData(token);

        print('🔍 Step 6: Fetching assignments...');
        await _fetchAssignments(token);

        // Load discounts in the background
        print('🔍 Step 7: Fetching discounts in background...');
        _fetchDiscountsForAllPupils(token);

        print('✅ Dashboard loaded successfully');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _errorMessage = studentsResult['message'] ?? 'Failed to load students data';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error fetching dashboard data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error. Please check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDiscountsForAllPupils(String token) async {
    try {
      final discountProvider = Provider.of<DiscountProvider>(context, listen: false);

      if (_pupils.isEmpty) {
        print('ℹ️ No pupils to fetch discounts for');
        return;
      }

      print('🔍 Fetching discounts for ${_pupils.length} pupils');

      final futures = _pupils.map((pupil) async {
        final studentId = pupil['id']?.toString();
        if (studentId != null && studentId.isNotEmpty) {
          try {
            await discountProvider.fetchStudentDiscounts(
              token: token,
              studentId: studentId,
            );
          } catch (e) {
            print('⚠️ Error fetching discounts for student $studentId: $e');
          }
        }
      }).toList();

      await Future.wait(futures, eagerError: false);
      print('✅ All discounts fetched');
    } catch (e) {
      print('⚠️ Error in _fetchDiscountsForAllPupils: $e');
    }
  }

  void _filterPupils(String query) {
    setState(() {
      _isSearchingPupils = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredPupils = List.from(_pupils);
      } else {
        _filteredPupils = _pupils.where((pupil) {
          final name = pupil['name'].toString().toLowerCase();
          final className = pupil['class'].toString().toLowerCase();
          final teacherName = pupil['teacherName'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              className.contains(query.toLowerCase()) ||
              teacherName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _fetchWalletAndAccount(String token) async {
    try {
      final accountResult = await _apiService.getGuardianSavingsAccount(
        token: token,
        guardianId: _currentUser.id,
      ).timeout(const Duration(seconds: 30));

      if (accountResult['success'] && mounted) {
        setState(() {
          _walletBalance = accountResult['balance'] ?? 0.0;
          _accountNumber = accountResult['accountNumber'] ?? '';
          _accountName = accountResult['accountName'] ?? '';
          _bankName = accountResult['bankName'] ?? '';
          _ledgerBalance = accountResult['ledgerBalance'] ?? 0.0;
        });
      }
    } catch (e) {
      print('Error fetching wallet: $e');
    }
  }

  Future<void> _fetchLoanData(String token) async {
    setState(() {
      _isLoadingLoan = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _loanBalance = 0.00;
      _activeLoans = 0;
      _isLoadingLoan = false;
    });
  }

  Future<void> _fetchAssignments(String token) async {
    setState(() {
      _isLoadingAssignments = true;
    });

    List<Map<String, dynamic>> allAssignments = [];

    for (var pupil in _pupils) {
      final classroomId = pupil['classroomId']?.toString();
      if (classroomId != null && classroomId.isNotEmpty && classroomId != 'N/A') {
        try {
          final result = await _apiService.getAssignmentsByClassId(
            token: token,
            classroomId: classroomId,
          ).timeout(const Duration(seconds: 30));

          if (result['success'] && result['data'] != null) {
            final assignments = List<Map<String, dynamic>>.from(result['data']);
            for (var assignment in assignments) {
              assignment['className'] = pupil['class'];
            }
            allAssignments.addAll(assignments);
          }
        } catch (e) {
          print('Error fetching assignments for class $classroomId: $e');
        }
      }
    }

    setState(() {
      _assignments = allAssignments;
      _isLoadingAssignments = false;
    });
  }

  Future<void> _fetchNews() async {
    setState(() {
      _isLoadingNews = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token != null) {
      try {
        final newsResult = await _apiService.getAllNews(token: token).timeout(const Duration(seconds: 30));
        if (newsResult['success'] && mounted) {
          setState(() {
            _news = (newsResult['data'] as List?)?.map((item) => ({
              'id': item['id'],
              'title': item['title'],
              'content': item['content'],
              'date': _formatDate(item['date']),
            })).toList() ?? [];
            _isLoadingNews = false;
          });
        } else {
          setState(() {
            _isLoadingNews = false;
          });
        }
      } catch (e) {
        print('Error fetching news: $e');
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

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'Recent';
    try {
      DateTime dateTime = DateTime.parse(dateValue.toString());
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
    } catch (e) {
      return 'Recent';
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    await _fetchDashboardData();
    await _fetchNews();
    await _fetchUnreadMessages();
    setState(() {
      _isRefreshing = false;
    });
  }

  // ==================== FEE PAYMENT METHODS ====================

  Future<void> _payFeesForPupil(Map<String, dynamic> pupil) async {
    final studentId = pupil['id']?.toString();
    final classroomId = pupil['classroomId']?.toString();
    final studentName = pupil['name'] ?? 'Student';
    final studentClass = pupil['class'] ?? 'N/A';

    // Get current fee amount
    double feeAmount = pupil['feeAmount'] as double? ?? 0.0;

    print('💰 Pay fee for: $studentName');
    print('💰 Current fee amount: $feeAmount');
    print('💰 Student ID: $studentId');
    print('💰 Classroom ID: $classroomId');

    if (studentId == null || studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student ID not available'), backgroundColor: AppColors.warning),
      );
      return;
    }

    if (classroomId == null || classroomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Classroom ID not available'), backgroundColor: AppColors.warning),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final String sessionId = _getCurrentSessionId();

    // If fee is 0 or we want to refresh it, fetch from API
    try {
      if (token != null && sessionId.isNotEmpty) {
        print('🔍 Fetching class fee from API with session: $sessionId');

        // First try: Get class fee for term
        final feeResult = await _apiService.getClassFeeForTerm(
          token: token,
          classId: classroomId,
          sessionId: sessionId,
        );

        if (feeResult['success'] && feeResult['fee'] > 0) {
          feeAmount = feeResult['fee'];
          print('💰 Class fee fetched: $feeAmount');

          // Update the pupil's fee in the list
          setState(() {
            final index = _pupils.indexWhere((p) => p['id'] == studentId);
            if (index != -1) {
              _pupils[index]['feeAmount'] = feeAmount;
              _filteredPupils[index]['feeAmount'] = feeAmount;
            }
          });
        } else {
          print('⚠️ Failed to fetch class fee: ${feeResult['message']}');

          // Try student fee endpoint as fallback
          print('🔍 Trying student fee endpoint...');
          final studentFeeResult = await _apiService.getStudentFee(
            token: token,
            studentId: studentId,
            sessionId: sessionId,
          );

          if (studentFeeResult['success'] && studentFeeResult['fee'] > 0) {
            feeAmount = studentFeeResult['fee'];
            print('💰 Student fee fetched: $feeAmount');

            // Update the pupil's fee in the list
            setState(() {
              final index = _pupils.indexWhere((p) => p['id'] == studentId);
              if (index != -1) {
                _pupils[index]['feeAmount'] = feeAmount;
                _filteredPupils[index]['feeAmount'] = feeAmount;
              }
            });
          } else {
            print('⚠️ Failed to fetch student fee: ${studentFeeResult['message']}');
          }
        }
      } else {
        print('⚠️ Cannot fetch fee: token or sessionId is empty');
        print('Token: ${token != null ? "Present" : "Missing"}');
        print('SessionId: $sessionId');
      }
    } catch (e) {
      print('⚠️ Error fetching fee: $e');
    } finally {
      // Close loading dialog
      Navigator.pop(context);
    }

    // Check if we have a valid fee
    if (feeAmount <= 0) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Fee Available', style: TextStyle(color: AppColors.warning)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: AppColors.warning),
              const SizedBox(height: 16),
              Text('No fee amount has been set for $studentName.'),
              const SizedBox(height: 12),
              const Text('Please contact the school administrator to set the fee amount.'),
              const SizedBox(height: 8),
              Text(
                'Classroom ID: $classroomId\nSession: $sessionId',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Retry fetching fee
                _payFeesForPupil(pupil);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      return;
    }

    // Navigate to payment screen with the fee
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeePaymentScreen(
          studentId: studentId,
          studentName: studentName,
          studentClass: studentClass,
          classroomId: classroomId,
          originalFee: feeAmount,
          sessionId: sessionId,
        ),
      ),
    );
  }

  // ==================== DISCOUNT METHODS ====================

  void _showStudentDiscounts(Map<String, dynamic> pupil) {
    final studentId = pupil['id']?.toString();
    if (studentId == null || studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student ID not available'), backgroundColor: AppColors.warning),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDiscountScreen(
          studentId: studentId,
          studentName: pupil['name'],
          studentClass: pupil['class'],
          admissionNo: pupil['admissionNo'],
        ),
      ),
    );
  }

  // ==================== PHONE CALL METHOD ====================

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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dial $phoneNumber'), backgroundColor: AppColors.error),
      );
    }
  }

  // ==================== NAVIGATION METHODS ====================

  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MessagesScreen()),
    ).then((_) => _fetchUnreadMessages());
  }

  void _startConversationWithTeacher(Map<String, dynamic> pupil) {
    final teacherId = pupil['teacherId']?.toString() ?? '';
    final teacherName = pupil['teacherName']?.toString() ?? 'Teacher';

    if (teacherId.isEmpty || teacherId == 'Not Assigned') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teacher not assigned'), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          userId: teacherId,
          userRole: 'Teacher',
          userName: teacherName,
          userEmail: pupil['teacherEmail']?.toString(),
          userPhone: pupil['teacherPhone']?.toString(),
        ),
      ),
    ).then((_) => _fetchUnreadMessages());
  }

  // ==================== DETAIL ROW METHODS ====================

  Widget _buildDetailRow(String label, String value, {bool isSmallScreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: isSmallScreen ? 70 : 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: isSmallScreen ? 11 : 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: isSmallScreen ? 11 : 12,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClickablePhoneRow(String label, String phoneNumber, bool isSmallScreen) {
    final bool hasValidPhone = phoneNumber.isNotEmpty &&
        phoneNumber != 'N/A' &&
        phoneNumber != 'Not available' &&
        phoneNumber != '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: hasValidPhone ? () => _makePhoneCall(phoneNumber) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: hasValidPhone ? AppColors.success.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: isSmallScreen ? 70 : 80,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: isSmallScreen ? 11 : 12,
                      ),
                    ),
                  ),
                  if (hasValidPhone) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'CALL',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 8 : 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      phoneNumber,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: isSmallScreen ? 11 : 12,
                        color: hasValidPhone ? AppColors.primary : AppColors.textPrimary,
                        decoration: hasValidPhone ? TextDecoration.underline : null,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasValidPhone) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.phone, size: isSmallScreen ? 14 : 16, color: AppColors.primary),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== PUPIL DETAILS DIALOG ====================

  void _showPupilDetails(Map<String, dynamic> pupil) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final bool hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'].toString().isNotEmpty &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'] != 'Not available';

    // Get current fee
    double feeAmount = pupil['feeAmount'] as double? ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                pupil['name'],
                style: const TextStyle(color: AppColors.primary, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasPhone)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'CALL',
                  style: TextStyle(fontSize: isSmallScreen ? 9 : 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Student Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Admission No', pupil['admissionNo'], isSmallScreen: isSmallScreen),
                    _buildDetailRow('Class', pupil['class'], isSmallScreen: isSmallScreen),
                    _buildDetailRow(
                      'Fee',
                      feeAmount > 0 ? '₦${feeAmount.toStringAsFixed(2)}' : 'Not Set',
                      isSmallScreen: isSmallScreen,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Teacher Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Name', pupil['teacherName'], isSmallScreen: isSmallScreen),
                    _buildDetailRow('Email', pupil['teacherEmail'], isSmallScreen: isSmallScreen),
                    _buildClickablePhoneRow('Phone', pupil['teacherPhone'], isSmallScreen),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (feeAmount > 0)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _payFeesForPupil(pupil);
              },
              icon: const Icon(Icons.payment, size: 18),
              label: const Text('Pay Fees'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          if (feeAmount <= 0)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _payFeesForPupil(pupil);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Fetch Fee'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _startConversationWithTeacher(pupil);
            },
            icon: const Icon(Icons.message, size: 18),
            label: const Text('Message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          if (hasPhone)
            ElevatedButton.icon(
              onPressed: () => _makePhoneCall(pupil['teacherPhone']),
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== RESULT METHODS ====================

  Future<void> _viewPupilResults(Map<String, dynamic> pupil) async {
    final classroomId = pupil['classroomId']?.toString();
    if (classroomId == null || classroomId.isEmpty) {
      _showNoClassroomDialog(pupil);
      return;
    }

    setState(() {
      _isLoadingResult = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      setState(() {
        _isLoadingResult = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication error'), backgroundColor: AppColors.error),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final result = await _apiService.getStudentAllSubjectsScoresByTermId(
      token: token,
      schoolId: _currentUser.schoolId,
      classroomId: classroomId,
      studentId: pupil['id'],
      sessionKey: _currentUser.sessionKey,
      termId: _currentUser.termId,
    );

    Navigator.pop(context);

    setState(() {
      _isLoadingResult = false;
    });

    if (result['success'] && result['data'] != null) {
      _showResultDetailsDialog(pupil, result['data']);
    } else {
      _showNoResultDialog(pupil, result['message'] ?? 'No results available');
    }
  }

  void _showResultDetailsDialog(Map<String, dynamic> pupil, dynamic resultData) {
    final studentResult = StudentResult.fromJson(resultData);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.95,
              height: MediaQuery.of(context).size.height * 0.9,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          pupil['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${studentResult.className} | ${studentResult.term}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Admission: ${pupil['admissionNo']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isSmallScreen)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildMiniSummaryCard('Total', '${studentResult.totalScore.toStringAsFixed(1)}%', Icons.assessment, AppColors.primary),
                          const SizedBox(width: 8),
                          _buildMiniSummaryCard('Average', '${studentResult.averageScore.toStringAsFixed(1)}%', Icons.trending_up, AppColors.info),
                          const SizedBox(width: 8),
                          _buildMiniSummaryCard('Grade', studentResult.grade, Icons.grade, _getGradeColor(studentResult.grade)),
                          const SizedBox(width: 8),
                          _buildMiniSummaryCard('Attendance', '${studentResult.attendancePercentage.toStringAsFixed(0)}%', Icons.calendar_today,
                              studentResult.attendancePercentage >= 75 ? AppColors.success : AppColors.warning),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(child: _buildSummaryCard('Total Score', '${studentResult.totalScore.toStringAsFixed(1)}%', Icons.assessment, AppColors.primary)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSummaryCard('Average Score', '${studentResult.averageScore.toStringAsFixed(1)}%', Icons.trending_up, AppColors.info)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSummaryCard('Grade', studentResult.grade, Icons.grade, _getGradeColor(studentResult.grade))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSummaryCard('Attendance', '${studentResult.attendancePercentage.toStringAsFixed(0)}%', Icons.calendar_today,
                            studentResult.attendancePercentage >= 75 ? AppColors.success : AppColors.warning)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: isSmallScreen ? 8 : 12,
                        headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
                        columns: const [
                          DataColumn(label: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('CA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('Exam', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('Grade', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('Remark', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                        rows: studentResult.subjects.map((subject) {
                          return DataRow(cells: [
                            DataCell(Text(subject.subjectName, style: TextStyle(fontSize: 11))),
                            DataCell(Text(subject.caScore.toStringAsFixed(1), style: TextStyle(fontSize: 11))),
                            DataCell(Text(subject.examScore.toStringAsFixed(1), style: TextStyle(fontSize: 11))),
                            DataCell(
                              Text(
                                subject.totalScore.toStringAsFixed(1),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: _getScoreColor(subject.totalScore.toInt()),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getGradeColor(subject.grade).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  subject.grade,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: _getGradeColor(subject.grade),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(subject.remark.length > 15 ? '${subject.remark.substring(0, 15)}...' : subject.remark, style: TextStyle(fontSize: 10))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (studentResult.teacherRemark.isNotEmpty && studentResult.teacherRemark != 'No remark')
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.comment, color: AppColors.info, size: 14),
                              const SizedBox(width: 4),
                              const Text('Teacher:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            studentResult.teacherRemark,
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  if (studentResult.principalRemark.isNotEmpty && studentResult.principalRemark != 'No remark')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.school, color: AppColors.primary, size: 14),
                                const SizedBox(width: 4),
                                const Text('Principal:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              studentResult.principalRemark,
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _downloadResultPDF(pupil, resultData),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('Download PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3)],
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 85,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            title,
            style: TextStyle(fontSize: 8, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A': return AppColors.success;
      case 'B': return Colors.lightGreen;
      case 'C': return AppColors.info;
      case 'D': return AppColors.warning;
      case 'F': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  void _downloadResultPDF(Map<String, dynamic> pupil, dynamic resultData) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDF download started!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showNoClassroomDialog(Map<String, dynamic> pupil) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Classroom Not Assigned', style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.warning),
            const SizedBox(height: 16),
            Text('${pupil['name']} has not been assigned to a classroom yet.'),
            const SizedBox(height: 12),
            Text('Please contact the school administrator.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showNoResultDialog(Map<String, dynamic> pupil, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Results Found', style: TextStyle(color: AppColors.warning)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 48, color: AppColors.warning),
            const SizedBox(height: 16),
            Text('No academic results available for ${pupil['name']}'),
            const SizedBox(height: 12),
            Text(message.isNotEmpty ? message : 'Results have not been published yet.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  // ==================== CAROUSEL METHODS ====================

  Widget _buildCarousel(ResponsiveInfo resp) {
    final List<Widget> carouselItems = [
      _buildWalletCard(resp),
      _buildLoanCard(resp),
    ];

    return Column(
      children: [
        SizedBox(
          height: resp.isMobile ? 230 : 250,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
            itemCount: carouselItems.length,
            itemBuilder: (context, index) {
              return carouselItems[index];
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(carouselItems.length, (index) {
            return GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentCarouselIndex == index
                      ? AppColors.primary
                      : AppColors.grey,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildWalletCard(ResponsiveInfo resp) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: EdgeInsets.all(resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wallet Balance',
                style: TextStyle(
                  fontSize: resp.isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                child: const Text(
                  'Active',
                  style: TextStyle(fontSize: 10, color: AppColors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '₦${_walletBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: resp.isMobile ? 28 : resp.isTablet ? 34 : 38,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _showFundWalletDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(resp.isMobile ? 'Fund' : 'Fund Wallet', style: TextStyle(fontSize: resp.isMobile ? 12 : 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _showLoanRequestDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(resp.isMobile ? 'Loan' : 'Get Loan', style: TextStyle(fontSize: resp.isMobile ? 12 : 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(ResponsiveInfo resp) {
    if (_isLoadingLoan) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.all(resp.isMobile ? 16 : 20),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.white),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: EdgeInsets.all(resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Loan Summary',
                style: TextStyle(
                  fontSize: resp.isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _activeLoans > 0 ? AppColors.warning.withOpacity(0.2) : AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _activeLoans > 0 ? 'Active' : 'No Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: _activeLoans > 0 ? AppColors.warning : AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '₦${_loanBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: resp.isMobile ? 28 : resp.isTablet ? 34 : 38,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showLoanDetailsDialog(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Details', style: TextStyle(fontSize: resp.isMobile ? 12 : 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loanBalance > 0 ? () => _showRepaymentDialog() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Repay', style: TextStyle(fontSize: resp.isMobile ? 12 : 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== LOAN DETAILS METHODS ====================

  void _showLoanDetailsDialog() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Loan Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildLoanDetailRow('Total Loan Amount', '₦${_loanBalance.toStringAsFixed(2)}', isSmallScreen),
                    _buildLoanDetailRow('Loan Balance', '₦${_loanBalance.toStringAsFixed(2)}', isSmallScreen),
                    _buildLoanDetailRow('Monthly Repayment', '₦0.00', isSmallScreen),
                    _buildLoanDetailRow('Next Due Date', 'N/A', isSmallScreen),
                    _buildLoanDetailRow('Remaining Tenure', 'N/A', isSmallScreen),
                    const Divider(height: 24),
                    const Text(
                      'Repayment Schedule',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text('No repayment history available'),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRepaymentDialog() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repay Loan', style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Outstanding Balance: ₦${_loanBalance.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 13 : 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₦',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Note: Payment will be processed from your wallet',
              style: TextStyle(fontSize: isSmallScreen ? 10 : 11, color: AppColors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (amountController.text.isNotEmpty) {
                double amount = double.tryParse(amountController.text) ?? 0;
                if (_loanBalance > 0 && amount > 0 && amount <= _loanBalance && amount <= _walletBalance) {
                  setState(() {
                    _loanBalance -= amount;
                    _walletBalance -= amount;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment of ₦${amount.toStringAsFixed(2)} successful!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else if (_loanBalance == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No active loan to repay'),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                } else if (amount > _loanBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Amount exceeds loan balance'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                } else if (amount > _walletBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Insufficient wallet balance'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Repay'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanDetailRow(String label, String value, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.grey, fontSize: isSmallScreen ? 12 : 13)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 12 : 13)),
        ],
      ),
    );
  }

  // ==================== FEE PAYMENT SCREEN ====================

  void _showFeesScreen() async {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning),
      );
      return;
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final String sessionId = _getCurrentSessionId();

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    // Fetch fees for all pupils
    List<Map<String, dynamic>> updatedPupils = List.from(_pupils);

    for (var i = 0; i < updatedPupils.length; i++) {
      final pupil = updatedPupils[i];
      final classroomId = pupil['classroomId']?.toString();
      final studentId = pupil['id']?.toString();
      double feeAmount = pupil['feeAmount'] as double? ?? 0.0;

      // If fee is 0, try to fetch it
      if (feeAmount <= 0 && classroomId != null && classroomId.isNotEmpty && token != null && sessionId.isNotEmpty) {
        try {
          final feeResult = await _apiService.getClassFeeForTerm(
            token: token,
            classId: classroomId,
            sessionId: sessionId,
          );

          if (feeResult['success'] && feeResult['fee'] > 0) {
            feeAmount = feeResult['fee'];
            updatedPupils[i]['feeAmount'] = feeAmount;
            print('💰 Fee fetched for ${pupil['name']}: $feeAmount');
          }
        } catch (e) {
          print('⚠️ Error fetching fee for ${pupil['name']}: $e');
        }
      }
    }

    // Update the pupils list
    setState(() {
      _pupils = updatedPupils;
      _filteredPupils = List.from(_pupils);
    });

    // Close loading dialog
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'School Fees Payment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: _pupils.map((pupil) {
                    final feeAmount = pupil['feeAmount'] as double? ?? 0.0;
                    final hasFee = feeAmount > 0;

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: isSmallScreen ? 18 : 20,
                        backgroundColor: hasFee ? AppColors.primary.withOpacity(0.1) : AppColors.grey.withOpacity(0.1),
                        child: Text(
                          (pupil['name'] as String)[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            color: hasFee ? AppColors.primary : AppColors.grey,
                          ),
                        ),
                      ),
                      title: Text(
                        pupil['name'] as String,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          color: hasFee ? AppColors.textPrimary : AppColors.grey,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Class: ${pupil['class']}',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 12,
                              color: hasFee ? AppColors.textSecondary : AppColors.grey,
                            ),
                          ),
                          if (!hasFee)
                            Text(
                              'Click to fetch fee',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 11,
                                color: AppColors.info,
                              ),
                            ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hasFee ? '₦${feeAmount.toStringAsFixed(2)}' : 'No Fee',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallScreen ? 12 : 13,
                              color: hasFee ? AppColors.primary : AppColors.grey,
                            ),
                          ),
                          if (hasFee)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Payable',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _payFeesForPupil(pupil);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== HMO METHODS ====================

  Future<void> _fetchHospitalRecords(String token, String studentId) async {
    final recordsResult = await _apiService.getChildHospitalRecords(
      token: token,
      studentId: studentId,
      schoolId: _currentUser.schoolId,
      sessionId: _currentUser.sessionId,
    );

    if (recordsResult['success'] && mounted) {
      setState(() {
        _hospitalRecords = (recordsResult['data'] as List?)?.map((record) => ({
          'id': record['id'],
          'date': record['visitDate'] ?? record['date'],
          'hospitalName': record['hospitalName'],
          'diagnosis': record['diagnosis'],
          'treatment': record['treatment'],
          'doctorName': record['doctorName'],
          'visitType': record['visitType'] ?? 'School',
          'cost': (record['cost'] ?? 0).toDouble(),
          'hmoCovered': record['hmoCovered'] ?? true,
        })).toList() ?? [];
        _isLoadingHMO = false;
      });
    } else {
      if (mounted) {
        setState(() {
          _isLoadingHMO = false;
          _hospitalRecords = [];
        });
      }
    }
  }

  void _showHMOScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning),
      );
      return;
    }

    if (_hospitalRecords.isEmpty && _pupils.isNotEmpty) {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token != null) {
        _fetchHospitalRecords(token, _pupils[0]['id']);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, bottomSheetSetState) {
                final isSmallScreen = MediaQuery.of(context).size.width < 600;

                return Container(
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Health Records (HMO)',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 20 : 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                        decoration: BoxDecoration(
                          gradient: AppColors.cardGradientLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Child',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButton<int>(
                              value: _selectedPupilForHMO,
                              isExpanded: true,
                              underline: const SizedBox(),
                              icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                color: AppColors.textPrimary,
                              ),
                              items: _pupils.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, dynamic> pupil = entry.value;
                                return DropdownMenuItem<int>(
                                  value: index,
                                  child: Text(
                                    pupil['name'] as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value != null && value != _selectedPupilForHMO) {
                                  bottomSheetSetState(() {
                                    _selectedPupilForHMO = value;
                                    _isLoadingHMO = true;
                                    _hospitalRecords = [];
                                  });

                                  final token = Provider.of<AuthProvider>(context, listen: false).token;
                                  if (token != null) {
                                    await _fetchHospitalRecords(token, _pupils[_selectedPupilForHMO]['id']);
                                    if (mounted) {
                                      bottomSheetSetState(() {
                                        _isLoadingHMO = false;
                                      });
                                    }
                                  } else {
                                    bottomSheetSetState(() {
                                      _isLoadingHMO = false;
                                    });
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_isLoadingHMO && _hospitalRecords.isNotEmpty)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildHMOStatCard('Total Visits', _hospitalRecords.length.toString(), Icons.local_hospital, AppColors.primary, isSmallScreen),
                              const SizedBox(width: 8),
                              _buildHMOStatCard('School Visit', _hospitalRecords.where((r) => r['visitType'] == 'School').length.toString(), Icons.school, AppColors.info, isSmallScreen),
                              const SizedBox(width: 8),
                              _buildHMOStatCard('Home Visit', _hospitalRecords.where((r) => r['visitType'] == 'Home').length.toString(), Icons.home, AppColors.success, isSmallScreen),
                              const SizedBox(width: 8),
                              _buildHMOStatCard('Total Cost', '₦${_hospitalRecords.fold(0.0, (sum, r) => sum + (r['cost'] as double)).toStringAsFixed(0)}', Icons.money, AppColors.warning, isSmallScreen),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _isLoadingHMO
                            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                            : _hospitalRecords.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.medical_information, size: isSmallScreen ? 40 : 48, color: AppColors.grey),
                              const SizedBox(height: 12),
                              Text('No hospital records found', style: TextStyle(fontSize: isSmallScreen ? 13 : 14, color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                            : ListView.builder(
                          controller: scrollController,
                          itemCount: _hospitalRecords.length,
                          itemBuilder: (context, index) {
                            final record = _hospitalRecords[index];
                            return _buildHMORecordCard(record, isSmallScreen);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHMOStatCard(String title, String value, IconData icon, Color color, bool isSmallScreen) {
    return Container(
      width: isSmallScreen ? 80 : 100,
      padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: isSmallScreen ? 20 : 24, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: isSmallScreen ? 9 : 10, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHMORecordCard(Map<String, dynamic> record, bool isSmallScreen) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                decoration: BoxDecoration(
                  color: record['visitType'] == 'School'
                      ? AppColors.info.withOpacity(0.1)
                      : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  record['visitType'] == 'School' ? Icons.school : Icons.home,
                  size: isSmallScreen ? 16 : 20,
                  color: record['visitType'] == 'School' ? AppColors.info : AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['hospitalName'] ?? 'Hospital Visit',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                    ),
                    Text(
                      record['date'] ?? 'Date not specified',
                      style: TextStyle(fontSize: isSmallScreen ? 10 : 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: record['hmoCovered'] == true ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  record['hmoCovered'] == true ? 'HMO' : 'Out of Pocket',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 9 : 10,
                    color: record['hmoCovered'] == true ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (record['diagnosis'] != null && record['diagnosis'].toString().isNotEmpty)
            Text(
              'Diagnosis: ${record['diagnosis']}',
              style: TextStyle(fontSize: isSmallScreen ? 11 : 12),
            ),
          if (record['treatment'] != null && record['treatment'].toString().isNotEmpty)
            Text(
              'Treatment: ${record['treatment']}',
              style: TextStyle(fontSize: isSmallScreen ? 11 : 12),
            ),
          if (record['doctorName'] != null && record['doctorName'].toString().isNotEmpty)
            Text(
              'Doctor: ${record['doctorName']}',
              style: TextStyle(fontSize: isSmallScreen ? 10 : 11, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 10, vertical: isSmallScreen ? 4 : 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Cost', style: TextStyle(fontSize: isSmallScreen ? 10 : 11, color: AppColors.textSecondary)),
                Text(
                  '₦${(record['cost'] as double).toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 12 : 13, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ASSIGNMENT METHODS ====================

  void _showViewAssignmentsScreen() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Assignments',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: isSmallScreen ? 20 : 24),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoadingAssignments
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _assignments.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_turned_in, size: isSmallScreen ? 48 : 64, color: AppColors.grey),
                        const SizedBox(height: 12),
                        Text('No assignments yet', style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                      : ListView.builder(
                    controller: scrollController,
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final assignment = _assignments[index];
                      return _buildAssignmentCard(assignment, isSmallScreen);
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

  Widget _buildAssignmentCard(Map<String, dynamic> assignment, bool isSmallScreen) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());
    final className = assignment['className'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? AppColors.error.withOpacity(0.3) : AppColors.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.assignment,
                  color: isOverdue ? AppColors.error : AppColors.primary,
                  size: isSmallScreen ? 16 : 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment['title'] ?? 'Untitled',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Due: ${_formatDate(assignment['dueDate'])}',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 11,
                        color: isOverdue ? AppColors.error : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isOverdue ? 'Overdue' : 'Active',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 9 : 10,
                    color: isOverdue ? AppColors.error : AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assignment['description'] ?? 'No description',
            style: TextStyle(fontSize: isSmallScreen ? 11 : 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.class_, size: isSmallScreen ? 12 : 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(className, style: TextStyle(fontSize: isSmallScreen ? 10 : 11, color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => _showAssignmentDetails(assignment),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('View', style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: AppColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(assignment['title'] ?? 'Assignment Details', style: const TextStyle(color: AppColors.primary, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(assignment['description'] ?? 'No description', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Due Date:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(_formatDate(assignment['dueDate']), style: TextStyle(fontSize: 12, color: isOverdue ? AppColors.error : AppColors.textPrimary)),
              const SizedBox(height: 12),
              const Text('Class:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(assignment['className'] ?? 'N/A', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  // ==================== UI BUILD METHODS ====================

  void _showResultsScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning),
      );
      return;
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Student Results',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: _pupils.map((pupil) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: isSmallScreen ? 18 : 20,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text((pupil['name'] as String)[0].toUpperCase(), style: const TextStyle(fontSize: 14)),
                    ),
                    title: Text(pupil['name'] as String, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('Class: ${pupil['class']}', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      _viewPupilResults(pupil);
                    },
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Feature coming soon!'), backgroundColor: AppColors.info, duration: const Duration(seconds: 1)),
    );
  }

  void _showTransactionHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Transaction history coming soon'), backgroundColor: AppColors.warning, duration: const Duration(seconds: 1)),
    );
  }

  void _showAllNews(ResponsiveInfo resp) {
    final isSmallScreen = resp.isMobile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: Column(
            children: [
              const Text('All News', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 16),
              Expanded(
                child: _news.isEmpty
                    ? const Center(child: Text('No news available'))
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: _news.length,
                  itemBuilder: (context, index) {
                    final item = _news[index];
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(item['title'], style: const TextStyle(fontSize: 13)),
                        subtitle: Text(item['date'], style: const TextStyle(fontSize: 11)),
                        onTap: () => _showNewsDetails(item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewsDetails(Map<String, dynamic> news) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(news['title'], style: const TextStyle(color: AppColors.primary, fontSize: 16)),
        content: SingleChildScrollView(child: Text(news['content'], style: const TextStyle(fontSize: 13))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showFundWalletDialog() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fund Wallet', style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send payment to:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradientLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Account Name', _accountName.isNotEmpty ? _accountName : 'N/A', isSmallScreen: isSmallScreen),
                  _buildDetailRow('Account Number', _accountNumber.isNotEmpty ? _accountNumber : 'N/A', isSmallScreen: isSmallScreen),
                  _buildDetailRow('Bank Name', _bankName.isNotEmpty ? _bankName : 'N/A', isSmallScreen: isSmallScreen),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Make a transfer to the above account. Your wallet will be credited automatically.',
              style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              String accountDetails = '''
Account Name: ${_accountName.isNotEmpty ? _accountName : 'N/A'}
Account Number: ${_accountNumber.isNotEmpty ? _accountNumber : 'N/A'}
Bank Name: ${_bankName.isNotEmpty ? _bankName : 'N/A'}
''';
              Clipboard.setData(ClipboardData(text: accountDetails));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account details copied!'), backgroundColor: AppColors.success));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Copy Details'),
          ),
        ],
      ),
    );
  }

  void _showLoanRequestDialog() {
    _showComingSoon();
  }

  void _showWithdrawDialog() {
    _showComingSoon();
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

  // ==================== CORE BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    final resp = ResponsiveInfo(screenWidth);

    return Scaffold(
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _errorMessage != null
              ? _buildErrorView(isMobile)
              : RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _selectedIndex == 0
                ? _buildHomeScreen(resp)
                : _buildScreenForIndex(_selectedIndex, resp),
          ),
        ),
      ),
      bottomNavigationBar: _isLoading || _errorMessage != null ? null : _buildBottomNavigationBar(resp),
    );
  }

  Widget _buildErrorView(bool isMobile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: AppColors.textSecondary, fontSize: isMobile ? 14 : 16), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchDashboardData,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(ResponsiveInfo resp) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16)],
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
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.school_rounded), label: 'Pupils'),
          const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
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
                          fontSize: 9,
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

  Widget _buildHomeScreen(ResponsiveInfo resp) {
    final isMobile = resp.isMobile;
    final statsColumns = isMobile ? 2 : (resp.isTablet ? 3 : 4);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(resp),
          const SizedBox(height: 12),
          _buildCarousel(resp),
          const SizedBox(height: 12),
          _buildStatsGrid(resp, statsColumns),
          const SizedBox(height: 12),
          _buildSectionTitle('My Children', 'View All', resp),
          const SizedBox(height: 8),
          _buildPupilsList(resp),
          const SizedBox(height: 12),
          _buildSectionTitle('Quick Actions', null, resp),
          const SizedBox(height: 8),
          _buildQuickActions(resp),
          const SizedBox(height: 12),
          _buildSectionTitle('Assignments', _assignments.isNotEmpty ? 'View All' : null, resp),
          const SizedBox(height: 8),
          _buildAssignmentsPreview(resp),
          const SizedBox(height: 12),
          _buildSectionTitle('News & Events', null, resp),
          const SizedBox(height: 8),
          _buildNewsAndEvents(resp),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader(ResponsiveInfo resp) {
    final isMobile = resp.isMobile;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: TextStyle(color: AppColors.textSecondary, fontSize: resp.smallTextSize)),
              const SizedBox(height: 2),
              Text(
                _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: resp.titleSize,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _currentUser.schoolName,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: resp.captionSize,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Stack(
          children: [
            GestureDetector(
              onTap: () => setState(() => _selectedIndex = 4),
              child: Container(
                width: resp.avatarSize,
                height: resp.avatarSize,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                ),
                child: Center(
                  child: Icon(Icons.message, size: resp.iconSize, color: AppColors.white),
                ),
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
                      fontSize: 11,
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

  Widget _buildStatsGrid(ResponsiveInfo resp, int crossAxisCount) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: resp.gridSpacing,
      crossAxisSpacing: resp.gridSpacing,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard('Pupils', '${_pupils.length}', Icons.people, AppColors.primary, resp),
        _buildStatCard('Assignments', '${_assignments.length}', Icons.assignment, AppColors.info, resp),
        _buildStatCard('Loans', _activeLoans > 0 ? '₦${_loanBalance.toStringAsFixed(0)}' : '₦0', Icons.credit_card, AppColors.warning, resp),
        _buildStatCard('HMO', 'Active', Icons.health_and_safety, AppColors.success, resp),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ResponsiveInfo resp) {
    return Container(
      padding: EdgeInsets.all(resp.isMobile ? 8 : 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: resp.iconSize, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: resp.valueSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String? action, ResponsiveInfo resp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: resp.sectionTitleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: () {
                if (title == 'Assignments') {
                  _showViewAssignmentsScreen();
                } else if (title == 'My Children') {
                  setState(() => _selectedIndex = 1);
                }
              },
              child: Text(
                action,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: resp.smallTextSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPupilsList(ResponsiveInfo resp) {
    if (_pupils.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('No wards found', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: resp.padding, vertical: resp.isMobile ? 6 : 8),
          child: TextField(
            controller: _searchController,
            onChanged: _filterPupils,
            decoration: InputDecoration(
              hintText: 'Search by name, class, or teacher...',
              hintStyle: TextStyle(fontSize: resp.smallTextSize, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: resp.iconSize),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: resp.smallIconSize),
                onPressed: () {
                  _searchController.clear();
                  _filterPupils('');
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: AppColors.greyLight,
              contentPadding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10, horizontal: 12),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding: EdgeInsets.symmetric(horizontal: resp.padding, vertical: 6),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                fontSize: resp.smallTextSize,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradientLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _isSearchingPupils ? _filteredPupils.length : (_pupils.length > 3 ? 3 : _pupils.length),
            separatorBuilder: (context, index) => Divider(height: 0.5, color: AppColors.greyLight),
            itemBuilder: (context, index) {
              final pupil = _isSearchingPupils ? _filteredPupils[index] : _pupils[index];
              return _buildPupilTile(pupil, resp);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPupilTile(Map<String, dynamic> pupil, ResponsiveInfo resp) {
    final hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'] != 'Not available' &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'].toString().isNotEmpty;
    final feeAmount = pupil['feeAmount'] as double? ?? 0.0;
    final hasFee = feeAmount > 0;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: resp.isMobile ? 6 : 8),
      leading: CircleAvatar(
        radius: resp.isMobile ? 18 : 22,
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text(
          (pupil['name'] as String)[0].toUpperCase(),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: resp.avatarTextSize,
          ),
        ),
      ),
      title: Text(
        pupil['name'] as String,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: resp.bodyTextSize,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pupil['class'] as String,
            style: TextStyle(
              fontSize: resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'Fee: ₦${feeAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: resp.smallCaptionSize,
              color: hasFee ? AppColors.primary : AppColors.grey,
              fontWeight: hasFee ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          Text(
            'Teacher: ${pupil['teacherName']}',
            style: TextStyle(
              fontSize: resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasFee)
            IconButton(
              icon: Icon(Icons.payment, color: AppColors.primary, size: resp.smallIconSize),
              onPressed: () => _payFeesForPupil(pupil),
              tooltip: 'Pay Fees',
            ),
          if (hasPhone)
            IconButton(
              icon: Icon(Icons.phone, color: AppColors.success, size: resp.smallIconSize),
              onPressed: () => _makePhoneCall(pupil['teacherPhone']),
              tooltip: 'Call Teacher',
            ),
          IconButton(
            icon: Icon(Icons.message, color: AppColors.primary, size: resp.smallIconSize),
            onPressed: () => _startConversationWithTeacher(pupil),
            tooltip: 'Message Teacher',
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: AppColors.primary, size: resp.smallIconSize),
            onPressed: () => _showPupilDetails(pupil),
            tooltip: 'Details',
          ),
          IconButton(
            icon: Icon(Icons.discount_rounded, color: AppColors.warning, size: resp.smallIconSize),
            onPressed: () => _showStudentDiscounts(pupil),
            tooltip: 'View Discounts',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ResponsiveInfo resp) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: resp.quickActionsColumns,
      mainAxisSpacing: resp.gridSpacing,
      crossAxisSpacing: resp.gridSpacing,
      childAspectRatio: 1,
      children: [
        _buildActionTile(Icons.payments, 'Fees', () => _showFeesScreen(), resp),
        _buildActionTile(Icons.grade, 'Results', () => _showResultsScreen(), resp),
        _buildActionTile(Icons.health_and_safety, 'HMO', () => _showHMOScreen(), resp),
        _buildActionTile(Icons.discount_rounded, 'Discounts', () => _showDiscountsScreen(), resp),
        _buildActionTile(Icons.message, 'Messages', _navigateToMessages, resp),
        _buildActionTile(Icons.history, 'History', () => _showTransactionHistory(), resp),
      ],
    );
  }

  void _showDiscountsScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning),
      );
      return;
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Student Discounts',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: isSmallScreen ? 20 : 24),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<DiscountProvider>(
                  builder: (context, discountProvider, child) {
                    if (discountProvider.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                    }

                    final hasAnyDiscounts = _pupils.any((pupil) {
                      final studentId = pupil['id']?.toString() ?? '';
                      return discountProvider.discounts
                          .any((d) => d.studentId == studentId);
                    });

                    if (!hasAnyDiscounts) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.discount_rounded,
                              size: isSmallScreen ? 48 : 64,
                              color: AppColors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No discounts available',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 14 : 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No student discounts have been applied yet',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: _pupils.length,
                      itemBuilder: (context, index) {
                        final pupil = _pupils[index];
                        final studentId = pupil['id']?.toString() ?? '';
                        final pupilDiscounts = discountProvider.discounts
                            .where((d) => d.studentId == studentId)
                            .toList();

                        return _buildStudentDiscountCard(
                          pupil: pupil,
                          discounts: pupilDiscounts,
                          isSmallScreen: isSmallScreen,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentDiscountCard({
    required Map<String, dynamic> pupil,
    required List<DiscountModel> discounts,
    required bool isSmallScreen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: discounts.isNotEmpty ? AppColors.primary.withOpacity(0.3) : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isSmallScreen ? 18 : 22,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  pupil['name'][0].toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 14 : 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pupil['name'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 14 : 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      pupil['class'],
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Admission: ${pupil['admissionNo']}',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: discounts.isEmpty ? Colors.grey[200] : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  discounts.isEmpty ? 'No Discount' : '${discounts.length} Discount${discounts.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: discounts.isEmpty ? Colors.grey[600] : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          if (discounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...discounts.map((discount) => _buildDiscountItem(discount, isSmallScreen)),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountItem(DiscountModel discount, bool isSmallScreen) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
      decoration: BoxDecoration(
        color: discount.isValid ? AppColors.primary.withOpacity(0.05) : AppColors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: discount.isValid ? AppColors.primary.withOpacity(0.2) : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: discount.isValid ? AppColors.primary.withOpacity(0.1) : AppColors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              discount.isValid ? Icons.check_circle : Icons.cancel,
              size: isSmallScreen ? 16 : 18,
              color: discount.isValid ? AppColors.success : AppColors.grey,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discount.discountType ?? 'Discount',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmallScreen ? 12 : 13,
                    color: discount.isValid ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                if (discount.description != null)
                  Text(
                    discount.description!,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  children: [
                    if (discount.percentage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          discount.formattedPercentage,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (discount.percentage != null && discount.amount != null)
                      const SizedBox(width: 6),
                    if (discount.amount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          discount.formattedAmount,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: discount.statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        discount.statusText,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 9 : 10,
                          color: discount.statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap, ResponsiveInfo resp) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: resp.iconSize, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: resp.actionLabelSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsPreview(ResponsiveInfo resp) {
    if (_isLoadingAssignments) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_assignments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.assignment_turned_in, size: 40, color: AppColors.grey),
            const SizedBox(height: 8),
            Text(
              'No assignments yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: resp.bodyTextSize),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _assignments.length > 2 ? 2 : _assignments.length,
        separatorBuilder: (context, index) => Divider(height: 0.5, color: AppColors.greyLight),
        itemBuilder: (context, index) {
          final assignment = _assignments[index];
          return _buildAssignmentCard(assignment, resp.isMobile);
        },
      ),
    );
  }

  Widget _buildNewsAndEvents(ResponsiveInfo resp) {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_news.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('No news available', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _news.length > 2 ? 2 : _news.length,
        separatorBuilder: (context, index) => Divider(height: 0.5, color: AppColors.greyLight),
        itemBuilder: (context, index) {
          final item = _news[index];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: resp.isMobile ? 6 : 8),
            leading: CircleAvatar(
              radius: resp.isMobile ? 16 : 18,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Icon(Icons.newspaper, color: AppColors.primary, size: resp.smallIconSize),
            ),
            title: Text(
              item['title'],
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: resp.smallTextSize,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item['date'],
              style: TextStyle(
                fontSize: resp.smallCaptionSize,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: resp.smallIconSize, color: AppColors.primary),
            onTap: () => _showNewsDetails(item),
          );
        },
      ),
    );
  }

  Widget _buildScreenForIndex(int index, ResponsiveInfo resp) {
    switch (index) {
      case 1:
        return _buildPupilsScreen(resp);
      case 2:
        return _buildWalletScreen(resp);
      case 3:
        return _buildProfileScreen(resp);
      case 4:
        return _buildMessagesScreen(resp);
      case 5:
        return _buildMoreScreen(resp);
      default:
        return _buildHomeScreen(resp);
    }
  }

  Widget _buildPupilsScreen(ResponsiveInfo resp) {
    if (_pupils.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_rounded, size: 64, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text('No children found'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(resp.padding),
          color: AppColors.white,
          child: TextField(
            controller: _searchController,
            onChanged: _filterPupils,
            decoration: InputDecoration(
              hintText: 'Search by name, class, or teacher...',
              hintStyle: TextStyle(fontSize: resp.smallTextSize, color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search, color: AppColors.primary, size: resp.iconSize),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: resp.smallIconSize),
                onPressed: () {
                  _searchController.clear();
                  _filterPupils('');
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: AppColors.greyLight,
              contentPadding: EdgeInsets.symmetric(vertical: resp.isMobile ? 8 : 10, horizontal: 12),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding: EdgeInsets.symmetric(horizontal: resp.padding, vertical: 6),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                fontSize: resp.smallTextSize,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: _isSearchingPupils && _filteredPupils.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text('No children found', style: TextStyle(fontSize: resp.bodyTextSize, color: AppColors.textSecondary)),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(resp.padding),
              itemCount: _isSearchingPupils ? _filteredPupils.length : _pupils.length,
              itemBuilder: (context, index) {
                final pupil = _isSearchingPupils ? _filteredPupils[index] : _pupils[index];
                return _buildDetailedPupilCard(pupil, resp);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedPupilCard(Map<String, dynamic> pupil, ResponsiveInfo resp) {
    final hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'] != 'Not available' &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'].toString().isNotEmpty;
    final feeAmount = pupil['feeAmount'] as double? ?? 0.0;
    final hasFee = feeAmount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(resp.cardPadding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: resp.avatarSize,
                height: resp.avatarSize,
                decoration: BoxDecoration(gradient: AppColors.cardGradient, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    (pupil['name'] as String)[0],
                    style: TextStyle(
                      fontSize: resp.avatarTextSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pupil['name'],
                      style: TextStyle(
                        fontSize: resp.bodyTextSize,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Admission: ${pupil['admissionNo']}',
                      style: TextStyle(
                        fontSize: resp.smallCaptionSize,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Class: ${pupil['class']}',
                      style: TextStyle(
                        fontSize: resp.smallCaptionSize,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.money_rounded,
                          size: 12,
                          color: hasFee ? AppColors.primary : AppColors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasFee ? 'Fee: ₦${feeAmount.toStringAsFixed(2)}' : 'Fee: Not Set',
                          style: TextStyle(
                            fontSize: resp.smallCaptionSize,
                            color: hasFee ? AppColors.primary : AppColors.grey,
                            fontWeight: hasFee ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasPhone)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.phone, color: Colors.white, size: resp.smallIconSize),
                    onPressed: () => _makePhoneCall(pupil['teacherPhone']),
                    tooltip: 'Call Teacher',
                  ),
                ),
              IconButton(
                icon: Icon(Icons.message, color: AppColors.primary, size: resp.smallIconSize),
                onPressed: () => _startConversationWithTeacher(pupil),
                tooltip: 'Message Teacher',
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: AppColors.primary, size: resp.smallIconSize),
                onPressed: () => _showPupilDetails(pupil),
                tooltip: 'Details',
              ),
              IconButton(
                icon: Icon(Icons.discount_rounded, color: AppColors.warning, size: resp.smallIconSize),
                onPressed: () => _showStudentDiscounts(pupil),
                tooltip: 'View Discounts',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(resp.isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Class Teacher', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pupil['teacherName'],
                        style: TextStyle(fontSize: resp.smallTextSize, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.phone, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pupil['teacherPhone'],
                        style: TextStyle(fontSize: resp.smallTextSize, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.email, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pupil['teacherEmail'],
                        style: TextStyle(fontSize: resp.smallTextSize, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (hasFee)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _payFeesForPupil(pupil),
                    icon: Icon(Icons.payment, size: resp.smallIconSize),
                    label: Text('Pay Fee', style: TextStyle(fontSize: resp.buttonTextSize)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 6 : 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              if (!hasFee)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _payFeesForPupil(pupil),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 6 : 8),
                      side: const BorderSide(color: AppColors.warning),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Check Fee', style: TextStyle(fontSize: resp.buttonTextSize, color: AppColors.warning)),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoadingResult ? null : () => _viewPupilResults(pupil),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 6 : 8),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoadingResult
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : Text('View Result', style: TextStyle(fontSize: resp.buttonTextSize, color: AppColors.primary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showStudentDiscounts(pupil),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 6 : 8),
                side: const BorderSide(color: AppColors.warning),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(Icons.discount_rounded, color: AppColors.warning, size: resp.smallIconSize),
              label: Text(
                'View Discounts',
                style: TextStyle(
                  fontSize: resp.buttonTextSize,
                  color: AppColors.warning,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesScreen(ResponsiveInfo resp) {
    return const MessagesScreen();
  }

  Widget _buildWalletScreen(ResponsiveInfo resp) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Wallet', style: TextStyle(fontSize: resp.pageTitleSize, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
            ),
            child: Column(
              children: [
                const Text('Available Balance', style: TextStyle(fontSize: 13, color: AppColors.white)),
                const SizedBox(height: 8),
                Text(
                  '₦${_walletBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: resp.largeValueSize,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showFundWalletDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.symmetric(vertical: resp.buttonVerticalPadding),
                        ),
                        child: Text(resp.isMobile ? 'Fund' : 'Fund Wallet', style: TextStyle(fontSize: resp.buttonTextSize)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showWithdrawDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: AppColors.white),
                          padding: EdgeInsets.symmetric(vertical: resp.buttonVerticalPadding),
                        ),
                        child: Text(resp.isMobile ? 'Withdraw' : 'Withdraw', style: TextStyle(fontSize: resp.buttonTextSize)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 10),
                _buildDetailRow('Account Name', _accountName.isNotEmpty ? _accountName : 'N/A', isSmallScreen: resp.isMobile),
                _buildDetailRow('Account Number', _accountNumber.isNotEmpty ? _accountNumber : 'N/A', isSmallScreen: resp.isMobile),
                _buildDetailRow('Bank Name', _bankName.isNotEmpty ? _bankName : 'N/A', isSmallScreen: resp.isMobile),
                _buildDetailRow('Ledger Balance', '₦${_ledgerBalance.toStringAsFixed(2)}', isSmallScreen: resp.isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileScreen(ResponsiveInfo resp) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: resp.avatarLargeSize,
            height: resp.avatarLargeSize,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
            ),
            child: Center(
              child: Text(
                _currentUser.name.isNotEmpty ? _currentUser.name[0].toUpperCase() : 'G',
                style: TextStyle(
                  fontSize: resp.avatarLargeTextSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
            style: TextStyle(fontSize: resp.titleSize, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 20),
          Container(
            padding: EdgeInsets.all(resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personal Information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 12),
                _buildProfileRow(Icons.person, 'Full Name', _currentUser.name.isNotEmpty ? _currentUser.name : 'N/A', resp),
                _buildProfileRow(Icons.email, 'Email', _currentUser.email, resp),
                _buildProfileRow(Icons.phone, 'Phone', _currentUser.phone ?? 'N/A', resp),
                const SizedBox(height: 12),
                const Text('School Information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 12),
                _buildProfileRow(Icons.school, 'School', _currentUser.schoolName, resp),
                _buildProfileRow(Icons.calendar_today, 'Session', _currentUser.sessionId, resp),
                _buildProfileRow(Icons.book, 'Term', _currentUser.term, resp),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value, ResponsiveInfo resp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: resp.smallIconSize, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: resp.smallCaptionSize,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: resp.smallTextSize,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreScreen(ResponsiveInfo resp) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('More Options', style: TextStyle(fontSize: resp.pageTitleSize, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMoreOption(Icons.assignment, 'All Assignments', 'View all assignments', _showViewAssignmentsScreen, resp),
                _buildMoreOption(Icons.discount_rounded, 'Student Discounts', 'View all student discounts', _showDiscountsScreen, resp),
                _buildMoreOption(Icons.message, 'Messages', 'View all messages', _navigateToMessages, resp),
                _buildMoreOption(Icons.newspaper, 'All News', 'View all news', () => _showAllNews(resp), resp),
                _buildMoreOption(Icons.help, 'Help & Support', 'Get assistance', _showComingSoon, resp),
                _buildMoreOption(Icons.logout, 'Logout', 'Sign out', _showLogoutDialog, resp, isDestructive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreOption(IconData icon, String title, String subtitle, VoidCallback onTap, ResponsiveInfo resp, {bool isDestructive = false}) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: resp.isMobile ? 6 : 8),
      leading: Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary, size: resp.iconSize),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
          fontSize: resp.bodyTextSize,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: resp.smallTextSize,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: Icon(Icons.arrow_forward_ios, size: resp.smallIconSize, color: AppColors.primary),
      onTap: onTap,
    );
  }
}

// Helper class for responsive sizing
class ResponsiveInfo {
  final double screenWidth;

  ResponsiveInfo(this.screenWidth);

  bool get isMobile => screenWidth < 600;
  bool get isTablet => screenWidth >= 600 && screenWidth < 1200;
  bool get isDesktop => screenWidth >= 1200;

  double get padding => isMobile ? 12 : isTablet ? 16 : 20;
  double get cardPadding => isMobile ? 10 : isTablet ? 12 : 16;
  double get gridSpacing => isMobile ? 8 : 12;

  int get statsGridColumns => isMobile ? 2 : (isTablet ? 3 : 4);
  int get quickActionsColumns => isMobile ? 4 : (isTablet ? 5 : 6);
  double get statsAspectRatio => isMobile ? 1.4 : 1.3;
  double get actionAspectRatio => isMobile ? 1 : 0.9;

  double get titleSize => isMobile ? 20 : (isTablet ? 24 : 28);
  double get pageTitleSize => isMobile ? 24 : (isTablet ? 28 : 32);
  double get sectionTitleSize => isMobile ? 16 : (isTablet ? 18 : 20);
  double get bodyTextSize => isMobile ? 13 : (isTablet ? 14 : 15);
  double get smallTextSize => isMobile ? 11 : (isTablet ? 12 : 13);
  double get captionSize => isMobile ? 10 : (isTablet ? 11 : 12);
  double get smallCaptionSize => isMobile ? 9 : (isTablet ? 10 : 11);
  double get valueSize => isMobile ? 14 : (isTablet ? 16 : 18);
  double get largeValueSize => isMobile ? 28 : (isTablet ? 32 : 36);

  double get iconSize => isMobile ? 20 : (isTablet ? 22 : 24);
  double get smallIconSize => isMobile ? 16 : (isTablet ? 18 : 20);

  double get avatarSize => isMobile ? 40 : (isTablet ? 45 : 50);
  double get avatarLargeSize => isMobile ? 80 : (isTablet ? 90 : 100);
  double get avatarTextSize => isMobile ? 16 : (isTablet ? 18 : 20);
  double get avatarLargeTextSize => isMobile ? 32 : (isTablet ? 36 : 40);

  double get buttonTextSize => isMobile ? 11 : (isTablet ? 12 : 13);
  double get buttonVerticalPadding => isMobile ? 8 : (isTablet ? 10 : 12);
  double get actionLabelSize => isMobile ? 9 : (isTablet ? 10 : 11);
}