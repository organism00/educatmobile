import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../models/result_model.dart';
import '../models/discount_model.dart';
import '../models/loan_application.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/discount_provider.dart';
import '../services/fee_provider.dart';
import '../services/loan_provider.dart';
import '../utils/app_colors.dart';
import '../screens/conversation_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/student_discount_screen.dart';
import '../screens/fee_payment_screen.dart';
import '../screens/loan_request_screen.dart';
import '../screens/assessment_status_screen.dart';
import '../screens/loan_application_screen.dart';
import 'login_screen.dart';

class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({super.key});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _selectedIndex = 0;
  late UserModel _currentUser;
  late ApiService _apiService;
  late LoanProvider _loanProvider;

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

  // Other fees data
  List<Map<String, dynamic>> _otherFees = [];
  double _totalOtherFees = 0.0;
  bool _isLoadingOtherFees = false;
  String? _otherFeesErrorMessage;

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchingPupils = false;

  // Cached responsive values
  late ResponsiveInfo _resp;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loanProvider = LoanProvider();
    _loadUserData();
    _fetchDashboardData();
    _fetchNews();
    _fetchUnreadMessages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _resp = ResponsiveInfo(MediaQuery.of(context).size.width);
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _loanProvider.clear();
    super.dispose();
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
      userRole: 'Guardian',
    );

    if (result['success'] && mounted) {
      final messages = result['data'] as List? ?? [];
      final unreadCount = messages.where((m) => m['isRead'] == false).length;
      if (mounted) {
        setState(() {
          _unreadMessageCount = unreadCount;
        });
      }
    }
  }

  String _getCurrentSessionId() {
    String sessionId = _currentUser.sessionId ?? '';
    if (sessionId.isEmpty) {
      final now = DateTime.now();
      final year = now.year;
      final nextYear = year + 1;
      sessionId = '$year/$nextYear';
    }
    return sessionId;
  }

  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Not authenticated';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final studentsResult = await _apiService.getGuardianStudents(
        token: token,
        guardianId: _currentUser.id,
      ).timeout(const Duration(seconds: 30));

      if (studentsResult['success'] && mounted) {
        final studentsData = studentsResult['data'] as List? ?? [];
        final List<Map<String, dynamic>> mappedPupils = [];
        final String sessionId = _getCurrentSessionId();

        for (var student in studentsData) {
          final teacher = student['teacher'];
          final classroom = student['classroom'];
          final studentId = student['studentId'] ?? '';
          final classroomId = student['classroomId'] ?? '';

          double feeAmount = 0.0;

          if (student['fee'] != null) {
            feeAmount = (student['fee'] as num?)?.toDouble() ?? 0.0;
          } else if (classroom != null) {
            feeAmount = (classroom['fee'] as num?)?.toDouble() ??
                (classroom['amount'] as num?)?.toDouble() ??
                (classroom['feeAmount'] as num?)?.toDouble() ??
                (classroom['schoolFee'] as num?)?.toDouble() ??
                0.0;
          }

          if (feeAmount == 0.0 && classroomId.isNotEmpty && token != null && sessionId.isNotEmpty) {
            try {
              final feeResult = await _apiService.getClassFeeForTerm(
                token: token,
                classId: classroomId,
                sessionId: sessionId,
              );
              if (feeResult['success'] && feeResult['fee'] > 0) {
                feeAmount = feeResult['fee'];
              }
            } catch (e) {
              // Silent fail
            }
          }

          if (feeAmount == 0.0 && studentId.isNotEmpty && token != null && sessionId.isNotEmpty) {
            try {
              final feeResult = await _apiService.getStudentFee(
                token: token,
                studentId: studentId,
                sessionId: sessionId,
              );
              if (feeResult['success'] && feeResult['fee'] > 0) {
                feeAmount = feeResult['fee'];
              }
            } catch (e) {
              // Silent fail
            }
          }

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

        if (mounted) {
          setState(() {
            _pupils = mappedPupils;
            _filteredPupils = List.from(mappedPupils);
          });
        }

        await _fetchWalletAndAccount(token);
        await _fetchLoanData(token);
        await _fetchAssignments(token);
        await _fetchLoanApplications(token);
        _fetchDiscountsForAllPupils(token);

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
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error. Please check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchLoanApplications(String token) async {
    await _loanProvider.fetchApplications(
      token: token,
      guardianId: _currentUser.id,
    );
  }

  void _fetchDiscountsForAllPupils(String token) {
    try {
      final discountProvider = Provider.of<DiscountProvider>(context, listen: false);
      if (_pupils.isEmpty) return;
      discountProvider.fetchDiscountsForAllPupils(
        token: token,
        pupils: _pupils,
      );
    } catch (e) {
      // Silent fail
    }
  }

  void _filterPupils(String query) {
    setState(() {
      _isSearchingPupils = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredPupils = List.from(_pupils);
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredPupils = _pupils.where((pupil) {
          final name = pupil['name'].toString().toLowerCase();
          final className = pupil['class'].toString().toLowerCase();
          final teacherName = pupil['teacherName'].toString().toLowerCase();
          return name.contains(lowerQuery) ||
              className.contains(lowerQuery) ||
              teacherName.contains(lowerQuery);
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
      // Silent fail
    }
  }

  Future<void> _fetchLoanData(String token) async {
    setState(() {
      _isLoadingLoan = true;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _loanBalance = 0.00;
        _activeLoans = 0;
        _isLoadingLoan = false;
      });
    }
  }

  Future<void> _fetchAssignments(String token) async {
    if (_pupils.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingAssignments = false;
        });
      }
      return;
    }

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
            final className = pupil['class'] ?? 'N/A';
            for (var assignment in assignments) {
              assignment['className'] = className;
            }
            allAssignments.addAll(assignments);
          }
        } catch (e) {
          // Silent fail
        }
      }
    }

    if (mounted) {
      setState(() {
        _assignments = allAssignments;
        _isLoadingAssignments = false;
      });
    }
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
          final newsData = (newsResult['data'] as List?)?.map((item) => ({
            'id': item['id'],
            'title': item['title'],
            'content': item['content'],
            'date': _formatDate(item['date']),
          })).toList() ?? [];
          setState(() {
            _news = newsData;
            _isLoadingNews = false;
          });
        } else {
          setState(() {
            _isLoadingNews = false;
          });
        }
      } catch (e) {
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
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  // ==================== FEE PAYMENT METHODS ====================

  Future<void> _payFeesForPupil(Map<String, dynamic> pupil) async {
    final studentId = pupil['id']?.toString();
    final classroomId = pupil['classroomId']?.toString();
    final studentName = pupil['name'] ?? 'Student';
    final studentClass = pupil['class'] ?? 'N/A';

    double feeAmount = pupil['feeAmount'] as double? ?? 0.0;

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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final String sessionId = _getCurrentSessionId();

    try {
      if (token != null && sessionId.isNotEmpty) {
        final feeResult = await _apiService.getClassFeeForTerm(
          token: token,
          classId: classroomId,
          sessionId: sessionId,
        );

        if (feeResult['success'] && feeResult['fee'] > 0) {
          feeAmount = feeResult['fee'];
          setState(() {
            final index = _pupils.indexWhere((p) => p['id'] == studentId);
            if (index != -1) {
              _pupils[index]['feeAmount'] = feeAmount;
              _filteredPupils[index]['feeAmount'] = feeAmount;
            }
          });
        } else {
          final studentFeeResult = await _apiService.getStudentFee(
            token: token,
            studentId: studentId,
            sessionId: sessionId,
          );
          if (studentFeeResult['success'] && studentFeeResult['fee'] > 0) {
            feeAmount = studentFeeResult['fee'];
            setState(() {
              final index = _pupils.indexWhere((p) => p['id'] == studentId);
              if (index != -1) {
                _pupils[index]['feeAmount'] = feeAmount;
                _filteredPupils[index]['feeAmount'] = feeAmount;
              }
            });
          }
        }
      }
    } catch (e) {
      print('⚠️ Error fetching fee: $e');
    } finally {
      Navigator.pop(context);
    }

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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

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

  // ==================== OTHER FEES METHODS ====================

  void _showOtherFeesScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning),
      );
      return;
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    _fetchOtherFeesForAllPupils(() {
      Navigator.pop(context);

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
                    Text(
                      'Other Fees',
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
                const SizedBox(height: 8),
                Text(
                  'Additional school fees for your children',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoadingOtherFees
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _otherFeesErrorMessage != null
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(
                          _otherFeesErrorMessage!,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showOtherFeesScreen();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                      : _otherFees.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: isSmallScreen ? 48 : 64,
                          color: AppColors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No other fees found',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'There are no additional fees for your children',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                      : ListView.builder(
                    controller: scrollController,
                    itemCount: _pupils.length,
                    itemBuilder: (context, index) {
                      final pupil = _pupils[index];
                      return _buildPupilOtherFeesCard(pupil, isSmallScreen);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> _fetchOtherFeesForAllPupils(VoidCallback onComplete) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      setState(() {
        _otherFeesErrorMessage = 'Authentication error';
        _isLoadingOtherFees = false;
      });
      onComplete();
      return;
    }

    setState(() {
      _isLoadingOtherFees = true;
      _otherFeesErrorMessage = null;
      _otherFees = [];
      _totalOtherFees = 0.0;
    });

    final Set<String> classroomIds = {};
    for (var pupil in _pupils) {
      final classroomId = pupil['classroomId']?.toString();
      if (classroomId != null && classroomId.isNotEmpty && classroomId != 'N/A') {
        classroomIds.add(classroomId);
      }
    }

    if (classroomIds.isEmpty) {
      setState(() {
        _isLoadingOtherFees = false;
        _otherFeesErrorMessage = 'No classroom IDs available';
      });
      onComplete();
      return;
    }

    List<Map<String, dynamic>> allFees = [];
    double totalAmount = 0.0;

    for (var classroomId in classroomIds) {
      try {
        final result = await _apiService.getOtherFeesByClassroom(
          token: token,
          classroomId: classroomId,
          activeOnly: true,
        );

        if (result['success']) {
          final fees = List<Map<String, dynamic>>.from(result['fees']);
          for (var fee in fees) {
            final pupil = _pupils.firstWhere(
                  (p) => p['classroomId']?.toString() == classroomId,
              orElse: () => {},
            );
            fee['studentName'] = pupil['name'] ?? 'Unknown';
            fee['className'] = pupil['class'] ?? 'N/A';
            fee['studentId'] = pupil['id'] ?? '';
          }
          allFees.addAll(fees);
          totalAmount += result['totalAmount'] ?? 0.0;
        }
      } catch (e) {
        print('Error fetching other fees for classroom $classroomId: $e');
      }
    }

    setState(() {
      _otherFees = allFees;
      _totalOtherFees = totalAmount;
      _isLoadingOtherFees = false;
    });

    onComplete();
  }

  Widget _buildPupilOtherFeesCard(Map<String, dynamic> pupil, bool isSmallScreen) {
    final pupilFees = _otherFees.where((fee) =>
    fee['studentId'] == pupil['id'] ||
        fee['studentName'] == pupil['name']).toList();

    final totalPupilFees = pupilFees.fold(0.0, (sum, fee) => sum + (fee['amount'] as double));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pupilFees.isNotEmpty ? AppColors.primary.withOpacity(0.3) : AppColors.grey.withOpacity(0.2),
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
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: pupilFees.isEmpty ? Colors.grey[200] : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  pupilFees.isEmpty ? 'No Fees' : '₦${totalPupilFees.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: pupilFees.isEmpty ? Colors.grey[600] : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (pupilFees.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...pupilFees.map((fee) => _buildOtherFeeItem(fee, isSmallScreen)),
          ],
        ],
      ),
    );
  }

  Widget _buildOtherFeeItem(Map<String, dynamic> fee, bool isSmallScreen) {
    final isMandatory = fee['isMandatory'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
      decoration: BoxDecoration(
        color: isMandatory ? AppColors.primary.withOpacity(0.05) : AppColors.info.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMandatory ? AppColors.primary.withOpacity(0.2) : AppColors.info.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMandatory ? AppColors.primary.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isMandatory ? Icons.check_circle : Icons.info,
              size: isSmallScreen ? 16 : 18,
              color: isMandatory ? AppColors.primary : AppColors.info,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fee['name'] ?? 'Untitled Fee',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmallScreen ? 12 : 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (fee['description'] != null && fee['description'].toString().isNotEmpty)
                  Text(
                    fee['description'],
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMandatory ? AppColors.primary.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isMandatory ? 'Mandatory' : 'Optional',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 9 : 10,
                          color: isMandatory ? AppColors.primary : AppColors.info,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₦${(fee['amount'] as double).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 12 : 13,
                        color: AppColors.primary,
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

  // ==================== RESULTS METHODS ====================

  Future<void> _viewPupilResults(Map<String, dynamic> pupil) async {
    final classroomId = pupil['classroomId']?.toString();
    if (classroomId == null || classroomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Classroom not assigned'), backgroundColor: AppColors.warning),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'No results available'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  void _showResultDetailsDialog(Map<String, dynamic> pupil, dynamic resultData) {
    final studentResult = StudentResult.fromJson(resultData);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                  ],
                ),
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
                              color: subject.totalScore >= 70 ? AppColors.success : AppColors.warning,
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
                      ]);
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
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

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, bottomSheetSetState) {
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
                            Text(
                              'No hospital records found',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 12 : 13,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
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

  void _navigateToLoanRequest() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoanRequestScreen()),
    );
  }

  void _navigateToLoanApplication(LoanApplication application) {
    // Navigate based on application status
    if (application.status == 2 || application.status == 3) {
      // Assessment pending - show status screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AssessmentStatusScreen(
            applicationId: application.id,
            application: application,
          ),
        ),
      );
    } else if (application.status == 4) {
      // Assessment complete - show loan application
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoanApplicationScreen(
            creditAssessmentId: application.creditAssessmentId ?? '',
            eligibleAmount: application.eligibleAmount ?? 0,
          ),
        ),
      );
    } else {
      // Show details dialog
      _showApplicationDetails(application);
    }
  }

  void _showApplicationDetails(LoanApplication application) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Loan Application Details',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Container(
          width: isSmallScreen ? double.maxFinite : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Application ID', application.id),
              _buildDetailRow('Status', application.statusDisplay),
              if (application.requestedAmount != null)
                _buildDetailRow('Requested Amount', '₦${application.requestedAmount!.toStringAsFixed(2)}'),
              if (application.eligibleAmount != null)
                _buildDetailRow('Eligible Amount', '₦${application.eligibleAmount!.toStringAsFixed(2)}'),
              _buildDetailRow('Created', _formatDate(application.createdAt.toString())),
              _buildDetailRow('Updated', _formatDate(application.updatedAt.toString())),
              if (application.edubanclStatusMessage != null)
                _buildDetailRow('Message', application.edubanclStatusMessage!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (application.status == 2 || application.status == 3)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AssessmentStatusScreen(
                      applicationId: application.id,
                      application: application,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Check Status'),
            ),
          if (application.status == 4)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoanApplicationScreen(
                      creditAssessmentId: application.creditAssessmentId ?? '',
                      eligibleAmount: application.eligibleAmount ?? 0,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Apply Now'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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

  void _showFeesScreen() {
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                      child: Text(
                        (pupil['name'] as String)[0].toUpperCase(),
                        style: const TextStyle(fontSize: 14),
                      ),
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
                      return discountProvider.getDiscountsForStudent(studentId).isNotEmpty;
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
                        final pupilDiscounts = discountProvider.getDiscountsForStudent(studentId);

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
                  discount.discountType,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmallScreen ? 12 : 13,
                    color: discount.isValid ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                if (discount.description.isNotEmpty)
                  Text(
                    discount.description,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  children: [
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

  void _showTransactionHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction history coming soon'),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feature coming soon!'),
        backgroundColor: AppColors.info,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout', style: TextStyle(color: AppColors.error)),
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
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ==================== CORE BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    _resp = ResponsiveInfo(MediaQuery.of(context).size.width);

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
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: _resp.isMobile ? 14 : 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchDashboardData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16),
        ],
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
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.school_rounded),
            label: 'Pupils',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallet',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
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
          const BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  // ==================== HOME SCREEN ====================

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildCarousel(),
          const SizedBox(height: 12),
          _buildStatsGrid(),
          const SizedBox(height: 12),
          _buildSectionTitle('My Children', 'View All'),
          const SizedBox(height: 8),
          _buildPupilsList(),
          const SizedBox(height: 12),
          _buildSectionTitle('Quick Actions', null),
          const SizedBox(height: 8),
          _buildQuickActions(),
          const SizedBox(height: 12),
          _buildLoanApplicationsSection(),
          const SizedBox(height: 12),
          _buildSectionTitle('Assignments', _assignments.isNotEmpty ? 'View All' : null),
          const SizedBox(height: 8),
          _buildAssignmentsPreview(),
          const SizedBox(height: 12),
          _buildSectionTitle('News & Events', null),
          const SizedBox(height: 8),
          _buildNewsAndEvents(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ==================== LOAN APPLICATIONS SECTION ====================

  Widget _buildLoanApplicationsSection() {
    final activeApps = _loanProvider.activeApplications;
    final hasActiveApps = activeApps.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Loan Applications', hasActiveApps ? 'View All' : null),
        const SizedBox(height: 8),
        if (_loanProvider.isLoading)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (activeApps.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.credit_card_off, size: 40, color: AppColors.grey),
                const SizedBox(height: 8),
                Text(
                  'No active loan applications',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: _resp.bodyTextSize,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _navigateToLoanRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply for Loan'),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeApps.length > 2 ? 2 : activeApps.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 0.5, color: AppColors.greyLight),
              itemBuilder: (context, index) {
                final application = activeApps[index];
                return _buildLoanApplicationTile(application);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildLoanApplicationTile(LoanApplication application) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _resp.isMobile ? 6 : 8,
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: application.statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          application.statusIcon,
          color: application.statusColor,
          size: _resp.smallIconSize,
        ),
      ),
      title: Text(
        'Application #${application.id.substring(0, 8)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: _resp.smallTextSize,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status: ${application.statusDisplay}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: application.statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (application.requestedAmount != null)
            Text(
              'Amount: ₦${application.requestedAmount!.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            'Updated: ${_formatDate(application.updatedAt.toString())}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.primary,
        size: _resp.smallIconSize,
      ),
      onTap: () => _navigateToLoanApplication(application),
    );
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 1:
        return _buildPupilsScreen();
      case 2:
        return _buildWalletScreen();
      case 3:
        return _buildProfileScreen();
      case 4:
        return const MessagesScreen();
      case 5:
        return _buildMoreScreen();
      default:
        return _buildHomeScreen();
    }
  }

  // ==================== HEADER ====================

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
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: _resp.smallTextSize,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: _resp.titleSize,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _currentUser.schoolName,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: _resp.captionSize,
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
                width: _resp.avatarSize,
                height: _resp.avatarSize,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.message,
                    size: _resp.iconSize,
                    color: AppColors.white,
                  ),
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

  // ==================== CAROUSEL ====================

  Widget _buildCarousel() {
    final List<Widget> carouselItems = [
      _buildWalletCard(),
      _buildLoanCard(),
    ];

    return Column(
      children: [
        SizedBox(
          height: _resp.isMobile ? 230 : 250,
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

  Widget _buildWalletCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: EdgeInsets.all(_resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
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
                  fontSize: _resp.isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '₦${_walletBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: _resp.isMobile ? 28 : _resp.isTablet ? 34 : 38,
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
                  onPressed: _showComingSoon,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 8 : 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _resp.isMobile ? 'Fund' : 'Fund Wallet',
                    style: TextStyle(fontSize: _resp.isMobile ? 12 : 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _navigateToLoanRequest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 8 : 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _resp.isMobile ? 'Loan' : 'Get Loan',
                    style: TextStyle(fontSize: _resp.isMobile ? 12 : 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard() {
    if (_isLoadingLoan) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.all(_resp.isMobile ? 16 : 20),
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
      padding: EdgeInsets.all(_resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
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
                  fontSize: _resp.isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _activeLoans > 0
                      ? AppColors.warning.withOpacity(0.2)
                      : AppColors.success.withOpacity(0.2),
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
                fontSize: _resp.isMobile ? 28 : _resp.isTablet ? 34 : 38,
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
                  onPressed: _showComingSoon,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 8 : 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Details',
                    style: TextStyle(fontSize: _resp.isMobile ? 12 : 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loanBalance > 0 ? _showComingSoon : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 8 : 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Repay',
                    style: TextStyle(fontSize: _resp.isMobile ? 12 : 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== STATS GRID ====================

  Widget _buildStatsGrid() {
    final crossAxisCount = _resp.isMobile ? 2 : (_resp.isTablet ? 3 : 4);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: _resp.gridSpacing,
      crossAxisSpacing: _resp.gridSpacing,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard('Pupils', '${_pupils.length}', Icons.people, AppColors.primary),
        _buildStatCard('Assignments', '${_assignments.length}', Icons.assignment, AppColors.info),
        _buildStatCard(
          'Loans',
          _activeLoans > 0 ? '₦${_loanBalance.toStringAsFixed(0)}' : '₦0',
          Icons.credit_card,
          AppColors.warning,
        ),
        _buildStatCard('HMO', 'Active', Icons.health_and_safety, AppColors.success),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(_resp.isMobile ? 8 : 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: _resp.iconSize, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: _resp.valueSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==================== SECTION TITLE ====================

  Widget _buildSectionTitle(String title, String? action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: _resp.sectionTitleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: () {
                if (title == 'Assignments') {
                  _showComingSoon();
                } else if (title == 'My Children') {
                  setState(() => _selectedIndex = 1);
                } else if (title == 'Loan Applications') {
                  // Show all applications - could navigate to a list screen
                  _showComingSoon();
                }
              },
              child: Text(
                action,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: _resp.smallTextSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== PUPILS LIST ====================

  Widget _buildPupilsList() {
    if (_pupils.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No wards found',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final displayList = _isSearchingPupils ? _filteredPupils : _pupils;
    final itemCount = _isSearchingPupils ? displayList.length : (displayList.length > 3 ? 3 : displayList.length);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: _resp.padding,
            vertical: _resp.isMobile ? 6 : 8,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _filterPupils,
            decoration: InputDecoration(
              hintText: 'Search by name, class, or teacher...',
              hintStyle: TextStyle(
                fontSize: _resp.smallTextSize,
                color: AppColors.textSecondary,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.primary,
                size: _resp.iconSize,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _resp.smallIconSize),
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
              contentPadding: EdgeInsets.symmetric(
                vertical: _resp.isMobile ? 8 : 10,
                horizontal: 12,
              ),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _resp.padding,
              vertical: 6,
            ),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                fontSize: _resp.smallTextSize,
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
            itemCount: itemCount,
            separatorBuilder: (context, index) =>
                Divider(height: 0.5, color: AppColors.greyLight),
            itemBuilder: (context, index) {
              final pupil = displayList[index];
              return _buildPupilTile(pupil);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPupilTile(Map<String, dynamic> pupil) {
    final hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'] != 'Not available' &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'].toString().isNotEmpty;
    final feeAmount = pupil['feeAmount'] as double? ?? 0.0;
    final hasFee = feeAmount > 0;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _resp.isMobile ? 6 : 8,
      ),
      leading: CircleAvatar(
        radius: _resp.isMobile ? 18 : 22,
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text(
          (pupil['name'] as String)[0].toUpperCase(),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: _resp.avatarTextSize,
          ),
        ),
      ),
      title: Text(
        pupil['name'] as String,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: _resp.bodyTextSize,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pupil['class'] as String,
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'Fee: ₦${feeAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: hasFee ? AppColors.primary : AppColors.grey,
              fontWeight: hasFee ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          Text(
            'Teacher: ${pupil['teacherName']}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhone)
            IconButton(
              icon: Icon(
                Icons.phone,
                color: AppColors.success,
                size: _resp.smallIconSize,
              ),
              onPressed: () => _makePhoneCall(pupil['teacherPhone']),
              tooltip: 'Call Teacher',
            ),
          IconButton(
            icon: Icon(
              Icons.message,
              color: AppColors.primary,
              size: _resp.smallIconSize,
            ),
            onPressed: () => _startConversationWithTeacher(pupil),
            tooltip: 'Message Teacher',
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: AppColors.primary,
              size: _resp.smallIconSize,
            ),
            onPressed: _showComingSoon,
            tooltip: 'Details',
          ),
        ],
      ),
    );
  }

  // ==================== QUICK ACTIONS ====================

  Widget _buildQuickActions() {
    final columns = _resp.isMobile ? 4 : (_resp.isTablet ? 5 : 6);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: _resp.gridSpacing,
      crossAxisSpacing: _resp.gridSpacing,
      childAspectRatio: 1,
      children: [
        _buildActionTile(Icons.payments, 'Fees', _showFeesScreen),
        _buildActionTile(Icons.grade, 'Results', _showResultsScreen),
        _buildActionTile(Icons.health_and_safety, 'HMO', _showHMOScreen),
        _buildActionTile(Icons.discount_rounded, 'Discounts', _showDiscountsScreen),
        _buildActionTile(Icons.receipt_long, 'Other Fees', _showOtherFeesScreen),
        _buildActionTile(Icons.credit_card, 'Request Loan', _navigateToLoanRequest),
        _buildActionTile(Icons.message, 'Messages', _navigateToMessages),
        _buildActionTile(Icons.history, 'History', _showTransactionHistory),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: _resp.isMobile ? 8 : 10),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: _resp.iconSize, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: _resp.actionLabelSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ASSIGNMENTS PREVIEW ====================

  Widget _buildAssignmentsPreview() {
    if (_isLoadingAssignments) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
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
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: _resp.bodyTextSize,
              ),
            ),
          ],
        ),
      );
    }

    final displayCount = _assignments.length > 2 ? 2 : _assignments.length;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: displayCount,
        separatorBuilder: (context, index) =>
            Divider(height: 0.5, color: AppColors.greyLight),
        itemBuilder: (context, index) {
          final assignment = _assignments[index];
          return _buildAssignmentItem(assignment);
        },
      ),
    );
  }

  Widget _buildAssignmentItem(Map<String, dynamic> assignment) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _resp.isMobile ? 6 : 8,
      ),
      leading: Container(
        padding: EdgeInsets.all(_resp.isMobile ? 6 : 8),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppColors.error.withOpacity(0.1)
              : AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.assignment,
          color: isOverdue ? AppColors.error : AppColors.primary,
          size: _resp.smallIconSize,
        ),
      ),
      title: Text(
        assignment['title'] ?? 'Untitled',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: _resp.smallTextSize,
          color: AppColors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Due: ${_formatDate(assignment['dueDate'])}',
        style: TextStyle(
          fontSize: _resp.smallCaptionSize,
          color: isOverdue ? AppColors.error : AppColors.textSecondary,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppColors.error.withOpacity(0.1)
              : AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isOverdue ? 'Overdue' : 'Active',
          style: TextStyle(
            fontSize: _resp.smallCaptionSize,
            color: isOverdue ? AppColors.error : AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: _showComingSoon,
    );
  }

  // ==================== NEWS AND EVENTS ====================

  Widget _buildNewsAndEvents() {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_news.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No news available',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final displayCount = _news.length > 2 ? 2 : _news.length;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: displayCount,
        separatorBuilder: (context, index) =>
            Divider(height: 0.5, color: AppColors.greyLight),
        itemBuilder: (context, index) {
          final item = _news[index];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: _resp.isMobile ? 6 : 8,
            ),
            leading: CircleAvatar(
              radius: _resp.isMobile ? 16 : 18,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Icon(
                Icons.newspaper,
                color: AppColors.primary,
                size: _resp.smallIconSize,
              ),
            ),
            title: Text(
              item['title'],
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: _resp.smallTextSize,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item['date'],
              style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: _resp.smallIconSize,
              color: AppColors.primary,
            ),
            onTap: _showComingSoon,
          );
        },
      ),
    );
  }

  // ==================== PUPILS SCREEN ====================

  Widget _buildPupilsScreen() {
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

    final displayList = _isSearchingPupils ? _filteredPupils : _pupils;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_resp.padding),
          color: AppColors.white,
          child: TextField(
            controller: _searchController,
            onChanged: _filterPupils,
            decoration: InputDecoration(
              hintText: 'Search by name, class, or teacher...',
              hintStyle: TextStyle(
                fontSize: _resp.smallTextSize,
                color: AppColors.textSecondary,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.primary,
                size: _resp.iconSize,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: _resp.smallIconSize),
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
              contentPadding: EdgeInsets.symmetric(
                vertical: _resp.isMobile ? 8 : 10,
                horizontal: 12,
              ),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _resp.padding,
              vertical: 6,
            ),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                fontSize: _resp.smallTextSize,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppColors.primary,
            child: displayList.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 48,
                    color: AppColors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No children found',
                    style: TextStyle(
                      fontSize: _resp.bodyTextSize,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(_resp.padding),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                final pupil = displayList[index];
                return _buildDetailedPupilCard(pupil);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedPupilCard(Map<String, dynamic> pupil) {
    final hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'] != 'Not available' &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'].toString().isNotEmpty;
    final feeAmount = pupil['feeAmount'] as double? ?? 0.0;
    final hasFee = feeAmount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(_resp.cardPadding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: _resp.avatarSize,
                height: _resp.avatarSize,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (pupil['name'] as String)[0],
                    style: TextStyle(
                      fontSize: _resp.avatarTextSize,
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
                        fontSize: _resp.bodyTextSize,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Admission: ${pupil['admissionNo']}',
                      style: TextStyle(
                        fontSize: _resp.smallCaptionSize,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Class: ${pupil['class']}',
                      style: TextStyle(
                        fontSize: _resp.smallCaptionSize,
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
                          hasFee
                              ? 'Fee: ₦${feeAmount.toStringAsFixed(2)}'
                              : 'Fee: Not Set',
                          style: TextStyle(
                            fontSize: _resp.smallCaptionSize,
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
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: _resp.smallIconSize,
                    ),
                    onPressed: () => _makePhoneCall(pupil['teacherPhone']),
                    tooltip: 'Call Teacher',
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.message,
                  color: AppColors.primary,
                  size: _resp.smallIconSize,
                ),
                onPressed: () => _startConversationWithTeacher(pupil),
                tooltip: 'Message Teacher',
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: AppColors.primary,
                  size: _resp.smallIconSize,
                ),
                onPressed: _showComingSoon,
                tooltip: 'Details',
              ),
              IconButton(
                icon: Icon(
                  Icons.discount_rounded,
                  color: AppColors.warning,
                  size: _resp.smallIconSize,
                ),
                onPressed: () => _showStudentDiscounts(pupil),
                tooltip: 'View Discounts',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(_resp.isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Class Teacher',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pupil['teacherName'],
                        style: TextStyle(
                          fontSize: _resp.smallTextSize,
                          color: AppColors.textPrimary,
                        ),
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
                        style: TextStyle(
                          fontSize: _resp.smallTextSize,
                          color: AppColors.textPrimary,
                        ),
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
                        style: TextStyle(
                          fontSize: _resp.smallTextSize,
                          color: AppColors.textPrimary,
                        ),
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
                    icon: Icon(Icons.payment, size: _resp.smallIconSize),
                    label: Text(
                      'Pay Fee',
                      style: TextStyle(fontSize: _resp.buttonTextSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 6 : 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              if (!hasFee)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _payFeesForPupil(pupil),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 6 : 8,
                      ),
                      side: const BorderSide(color: AppColors.warning),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Check Fee',
                      style: TextStyle(
                        fontSize: _resp.buttonTextSize,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoadingResult ? null : () => _viewPupilResults(pupil),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 6 : 8,
                    ),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoadingResult
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                      : Text(
                    'View Result',
                    style: TextStyle(
                      fontSize: _resp.buttonTextSize,
                      color: AppColors.primary,
                    ),
                  ),
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
                padding: EdgeInsets.symmetric(
                  vertical: _resp.isMobile ? 6 : 8,
                ),
                side: const BorderSide(color: AppColors.warning),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(
                Icons.discount_rounded,
                color: AppColors.warning,
                size: _resp.smallIconSize,
              ),
              label: Text(
                'View Discounts',
                style: TextStyle(
                  fontSize: _resp.buttonTextSize,
                  color: AppColors.warning,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== WALLET SCREEN ====================

  Widget _buildWalletScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Wallet',
            style: TextStyle(
              fontSize: _resp.pageTitleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(_resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Available Balance',
                  style: TextStyle(fontSize: 13, color: AppColors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  '₦${_walletBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: _resp.largeValueSize,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showComingSoon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.symmetric(
                            vertical: _resp.buttonVerticalPadding,
                          ),
                        ),
                        child: Text(
                          _resp.isMobile ? 'Fund' : 'Fund Wallet',
                          style: TextStyle(fontSize: _resp.buttonTextSize),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showComingSoon,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: AppColors.white),
                          padding: EdgeInsets.symmetric(
                            vertical: _resp.buttonVerticalPadding,
                          ),
                        ),
                        child: Text(
                          _resp.isMobile ? 'Withdraw' : 'Withdraw',
                          style: TextStyle(fontSize: _resp.buttonTextSize),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(_resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account Details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                _buildInfoRow('Account Name', _accountName.isNotEmpty ? _accountName : 'N/A'),
                _buildInfoRow('Account Number', _accountNumber.isNotEmpty ? _accountNumber : 'N/A'),
                _buildInfoRow('Bank Name', _bankName.isNotEmpty ? _bankName : 'N/A'),
                _buildInfoRow('Ledger Balance', '₦${_ledgerBalance.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: _resp.smallTextSize,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: _resp.smallTextSize,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==================== PROFILE SCREEN ====================

  Widget _buildProfileScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: _resp.avatarLargeSize,
            height: _resp.avatarLargeSize,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _currentUser.name.isNotEmpty ? _currentUser.name[0].toUpperCase() : 'G',
                style: TextStyle(
                  fontSize: _resp.avatarLargeTextSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
            style: TextStyle(
              fontSize: _resp.titleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: EdgeInsets.all(_resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildProfileRow(Icons.person, 'Full Name', _currentUser.name.isNotEmpty ? _currentUser.name : 'N/A'),
                _buildProfileRow(Icons.email, 'Email', _currentUser.email),
                _buildProfileRow(Icons.phone, 'Phone', _currentUser.phone ?? 'N/A'),
                const SizedBox(height: 12),
                const Text(
                  'School Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildProfileRow(Icons.school, 'School', _currentUser.schoolName),
                _buildProfileRow(Icons.calendar_today, 'Session', _currentUser.sessionId),
                _buildProfileRow(Icons.book, 'Term', _currentUser.term),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: _resp.smallIconSize, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: _resp.smallCaptionSize,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: _resp.smallTextSize,
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

  // ==================== MORE SCREEN ====================

  Widget _buildMoreScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More Options',
            style: TextStyle(
              fontSize: _resp.pageTitleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMoreOption(Icons.payments, 'School Fees', 'Pay school fees', _showFeesScreen),
                _buildMoreOption(Icons.receipt_long, 'Other Fees', 'View additional fees', _showOtherFeesScreen),
                _buildMoreOption(Icons.assignment, 'All Assignments', 'View all assignments', _showComingSoon),
                _buildMoreOption(Icons.discount_rounded, 'Student Discounts', 'View all student discounts', _showDiscountsScreen),
                _buildMoreOption(Icons.message, 'Messages', 'View all messages', _navigateToMessages),
                _buildMoreOption(Icons.newspaper, 'All News', 'View all news', _showComingSoon),
                _buildMoreOption(Icons.credit_card, 'Request Loan', 'Apply for a loan', _navigateToLoanRequest),
                _buildMoreOption(Icons.help, 'Help & Support', 'Get assistance', _showComingSoon),
                _buildMoreOption(Icons.logout, 'Logout', 'Sign out', _showLogoutDialog, isDestructive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreOption(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap, {
        bool isDestructive = false,
      }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _resp.isMobile ? 6 : 8,
      ),
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.primary,
        size: _resp.iconSize,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
          fontSize: _resp.bodyTextSize,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: _resp.smallTextSize,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: _resp.smallIconSize,
        color: AppColors.primary,
      ),
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