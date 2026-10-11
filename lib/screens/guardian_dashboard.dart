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
import '../services/loan_provider.dart';
import '../utils/app_colors.dart';
import '../screens/conversation_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/student_discount_screen.dart';
import '../screens/fee_payment_screen.dart';
import '../screens/loan_request_screen.dart';
import '../screens/assessment_status_screen.dart';
import '../screens/loan_application_screen.dart';
import '../screens/payment_history_screen.dart';
import 'login_screen.dart';

class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({super.key});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _selectedIndex = 0;
  late UserModel _currentUser;
  late ApiService _apiService;
  late LoanProvider _loanProvider;

  // Data
  List<Map<String, dynamic>> _pupils = [];
  List<Map<String, dynamic>> _filteredPupils = [];
  double _walletBalance = 0.00;
  double _totalOutstandingDue = 0.00;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Account
  String _accountNumber = '';
  String _accountName = '';
  String _bankName = '';
  double _ledgerBalance = 0.00;

  // Loans
  double _loanBalance = 0.00;
  int _activeLoans = 0;
  bool _isLoadingLoan = false;

  // Carousel
  int _currentCarouselIndex = 0;
  final PageController _pageController = PageController();

  // News
  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  // HMO
  List<Map<String, dynamic>> _hospitalRecords = [];
  bool _isLoadingHMO = false;
  int _selectedPupilForHMO = 0;

  // Results
  bool _isLoadingResult = false;

  // Assignments
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoadingAssignments = false;

  // Messages
  int _unreadMessageCount = 0;

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchingPupils = false;

  // Responsive
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

  // ==================== DATA FETCH ====================

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
      // 1. Fetch students
      final studentsResult = await _apiService
          .getGuardianStudents(token: token, guardianId: _currentUser.id)
          .timeout(const Duration(seconds: 30));

      if (studentsResult['success'] != true) {
        if (mounted) {
          setState(() {
            _errorMessage =
                studentsResult['message'] ?? 'Failed to load students data';
            _isLoading = false;
          });
        }
        return;
      }

      final studentsData = studentsResult['data'] as List? ?? [];

      // 2. Fetch all pending fees in one call
      Map<String, Map<String, dynamic>> pendingByStudent = {};
      double grandTotalDue = 0.0;

      try {
        final pendingResult = await _apiService.getGuardianPendingPayments(
          token: token,
          guardianId: _currentUser.id,
        );

        if (pendingResult['success'] == true) {
          final List<dynamic> studentsPending =
              (pendingResult['students'] as List?) ?? [];
          grandTotalDue =
              (pendingResult['grandTotalDue'] as num?)?.toDouble() ?? 0.0;

          for (var s in studentsPending) {
            if (s is Map<String, dynamic>) {
              final sid = s['studentId']?.toString() ?? '';
              if (sid.isNotEmpty) pendingByStudent[sid] = s;
            }
          }
        }
      } catch (e) {
        print('⚠️ Failed to fetch pending fees: $e');
      }

      // 3. Map pupils with fee data
      final List<Map<String, dynamic>> mappedPupils = [];

      for (var student in studentsData) {
        final teacher = student['teacher'];
        final classroom = student['classroom'];
        final studentId = student['studentId'] ?? '';
        final classroomId = student['classroomId'] ?? '';

        double totalFees = 0.0;
        double totalPaid = 0.0;
        double balance = 0.0;
        double mandatoryDue = 0.0;
        double optionalDue = 0.0;
        List<Map<String, dynamic>> mandatoryFees = [];
        List<Map<String, dynamic>> optionalFees = [];

        final pending = pendingByStudent[studentId];
        if (pending != null) {
          mandatoryDue =
              (pending['totalMandatoryDue'] as num?)?.toDouble() ?? 0.0;
          optionalDue =
              (pending['totalOptionalDue'] as num?)?.toDouble() ?? 0.0;
          balance = (pending['totalDue'] as num?)?.toDouble() ?? 0.0;

          mandatoryFees = ((pending['mandatoryFees'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          optionalFees = ((pending['optionalFees'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          for (var f in [...mandatoryFees, ...optionalFees]) {
            totalFees += (f['totalAmount'] as num?)?.toDouble() ?? 0.0;
            totalPaid += (f['amountPaid'] as num?)?.toDouble() ?? 0.0;
          }
        }

        mappedPupils.add({
          'id': studentId,
          'name':
          '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'
              .trim(),
          'class': classroom?['name'] ?? student['classroomId'] ?? 'N/A',
          'classroomId': classroomId,
          'classroomName': classroom?['name'] ?? 'N/A',
          'teacherId': teacher?['teacherId'] ?? '',
          'teacherName': teacher != null
              ? '${teacher['firstname'] ?? ''} ${teacher['lastname'] ?? ''}'
              .trim()
              : 'Not Assigned',
          'teacherEmail': teacher?['email'] ?? 'Not available',
          'teacherPhone': teacher?['phone'] ?? 'Not available',
          'admissionNo': student['studentNo'] ?? '',
          'totalFees': totalFees,
          'totalPaid': totalPaid,
          'balance': balance,
          'mandatoryDue': mandatoryDue,
          'optionalDue': optionalDue,
          'mandatoryFees': mandatoryFees,
          'optionalFees': optionalFees,
          'feeStatus': totalFees == 0
              ? 'Not Set'
              : (balance <= 0 ? 'Cleared' : 'Pending'),
          'averageScore': 0,
          'attendance': 0,
        });
      }

      if (mounted) {
        setState(() {
          _pupils = mappedPupils;
          _filteredPupils = List.from(mappedPupils);
          _totalOutstandingDue = grandTotalDue;
        });
      }

      await _fetchWalletAndAccount(token);
      await _fetchLoanData(token);
      await _fetchAssignments(token);
      await _fetchLoanApplications(token);
      _fetchDiscountsForAllPupils(token);

      if (mounted) setState(() => _isLoading = false);
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
      final discountProvider =
      Provider.of<DiscountProvider>(context, listen: false);
      if (_pupils.isEmpty) return;
      discountProvider.fetchDiscountsForAllPupils(
        token: token,
        pupils: _pupils,
      );
    } catch (_) {}
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
      final accountResult = await _apiService
          .getGuardianSavingsAccount(
        token: token,
        guardianId: _currentUser.id,
      )
          .timeout(const Duration(seconds: 30));

      if (accountResult['success'] && mounted) {
        setState(() {
          _walletBalance = accountResult['balance'] ?? 0.0;
          _accountNumber = accountResult['accountNumber'] ?? '';
          _accountName = accountResult['accountName'] ?? '';
          _bankName = accountResult['bankName'] ?? '';
          _ledgerBalance = accountResult['ledgerBalance'] ?? 0.0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLoanData(String token) async {
    setState(() => _isLoadingLoan = true);
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
      if (mounted) setState(() => _isLoadingAssignments = false);
      return;
    }
    setState(() => _isLoadingAssignments = true);

    List<Map<String, dynamic>> allAssignments = [];
    for (var pupil in _pupils) {
      final classroomId = pupil['classroomId']?.toString();
      if (classroomId != null &&
          classroomId.isNotEmpty &&
          classroomId != 'N/A') {
        try {
          final result = await _apiService
              .getAssignmentsByClassId(
            token: token,
            classroomId: classroomId,
          )
              .timeout(const Duration(seconds: 30));

          if (result['success'] && result['data'] != null) {
            final assignments =
            List<Map<String, dynamic>>.from(result['data']);
            final className = pupil['class'] ?? 'N/A';
            for (var a in assignments) {
              a['className'] = className;
            }
            allAssignments.addAll(assignments);
          }
        } catch (_) {}
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
    setState(() => _isLoadingNews = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token != null) {
      try {
        final newsResult = await _apiService
            .getAllNews(token: token)
            .timeout(const Duration(seconds: 30));
        if (newsResult['success'] && mounted) {
          final newsData = (newsResult['data'] as List?)
              ?.map((item) => {
            'id': item['id'],
            'title': item['title'],
            'content': item['content'],
            'date': _formatDate(item['date']),
          })
              .toList() ??
              [];
          setState(() {
            _news = newsData;
            _isLoadingNews = false;
          });
        } else {
          setState(() => _isLoadingNews = false);
        }
      } catch (_) {
        setState(() => _isLoadingNews = false);
      }
    } else {
      setState(() => _isLoadingNews = false);
    }
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
      if (mounted) setState(() => _unreadMessageCount = unreadCount);
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'Recent';
    try {
      DateTime dateTime = DateTime.parse(dateValue.toString());
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
    } catch (_) {
      return 'Recent';
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _fetchDashboardData();
    await _fetchNews();
    await _fetchUnreadMessages();
    if (mounted) setState(() => _isRefreshing = false);
  }

  // ==================== FEE GROUPING HELPERS ====================

  Map<String, List<Map<String, dynamic>>> _groupFeesBySessionTerm(
      List<Map<String, dynamic>> fees) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var fee in fees) {
      final session = fee['sessionId']?.toString() ?? 'Unknown';
      final term = fee['termName']?.toString() ?? 'Unknown';
      final key = '$session|$term';
      groups.putIfAbsent(key, () => []).add(fee);
    }
    return groups;
  }

  bool _isCurrentSessionTerm(Map<String, dynamic> fee) {
    final session = fee['sessionId']?.toString() ?? '';
    final term = fee['termName']?.toString() ?? '';
    final currentSession = _currentUser.sessionId ?? '';
    final currentTerm = _currentUser.term ?? '';
    return session == currentSession &&
        term.toLowerCase().trim() == currentTerm.toLowerCase().trim();
  }

  // ==================== FEE PAYMENT ====================

  Future<void> _payAllFeesForPupil(Map<String, dynamic> pupil) async {
    final studentId = pupil['id']?.toString();
    final classroomId = pupil['classroomId']?.toString();
    final studentName = pupil['name'] ?? 'Student';
    final studentClass = pupil['class'] ?? 'N/A';

    if (studentId == null || studentId.isEmpty) {
      _showSnack('Student ID not available', AppColors.warning);
      return;
    }
    if (classroomId == null || classroomId.isEmpty) {
      _showSnack('Classroom ID not available', AppColors.warning);
      return;
    }

    final double balance = (pupil['balance'] as num?)?.toDouble() ?? 0.0;

    if (balance <= 0) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Outstanding Balance',
              style: TextStyle(color: AppColors.success)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 48, color: AppColors.success),
              const SizedBox(height: 16),
              Text('$studentName has no outstanding fees.'),
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
          originalFee: balance,
          sessionId: _currentUser.sessionId ?? '',
        ),
      ),
    ).then((_) => _refreshData());
  }

  Future<void> _payIndividualFee({
    required Map<String, dynamic> pupil,
    required Map<String, dynamic> fee,
  }) async {
    final studentId = pupil['id']?.toString();
    final classroomId = pupil['classroomId']?.toString();
    final studentName = pupil['name'] ?? 'Student';
    final studentClass = pupil['class'] ?? 'N/A';

    final feeId = fee['feeId']?.toString() ?? '';
    final feeName = fee['feeName']?.toString() ?? 'Fee';
    final feeType = fee['feeType']?.toString() ?? '';
    final termName = fee['termName']?.toString() ?? '';
    final balance = (fee['balance'] as num?)?.toDouble() ?? 0.0;

    if (studentId == null || studentId.isEmpty) {
      _showSnack('Student ID not available', AppColors.warning);
      return;
    }
    if (classroomId == null || classroomId.isEmpty) {
      _showSnack('Classroom ID not available', AppColors.warning);
      return;
    }
    if (balance <= 0) {
      _showSnack('This fee is already cleared', AppColors.success);
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
          originalFee: balance,
          sessionId: fee['sessionId']?.toString() ?? '',
          feeId: feeId,
          feeType: feeType,
          feeName: feeName,
          termName: termName,
        ),
      ),
    ).then((_) => _refreshData());
  }

  // ==================== FEES SCREEN ====================

  void _showFeesScreen() {
    if (_pupils.isEmpty) {
      _showSnack('No pupils found', AppColors.warning);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Outstanding Fees',
                      style: TextStyle(
                        fontSize: _resp.isVerySmall ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Grand Total Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet,
                        color: AppColors.white, size: _resp.iconSize),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Outstanding',
                            style: TextStyle(
                              fontSize: _resp.smallCaptionSize,
                              color: AppColors.white.withOpacity(0.9),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '₦${_totalOutstandingDue.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: _resp.isVerySmall ? 22 : 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Fees are grouped by academic session and term. Pay each fee individually or use "Pay All".',
                  style: TextStyle(
                    fontSize: _resp.smallCaptionSize,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _pupils.length,
                  itemBuilder: (context, index) =>
                      _buildPupilFeesExpandableCard(_pupils[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPupilFeesExpandableCard(Map<String, dynamic> pupil) {
    final List<Map<String, dynamic>> mandatory =
        (pupil['mandatoryFees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> optional =
        (pupil['optionalFees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final double total = (pupil['balance'] as num?)?.toDouble() ?? 0.0;
    final bool hasAnyFees = mandatory.isNotEmpty || optional.isNotEmpty;

    // Group by session + term
    final mandatoryGroups = _groupFeesBySessionTerm(mandatory);
    final optionalGroups = _groupFeesBySessionTerm(optional);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasAnyFees
              ? AppColors.warning.withOpacity(0.3)
              : AppColors.success.withOpacity(0.3),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.symmetric(
            horizontal: _resp.isVerySmall ? 8 : 12, vertical: 4),
        childrenPadding: EdgeInsets.fromLTRB(
            _resp.isVerySmall ? 8 : 12, 0, _resp.isVerySmall ? 8 : 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          radius: _resp.isVerySmall ? 16 : 22,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(
            (pupil['name'] as String)[0].toUpperCase(),
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: _resp.isVerySmall ? 13 : 16,
            ),
          ),
        ),
        title: Text(
          pupil['name'],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: _resp.isVerySmall ? 13 : 15,
            color: AppColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pupil['class'],
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              total > 0
                  ? 'Total due: ₦${total.toStringAsFixed(2)}'
                  : 'Fully cleared ✅',
              style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: total > 0 ? AppColors.warning : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
        trailing: Icon(
          total > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
          color: total > 0 ? AppColors.warning : AppColors.success,
          size: _resp.iconSize,
        ),
        children: [
          if (!hasAnyFees)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No outstanding fees for this child.',
                style: TextStyle(
                    fontSize: _resp.smallTextSize,
                    color: AppColors.textSecondary),
              ),
            ),
          if (mandatory.isNotEmpty) ...[
            _buildFeeTypeHeader('Mandatory Fees', AppColors.primary,
                pupil['mandatoryDue']),
            const SizedBox(height: 6),
            ..._buildSessionTermGroups(
              pupil: pupil,
              groups: mandatoryGroups,
              isMandatory: true,
            ),
          ],
          if (optional.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildFeeTypeHeader(
                'Optional Fees', AppColors.info, pupil['optionalDue']),
            const SizedBox(height: 6),
            ..._buildSessionTermGroups(
              pupil: pupil,
              groups: optionalGroups,
              isMandatory: false,
            ),
          ],
          if (total > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _payAllFeesForPupil(pupil);
                },
                icon: Icon(Icons.payment, size: _resp.smallIconSize),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Pay All — ₦${total.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: _resp.buttonTextSize,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 10 : 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeeTypeHeader(String title, Color color, dynamic due) {
    final double amount = (due as num?)?.toDouble() ?? 0.0;
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: _resp.smallTextSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (amount > 0)
          Text(
            'Due ₦${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSessionTermGroups({
    required Map<String, dynamic> pupil,
    required Map<String, List<Map<String, dynamic>>> groups,
    required bool isMandatory,
  }) {
    final List<Widget> widgets = [];

    final sortedKeys = groups.keys.toList();
    sortedKeys.sort((a, b) {
      final feeA = groups[a]!.first;
      final feeB = groups[b]!.first;
      final isCurrentA = _isCurrentSessionTerm(feeA);
      final isCurrentB = _isCurrentSessionTerm(feeB);
      if (isCurrentA && !isCurrentB) return -1;
      if (!isCurrentA && isCurrentB) return 1;
      return 0;
    });

    for (var key in sortedKeys) {
      final fees = groups[key]!;
      if (fees.isEmpty) continue;

      final sampleFee = fees.first;
      final session = sampleFee['sessionId']?.toString() ?? '';
      final term = sampleFee['termName']?.toString() ?? '';
      final isCurrent = _isCurrentSessionTerm(sampleFee);

      final groupTotal = fees.fold<double>(
        0.0,
            (sum, f) => sum + ((f['balance'] as num?)?.toDouble() ?? 0.0),
      );

      final headerColor = isCurrent
          ? (isMandatory ? AppColors.primary : AppColors.info)
          : AppColors.warning;

      final headerLabel = isCurrent
          ? 'Current — $session • $term'
          : 'Outstanding — $session • $term';

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: headerColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: headerColor.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(
                isCurrent ? Icons.event_available : Icons.history,
                size: _resp.smallIconSize,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headerLabel,
                  style: TextStyle(
                    fontSize: _resp.smallTextSize,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (groupTotal > 0)
                Text(
                  '₦${groupTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: _resp.smallTextSize,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                ),
            ],
          ),
        ),
      );

      for (var fee in fees) {
        widgets.add(_buildPayableFeeCard(
          pupil: pupil,
          fee: fee,
          isMandatory: isMandatory,
          isOutstandingPrevious: !isCurrent,
        ));
      }
    }

    return widgets;
  }

  Widget _buildPayableFeeCard({
    required Map<String, dynamic> pupil,
    required Map<String, dynamic> fee,
    required bool isMandatory,
    bool isOutstandingPrevious = false,
  }) {
    final name = fee['feeName'] ?? 'Fee';
    final type = fee['feeType'] ?? '';
    final totalAmount = (fee['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (fee['amountPaid'] as num?)?.toDouble() ?? 0.0;
    final balance = (fee['balance'] as num?)?.toDouble() ?? 0.0;
    final term = fee['termName'] ?? '';
    final session = fee['sessionId'] ?? '';
    final isCleared = balance <= 0;

    final String typeLabel = type == 'ClassFee'
        ? 'Tuition Fee'
        : type == 'OtherFee'
        ? 'Other Fee'
        : type.isNotEmpty
        ? type
        : 'Fee';

    final baseColor = isMandatory ? AppColors.primary : AppColors.info;
    final color = isOutstandingPrevious ? AppColors.warning : baseColor;
    final statusColor = isCleared ? AppColors.success : color;

    final String subtitleLine = [
      if (name.isNotEmpty && name != typeLabel) name,
      if (session.isNotEmpty) session,
      if (term.isNotEmpty) term,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCleared
            ? AppColors.success.withOpacity(0.05)
            : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCleared
              ? AppColors.success.withOpacity(0.3)
              : color.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            type == 'ClassFee'
                                ? Icons.school
                                : type == 'OtherFee'
                                ? Icons.receipt_long
                                : Icons.payments,
                            size: _resp.smallIconSize,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: _resp.isVerySmall ? 13 : 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isOutstandingPrevious)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'OUTSTANDING',
                              style: TextStyle(
                                fontSize: _resp.smallCaptionSize,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (subtitleLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 34, top: 2),
                        child: Text(
                          subtitleLine,
                          style: TextStyle(
                            fontSize: _resp.smallCaptionSize,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isCleared ? 'Paid ✅' : '₦${balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: _resp.isVerySmall ? 13 : 15,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  if (!isCleared)
                    Text(
                      'of ₦${totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: _resp.smallCaptionSize,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: totalAmount > 0
                  ? (amountPaid / totalAmount).clamp(0, 1)
                  : 0,
              minHeight: 5,
              backgroundColor: AppColors.greyLight,
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paid: ₦${amountPaid.toStringAsFixed(2)} / ₦${totalAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: _resp.smallCaptionSize,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (!isCleared) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _payIndividualFee(pupil: pupil, fee: fee);
                },
                icon: Icon(Icons.payment, size: _resp.smallIconSize),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Pay ₦${balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: _resp.buttonTextSize,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      vertical: _resp.isMobile ? 8 : 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== PUPIL DETAILS ====================

  void _showPupilDetails(Map<String, dynamic> pupil) {
    final bool hasPhone = pupil['teacherPhone'] != null &&
        pupil['teacherPhone'].toString().isNotEmpty &&
        pupil['teacherPhone'] != 'N/A' &&
        pupil['teacherPhone'] != 'Not available';

    final List<Map<String, dynamic>> mandatoryFees =
        (pupil['mandatoryFees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> optionalFees =
        (pupil['optionalFees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final double totalFees = (pupil['totalFees'] as num?)?.toDouble() ?? 0.0;
    final double totalPaid = (pupil['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final double balance = (pupil['balance'] as num?)?.toDouble() ?? 0.0;
    final bool hasFee = totalFees > 0;
    final bool isCleared = hasFee && balance <= 0;
    final double percentagePaid =
    hasFee ? ((totalPaid / totalFees) * 100).clamp(0, 100) : 0;

    final mandatoryGroups = _groupFeesBySessionTerm(mandatoryFees);
    final optionalGroups = _groupFeesBySessionTerm(optionalFees);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.all(_resp.isVerySmall ? 12 : 16),
        title: Text(
          pupil['name'],
          style: const TextStyle(color: AppColors.primary, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Student Information',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                          'Admission No', pupil['admissionNo'] ?? 'N/A'),
                      _buildInfoRow('Class', pupil['class'] ?? 'N/A'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCleared
                        ? AppColors.success.withOpacity(0.08)
                        : AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCleared
                          ? AppColors.success.withOpacity(0.3)
                          : AppColors.warning.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCleared
                                ? Icons.check_circle
                                : Icons.receipt_long,
                            color: isCleared
                                ? AppColors.success
                                : AppColors.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              'Fee Summary',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (hasFee) ...[
                        _buildFeeLine('Total Fee',
                            '₦${totalFees.toStringAsFixed(2)}',
                            AppColors.textSecondary),
                        _buildFeeLine('Total Paid',
                            '₦${totalPaid.toStringAsFixed(2)}',
                            AppColors.success),
                        const Divider(height: 12),
                        _buildFeeLine(
                          isCleared ? 'Status' : 'Outstanding',
                          isCleared
                              ? 'Cleared ✅'
                              : '₦${balance.toStringAsFixed(2)}',
                          isCleared
                              ? AppColors.success
                              : AppColors.warning,
                          bold: true,
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: percentagePaid / 100,
                            minHeight: 8,
                            backgroundColor: AppColors.greyLight,
                            valueColor: AlwaysStoppedAnimation(
                              isCleared
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${percentagePaid.toStringAsFixed(0)}% paid',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ] else
                        const Text(
                          'No fee has been set for this term.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),

                // Grouped fees
                if (mandatoryFees.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDialogSectionHeader(
                      'Mandatory Fees', AppColors.primary),
                  const SizedBox(height: 6),
                  ..._buildDialogSessionGroups(
                    pupil: pupil,
                    groups: mandatoryGroups,
                    isMandatory: true,
                  ),
                ],
                if (optionalFees.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDialogSectionHeader(
                      'Optional Fees', AppColors.info),
                  const SizedBox(height: 6),
                  ..._buildDialogSessionGroups(
                    pupil: pupil,
                    groups: optionalGroups,
                    isMandatory: false,
                  ),
                ],

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
                      const Text('Teacher Information',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                          'Name', pupil['teacherName'] ?? 'N/A'),
                      _buildInfoRow(
                          'Email', pupil['teacherEmail'] ?? 'N/A'),
                      _buildInfoRow(
                          'Phone', pupil['teacherPhone'] ?? 'N/A'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: EdgeInsets.symmetric(
            horizontal: _resp.isVerySmall ? 8 : 16, vertical: 8),
        actions: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (hasFee && !isCleared)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _payAllFeesForPupil(pupil);
                  },
                  icon: const Icon(Icons.payment, size: 16),
                  label: Text('Pay All ₦${balance.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (hasPhone)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _makePhoneCall(pupil['teacherPhone']);
                  },
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _startConversationWithTeacher(pupil);
                },
                icon: const Icon(Icons.message, size: 16),
                label: const Text('Message',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogSectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDialogSessionGroups({
    required Map<String, dynamic> pupil,
    required Map<String, List<Map<String, dynamic>>> groups,
    required bool isMandatory,
  }) {
    final List<Widget> widgets = [];

    final sortedKeys = groups.keys.toList();
    sortedKeys.sort((a, b) {
      final feeA = groups[a]!.first;
      final feeB = groups[b]!.first;
      final isCurrentA = _isCurrentSessionTerm(feeA);
      final isCurrentB = _isCurrentSessionTerm(feeB);
      if (isCurrentA && !isCurrentB) return -1;
      if (!isCurrentA && isCurrentB) return 1;
      return 0;
    });

    for (var key in sortedKeys) {
      final fees = groups[key]!;
      if (fees.isEmpty) continue;

      final sampleFee = fees.first;
      final session = sampleFee['sessionId']?.toString() ?? '';
      final term = sampleFee['termName']?.toString() ?? '';
      final isCurrent = _isCurrentSessionTerm(sampleFee);

      final headerColor = isCurrent
          ? (isMandatory ? AppColors.primary : AppColors.info)
          : AppColors.warning;

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: headerColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                isCurrent ? Icons.event_available : Icons.history,
                size: 12,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isCurrent
                      ? 'Current — $session • $term'
                      : 'Outstanding — $session • $term',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      );

      for (var fee in fees) {
        widgets.add(_buildDialogFeeItem(
          pupil: pupil,
          fee: fee,
          isMandatory: isMandatory,
          isOutstandingPrevious: !isCurrent,
        ));
      }
    }

    return widgets;
  }

  Widget _buildDialogFeeItem({
    required Map<String, dynamic> pupil,
    required Map<String, dynamic> fee,
    required bool isMandatory,
    bool isOutstandingPrevious = false,
  }) {
    final name = fee['feeName'] ?? 'Fee';
    final type = fee['feeType'] ?? '';
    final totalAmount = (fee['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (fee['amountPaid'] as num?)?.toDouble() ?? 0.0;
    final balance = (fee['balance'] as num?)?.toDouble() ?? 0.0;
    final term = fee['termName'] ?? '';
    final session = fee['sessionId'] ?? '';
    final isCleared = balance <= 0;

    final String typeLabel = type == 'ClassFee'
        ? 'Tuition Fee'
        : type == 'OtherFee'
        ? 'Other Fee'
        : type.isNotEmpty
        ? type
        : 'Fee';

    final baseColor = isMandatory ? AppColors.primary : AppColors.info;
    final color = isOutstandingPrevious ? AppColors.warning : baseColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCleared
            ? AppColors.success.withOpacity(0.05)
            : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCleared
              ? AppColors.success.withOpacity(0.3)
              : color.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (name.isNotEmpty && name != typeLabel)
                      Text(
                        name,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    if (session.isNotEmpty || term.isNotEmpty)
                      Text(
                        '$session${session.isNotEmpty && term.isNotEmpty ? ' • ' : ''}$term',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isCleared ? 'Paid ✅' : '₦${balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isCleared ? AppColors.success : color,
                ),
              ),
            ],
          ),
          if (!isCleared) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Paid: ₦${amountPaid.toStringAsFixed(2)} / ₦${totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _payIndividualFee(pupil: pupil, fee: fee);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Pay',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== DIALOGS ====================

  void _showFundWalletDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fund Wallet',
            style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  _buildInfoRow('Account Name',
                      _accountName.isNotEmpty ? _accountName : 'N/A'),
                  _buildInfoRow('Account Number',
                      _accountNumber.isNotEmpty ? _accountNumber : 'N/A'),
                  _buildInfoRow('Bank Name',
                      _bankName.isNotEmpty ? _bankName : 'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Make a transfer to the above account. Your wallet will be credited automatically.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              final details = 'Account Name: $_accountName\n'
                  'Account Number: $_accountNumber\n'
                  'Bank Name: $_bankName';
              Clipboard.setData(ClipboardData(text: details));
              Navigator.pop(context);
              _showSnack('Account details copied!', AppColors.success);
            },
            style:
            ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Copy Details'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog() {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds',
            style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Balance: ₦${_walletBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount > 0 && amount <= _walletBalance) {
                Navigator.pop(context);
                _showSnack(
                    'Withdrawal of ₦${amount.toStringAsFixed(2)} initiated!',
                    AppColors.success);
              } else {
                _showSnack('Invalid amount or insufficient balance',
                    AppColors.error);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }

  void _showNewsDetails(Map<String, dynamic> news) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(news['title'],
            style:
            const TextStyle(color: AppColors.primary, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Date: ${news['date']}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text(news['content'] ?? 'No content available',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ==================== SHEETS ====================

  void _showAllNews() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 16),
          child: Column(
            children: [
              const Text('All News',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
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
                        title: Text(item['title'],
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                        subtitle: Text(item['date'],
                            style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          Navigator.pop(context);
                          _showNewsDetails(item);
                        },
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

  void _showAllAssignments() {
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
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('All Assignments',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoadingAssignments
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                    : _assignments.isEmpty
                    ? const Center(child: Text('No assignments yet'))
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: _assignments.length,
                  itemBuilder: (context, index) =>
                      _buildAssignmentItem(_assignments[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllLoanApplications() {
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
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('All Loan Applications',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loanProvider.isLoading
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                    : _loanProvider.applications.isEmpty
                    ? const Center(
                    child: Text('No loan applications yet'))
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: _loanProvider.applications.length,
                  itemBuilder: (context, index) =>
                      _buildLoanApplicationTile(
                          _loanProvider.applications[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoanDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Loan Details',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildInfoRow('Total Loan Amount',
                        '₦${_loanBalance.toStringAsFixed(2)}'),
                    _buildInfoRow('Loan Balance',
                        '₦${_loanBalance.toStringAsFixed(2)}'),
                    _buildInfoRow('Active Loans', '$_activeLoans'),
                    const Divider(height: 24),
                    const Text('Loan Applications',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_loanProvider.applications.isEmpty)
                      const Text('No loan applications yet')
                    else
                      ..._loanProvider.applications.map((app) => ListTile(
                        dense: true,
                        title: Text(app.statusDisplay,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                        subtitle: Text(
                          'ID: ${app.id.length > 8 ? app.id.substring(0, 8) : app.id}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Icon(app.statusIcon,
                            color: app.statusColor),
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToLoanApplication(app);
                        },
                      )),
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

  void _showResultsScreen() {
    if (_pupils.isEmpty) {
      _showSnack('No pupils found', AppColors.warning);
      return;
    }

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
          padding: EdgeInsets.all(_resp.isVerySmall ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Student Results',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: _pupils
                      .map((pupil) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: _resp.isVerySmall ? 16 : 20,
                      backgroundColor:
                      AppColors.primary.withOpacity(0.1),
                      child: Text(
                        (pupil['name'] as String)[0].toUpperCase(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    title: Text(pupil['name'] as String,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    subtitle: Text('Class: ${pupil['class']}',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    trailing: const Icon(Icons.chevron_right,
                        size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      _viewPupilResults(pupil);
                    },
                  ))
                      .toList(),
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
      _showSnack('No pupils found', AppColors.warning);
      return;
    }

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
          padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Student Discounts',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Consumer<DiscountProvider>(
                  builder: (context, discountProvider, child) {
                    if (discountProvider.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary),
                      );
                    }

                    final hasAnyDiscounts = _pupils.any((pupil) {
                      final studentId = pupil['id']?.toString() ?? '';
                      return discountProvider
                          .getDiscountsForStudent(studentId)
                          .isNotEmpty;
                    });

                    if (!hasAnyDiscounts) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.discount_rounded,
                                size: _resp.isVerySmall ? 40 : 64,
                                color: AppColors.grey),
                            const SizedBox(height: 12),
                            const Text('No discounts available',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary)),
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
                        final pupilDiscounts = discountProvider
                            .getDiscountsForStudent(studentId);
                        return _buildStudentDiscountCard(
                            pupil, pupilDiscounts);
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

  void _showStudentDiscounts(Map<String, dynamic> pupil) {
    final studentId = pupil['id']?.toString();
    if (studentId == null || studentId.isEmpty) {
      _showSnack('Student ID not available', AppColors.warning);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDiscountScreen(
          studentId: studentId,
          studentName: pupil['name'] ?? 'Student',
          studentClass: pupil['class'] ?? 'N/A',
          admissionNo: pupil['admissionNo'] ?? '',
        ),
      ),
    );
  }

  // ==================== HMO ====================

  Future<void> _fetchHospitalRecords(String token, String studentId) async {
    final recordsResult = await _apiService.getChildHospitalRecords(
      token: token,
      studentId: studentId,
      schoolId: _currentUser.schoolId,
      sessionId: _currentUser.sessionId,
    );

    if (recordsResult['success'] && mounted) {
      setState(() {
        _hospitalRecords = (recordsResult['data'] as List?)
            ?.map((record) => {
          'id': record['id'],
          'date': record['visitDate'] ?? record['date'],
          'hospitalName': record['hospitalName'],
          'diagnosis': record['diagnosis'],
          'treatment': record['treatment'],
          'doctorName': record['doctorName'],
          'visitType': record['visitType'] ?? 'School',
          'cost': (record['cost'] ?? 0).toDouble(),
          'hmoCovered': record['hmoCovered'] ?? true,
        })
            .toList() ??
            [];
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
      _showSnack('No pupils found', AppColors.warning);
      return;
    }

    if (_hospitalRecords.isEmpty && _pupils.isNotEmpty) {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token != null) _fetchHospitalRecords(token, _pupils[0]['id']);
    }

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
                padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Health Records (HMO)',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.cardGradientLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Select Child',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                          const SizedBox(height: 8),
                          DropdownButton<int>(
                            value: _selectedPupilForHMO,
                            isExpanded: true,
                            underline: const SizedBox(),
                            icon: Icon(Icons.arrow_drop_down,
                                color: AppColors.primary),
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            items: _pupils.asMap().entries.map((entry) {
                              return DropdownMenuItem<int>(
                                value: entry.key,
                                child: Text(
                                  entry.value['name'] as String,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              if (value != null &&
                                  value != _selectedPupilForHMO) {
                                bottomSheetSetState(() {
                                  _selectedPupilForHMO = value;
                                  _isLoadingHMO = true;
                                  _hospitalRecords = [];
                                });
                                final token = Provider.of<AuthProvider>(
                                    context,
                                    listen: false)
                                    .token;
                                if (token != null) {
                                  await _fetchHospitalRecords(token,
                                      _pupils[_selectedPupilForHMO]['id']);
                                  if (mounted) {
                                    bottomSheetSetState(() {
                                      _isLoadingHMO = false;
                                    });
                                  }
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
                          ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                          : _hospitalRecords.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_information,
                                size: _resp.isVerySmall ? 40 : 48,
                                color: AppColors.grey),
                            const SizedBox(height: 12),
                            const Text(
                              'No hospital records found',
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                  AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        controller: scrollController,
                        itemCount: _hospitalRecords.length,
                        itemBuilder: (context, index) =>
                            _buildHMORecordCard(
                                _hospitalRecords[index]),
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

  // ==================== PHONE ====================

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty ||
        phoneNumber == 'N/A' ||
        phoneNumber == 'Not available') {
      _showSnack('Phone number not available', AppColors.warning);
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
      if (await canLaunchUrl(phoneUri)) await launchUrl(phoneUri);
    } catch (_) {
      _showSnack('Could not dial $phoneNumber', AppColors.error);
    }
  }

  // ==================== NAVIGATION ====================

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
    ).then((_) => _fetchLoanApplications(
      Provider.of<AuthProvider>(context, listen: false).token ?? '',
    ));
  }

  void _navigateToLoanApplication(LoanApplication application) {
    if (application.status == 2 || application.status == 3) {
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
      _showApplicationDetails(application);
    }
  }

  void _showApplicationDetails(LoanApplication application) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Loan Application Details',
            style: TextStyle(color: AppColors.primary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Application ID', application.id),
              _buildDetailRow('Status', application.statusDisplay),
              if (application.requestedAmount != null)
                _buildDetailRow('Requested Amount',
                    '₦${application.requestedAmount!.toStringAsFixed(2)}'),
              if (application.eligibleAmount != null)
                _buildDetailRow('Eligible Amount',
                    '₦${application.eligibleAmount!.toStringAsFixed(2)}'),
              _buildDetailRow('Created',
                  _formatDate(application.createdAt.toString())),
              _buildDetailRow('Updated',
                  _formatDate(application.updatedAt.toString())),
              if (application.edubanclStatusMessage != null)
                _buildDetailRow(
                    'Message', application.edubanclStatusMessage!),
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
                      creditAssessmentId:
                      application.creditAssessmentId ?? '',
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

  void _startConversationWithTeacher(Map<String, dynamic> pupil) {
    final teacherId = pupil['teacherId']?.toString() ?? '';
    final teacherName = pupil['teacherName']?.toString() ?? 'Teacher';

    if (teacherId.isEmpty || teacherId == 'Not Assigned') {
      _showSnack('Teacher not assigned', AppColors.error);
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

  // ==================== HELPERS ====================

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: _resp.smallTextSize,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: _resp.smallTextSize,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeLine(String label, String value, Color valueColor,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: valueColor,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.right,
            ),
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return AppColors.success;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return AppColors.info;
      case 'D':
        return AppColors.warning;
      case 'F':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  // ==================== RESULTS ====================

  Future<void> _viewPupilResults(Map<String, dynamic> pupil) async {
    final classroomId = pupil['classroomId']?.toString();
    if (classroomId == null || classroomId.isEmpty) {
      _showSnack('Classroom not assigned', AppColors.warning);
      return;
    }

    setState(() => _isLoadingResult = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      setState(() => _isLoadingResult = false);
      _showSnack('Authentication error', AppColors.error);
      return;
    }

    final result = await _apiService.getStudentAllSubjectsScoresByTermId(
      token: token,
      schoolId: _currentUser.schoolId,
      classroomId: classroomId,
      studentId: pupil['id'],
      sessionKey: _currentUser.sessionKey,
      termId: _currentUser.termId,
    );

    setState(() => _isLoadingResult = false);

    if (result['success'] && result['data'] != null) {
      _showResultDetailsDialog(pupil, result['data']);
    } else {
      _showSnack(result['message'] ?? 'No results available',
          AppColors.warning);
    }
  }

  void _showResultDetailsDialog(
      Map<String, dynamic> pupil, dynamic resultData) {
    final studentResult = StudentResult.fromJson(resultData);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          color: Colors.white),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${studentResult.className} | ${studentResult.term}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9)),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 10,
                    headingRowColor: MaterialStateProperty.all(
                        AppColors.primary.withOpacity(0.1)),
                    columns: const [
                      DataColumn(
                          label: Text('Subject',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      DataColumn(
                          label: Text('CA',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      DataColumn(
                          label: Text('Exam',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      DataColumn(
                          label: Text('Total',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      DataColumn(
                          label: Text('Grade',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                    ],
                    rows: studentResult.subjects.map((subject) {
                      return DataRow(cells: [
                        DataCell(Text(subject.subjectName,
                            style: const TextStyle(fontSize: 11))),
                        DataCell(Text(
                            subject.caScore.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11))),
                        DataCell(Text(
                            subject.examScore.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11))),
                        DataCell(Text(
                          subject.totalScore.toStringAsFixed(1),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: subject.totalScore >= 70
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getGradeColor(subject.grade)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subject.grade,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: _getGradeColor(subject.grade)),
                          ),
                        )),
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

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _resp = ResponsiveInfo(MediaQuery.of(context).size.width);

    return Scaffold(
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: _isLoading
              ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
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
      bottomNavigationBar: _isLoading || _errorMessage != null
          ? null
          : _buildBottomNavigationBar(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: _resp.isVerySmall ? 13 : 15,
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
        selectedFontSize: _resp.isVerySmall ? 9 : 11,
        unselectedFontSize: _resp.isVerySmall ? 9 : 11,
        currentIndex: _selectedIndex,
        elevation: 0,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded), label: 'Home'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.school_rounded), label: 'Pupils'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Wallet'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.message_rounded),
                if (_unreadMessageCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(
                          minWidth: 14, minHeight: 14),
                      child: Text(
                        '$_unreadMessageCount',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 8),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }

  // ==================== HOME ====================

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          if (_totalOutstandingDue > 0) ...[
            _buildOutstandingBanner(),
            const SizedBox(height: 12),
          ],
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
          _buildSectionTitle(
              'Assignments', _assignments.isNotEmpty ? 'View All' : null),
          const SizedBox(height: 8),
          _buildAssignmentsPreview(),
          const SizedBox(height: 12),
          _buildSectionTitle(
              'News & Events', _news.isNotEmpty ? 'View All' : null),
          const SizedBox(height: 8),
          _buildNewsAndEvents(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOutstandingBanner() {
    return GestureDetector(
      onTap: _showFeesScreen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.white, size: _resp.iconSize),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Outstanding',
                    style: TextStyle(
                      fontSize: _resp.smallCaptionSize,
                      color: AppColors.white.withOpacity(0.9),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '₦${_totalOutstandingDue.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: _resp.isVerySmall ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppColors.white, size: _resp.iconSize),
          ],
        ),
      ),
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

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: _resp.smallTextSize)),
              const SizedBox(height: 2),
              Text(
                _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: _resp.titleSize,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                _currentUser.schoolName,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: _resp.captionSize),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
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
                        blurRadius: 10),
                  ],
                ),
                child: Center(
                  child: Icon(Icons.message,
                      size: _resp.iconSize, color: AppColors.white),
                ),
              ),
            ),
            if (_unreadMessageCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$_unreadMessageCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCarousel() {
    final items = [_buildWalletCard(), _buildLoanCard()];
    return Column(
      children: [
        SizedBox(
          height: _resp.isVerySmall ? 210 : _resp.isMobile ? 230 : 250,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentCarouselIndex = i),
            itemCount: items.length,
            itemBuilder: (context, index) => items[index],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (index) {
            return GestureDetector(
              onTap: () => _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
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
      padding:
      EdgeInsets.all(_resp.isVerySmall ? 12 : _resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.3), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wallet Balance',
                    style: TextStyle(
                      fontSize: _resp.isVerySmall
                          ? 14
                          : _resp.isMobile
                          ? 16
                          : 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('Active',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₦${_walletBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: _resp.isVerySmall
                        ? 22
                        : _resp.isMobile
                        ? 28
                        : _resp.isTablet
                        ? 34
                        : 38,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _showFundWalletDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 8 : 10, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _resp.isVerySmall ? 'Fund' : 'Fund Wallet',
                      style: TextStyle(fontSize: _resp.isMobile ? 11 : 13),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: _navigateToLoanRequest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 8 : 10, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _resp.isVerySmall ? 'Loan' : 'Get Loan',
                      style: TextStyle(fontSize: _resp.isMobile ? 11 : 13),
                      maxLines: 1,
                    ),
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
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: AppColors.white)),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding:
      EdgeInsets.all(_resp.isVerySmall ? 12 : _resp.isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.3), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Loan Summary',
                    style: TextStyle(
                      fontSize: _resp.isVerySmall
                          ? 14
                          : _resp.isMobile
                          ? 16
                          : 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    color: _activeLoans > 0
                        ? AppColors.warning
                        : AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₦${_loanBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: _resp.isVerySmall
                        ? 22
                        : _resp.isMobile
                        ? 28
                        : _resp.isTablet
                        ? 34
                        : 38,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _showLoanDetails,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white),
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 8 : 10, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Details',
                        style: TextStyle(
                            fontSize: _resp.isMobile ? 11 : 13),
                        maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                  _loanBalance > 0 ? _showWithdrawDialog : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 8 : 10, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Repay',
                        style: TextStyle(
                            fontSize: _resp.isMobile ? 11 : 13),
                        maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== STATS ====================

  Widget _buildStatsGrid() {
    final crossAxisCount = _resp.isVerySmall
        ? 2
        : (_resp.isMobile ? 2 : (_resp.isTablet ? 3 : 4));
    final ratio = _resp.isVerySmall ? 1.6 : 1.4;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: _resp.gridSpacing,
      crossAxisSpacing: _resp.gridSpacing,
      childAspectRatio: ratio,
      children: [
        _buildStatCard('Pupils', '${_pupils.length}', Icons.people,
            AppColors.primary),
        _buildStatCard(
            'Outstanding',
            '₦${_totalOutstandingDue.toStringAsFixed(0)}',
            Icons.receipt_long,
            AppColors.warning),
        _buildStatCard('Assignments', '${_assignments.length}',
            Icons.assignment, AppColors.info),
        _buildStatCard(
            'HMO', 'Active', Icons.health_and_safety, AppColors.success),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(_resp.isVerySmall ? 6 : 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: _resp.iconSize, color: color),
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: _resp.valueSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String? action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: _resp.sectionTitleSize,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: () {
                if (title == 'Assignments') {
                  _showAllAssignments();
                } else if (title == 'My Children') {
                  setState(() => _selectedIndex = 1);
                } else if (title == 'News & Events') {
                  _showAllNews();
                } else if (title == 'Loan Applications') {
                  _showAllLoanApplications();
                }
              },
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  action,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: _resp.smallTextSize,
                    fontWeight: FontWeight.w500,
                  ),
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
          child: Text('No wards found',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final displayList = _isSearchingPupils ? _filteredPupils : _pupils;
    final itemCount = _isSearchingPupils
        ? displayList.length
        : (displayList.length > 3 ? 3 : displayList.length);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: _resp.padding, vertical: _resp.isMobile ? 6 : 8),
          child: TextField(
            controller: _searchController,
            onChanged: _filterPupils,
            decoration: InputDecoration(
              hintText: 'Search by name, class, or teacher...',
              hintStyle: TextStyle(
                  fontSize: _resp.smallTextSize,
                  color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search,
                  color: AppColors.primary, size: _resp.iconSize),
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
                  vertical: _resp.isMobile ? 8 : 10, horizontal: 12),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding:
            EdgeInsets.symmetric(horizontal: _resp.padding, vertical: 6),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                  fontSize: _resp.smallTextSize,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500),
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
            itemBuilder: (context, index) =>
                _buildPupilTile(displayList[index]),
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

    final double balance = (pupil['balance'] as num?)?.toDouble() ?? 0.0;
    final double totalFees = (pupil['totalFees'] as num?)?.toDouble() ?? 0.0;
    final bool hasFee = totalFees > 0;
    final bool isCleared = hasFee && balance <= 0;

    Color balanceColor;
    IconData balanceIcon;
    String balanceText;

    if (!hasFee) {
      balanceColor = AppColors.grey;
      balanceIcon = Icons.info_outline;
      balanceText = 'No outstanding fees';
    } else if (isCleared) {
      balanceColor = AppColors.success;
      balanceIcon = Icons.check_circle;
      balanceText = 'Fully cleared';
    } else {
      balanceColor = AppColors.warning;
      balanceIcon = Icons.warning_amber_rounded;
      balanceText = 'Owes ₦${balance.toStringAsFixed(2)}';
    }

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
          horizontal: _resp.isVerySmall ? 8 : 12,
          vertical: _resp.isMobile ? 6 : 8),
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
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pupil['class'] as String,
            style: TextStyle(
                fontSize: _resp.smallCaptionSize,
                color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(balanceIcon, size: 12, color: balanceColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  balanceText,
                  style: TextStyle(
                    fontSize: _resp.smallCaptionSize,
                    color: balanceColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhone && !_resp.isVerySmall)
            IconButton(
              padding: EdgeInsets.zero,
              constraints:
              const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.phone,
                  color: AppColors.success, size: _resp.smallIconSize),
              onPressed: () => _makePhoneCall(pupil['teacherPhone']),
              tooltip: 'Call Teacher',
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.message,
                color: AppColors.primary, size: _resp.smallIconSize),
            onPressed: () => _startConversationWithTeacher(pupil),
            tooltip: 'Message',
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.chevron_right,
                color: AppColors.primary, size: _resp.smallIconSize),
            onPressed: () => _showPupilDetails(pupil),
            tooltip: 'Details',
          ),
        ],
      ),
    );
  }

  // ==================== QUICK ACTIONS ====================

  Widget _buildQuickActions() {
    // Fixed 4 items per row across all screen sizes
    const int columns = 4;

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
        _buildActionTile(
            Icons.discount_rounded, 'Discounts', _showDiscountsScreen),
        _buildActionTile(
            Icons.credit_card, 'Request Loan', _navigateToLoanRequest),
        _buildActionTile(Icons.message, 'Messages', _navigateToMessages),
        _buildActionTile(
            Icons.history, 'Payment History', _showTransactionHistory),
        _buildActionTile(Icons.school, 'Pupils', () {
          setState(() => _selectedIndex = 1);
        }),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 2, vertical: _resp.isMobile ? 8 : 10),
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
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: _resp.actionLabelSize,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ASSIGNMENTS ====================

  Widget _buildAssignmentsPreview() {
    if (_isLoadingAssignments) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
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
            Icon(Icons.assignment_turned_in,
                size: 40, color: AppColors.grey),
            const SizedBox(height: 8),
            Text('No assignments yet',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: _resp.bodyTextSize)),
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
        itemBuilder: (context, index) =>
            _buildAssignmentItem(_assignments[index]),
      ),
    );
  }

  Widget _buildAssignmentItem(Map<String, dynamic> assignment) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(
          horizontal: _resp.isVerySmall ? 8 : 12, vertical: 6),
      leading: Container(
        padding: EdgeInsets.all(_resp.isVerySmall ? 6 : 8),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppColors.error.withOpacity(0.1)
              : AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.assignment,
            color: isOverdue ? AppColors.error : AppColors.primary,
            size: _resp.smallIconSize),
      ),
      title: Text(
        assignment['title'] ?? 'Untitled',
        style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: _resp.smallTextSize,
            color: AppColors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Due: ${_formatDate(assignment['dueDate'])}',
        style: TextStyle(
            fontSize: _resp.smallCaptionSize,
            color: isOverdue ? AppColors.error : AppColors.textSecondary),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
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
              fontWeight: FontWeight.w600),
        ),
      ),
      onTap: () => _showAssignmentDetails(assignment),
    );
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(assignment['title'] ?? 'Assignment Details',
            style: const TextStyle(color: AppColors.primary, fontSize: 16),
            overflow: TextOverflow.ellipsis,
            maxLines: 2),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Description:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(assignment['description'] ?? 'No description',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Due Date:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(_formatDate(assignment['dueDate']),
                  style: TextStyle(
                      fontSize: 12,
                      color: isOverdue
                          ? AppColors.error
                          : AppColors.textPrimary)),
              const SizedBox(height: 12),
              const Text('Class:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(assignment['className'] ?? 'N/A',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ==================== NEWS ====================

  Widget _buildNewsAndEvents() {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradientLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
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
          child: Text('No news available',
              style: TextStyle(color: AppColors.textSecondary)),
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
                horizontal: _resp.isVerySmall ? 8 : 12, vertical: 6),
            leading: CircleAvatar(
              radius: _resp.isMobile ? 16 : 18,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Icon(Icons.newspaper,
                  color: AppColors.primary, size: _resp.smallIconSize),
            ),
            title: Text(
              item['title'],
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: _resp.smallTextSize,
                  color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item['date'],
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: Icon(Icons.arrow_forward_ios,
                size: _resp.smallIconSize, color: AppColors.primary),
            onTap: () => _showNewsDetails(item),
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
                  color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.search,
                  color: AppColors.primary, size: _resp.iconSize),
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
                  vertical: _resp.isMobile ? 8 : 10, horizontal: 12),
            ),
          ),
        ),
        if (_isSearchingPupils)
          Container(
            padding:
            EdgeInsets.symmetric(horizontal: _resp.padding, vertical: 6),
            color: AppColors.primary.withOpacity(0.05),
            child: Text(
              'Found ${_filteredPupils.length} child${_filteredPupils.length != 1 ? 'ren' : ''}',
              style: TextStyle(
                  fontSize: _resp.smallTextSize,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500),
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
                  Icon(Icons.search_off,
                      size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text('No children found',
                      style: TextStyle(
                          fontSize: _resp.bodyTextSize,
                          color: AppColors.textSecondary)),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(_resp.padding),
              itemCount: displayList.length,
              itemBuilder: (context, index) =>
                  _buildDetailedPupilCard(displayList[index]),
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

    final double totalFees = (pupil['totalFees'] as num?)?.toDouble() ?? 0.0;
    final double balance = (pupil['balance'] as num?)?.toDouble() ?? 0.0;
    final bool hasFee = totalFees > 0;
    final bool isCleared = hasFee && balance <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(_resp.cardPadding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: _resp.avatarSize,
                height: _resp.avatarSize,
                decoration: const BoxDecoration(
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
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      'Admission: ${pupil['admissionNo']}',
                      style: TextStyle(
                          fontSize: _resp.smallCaptionSize,
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      'Class: ${pupil['class']}',
                      style: TextStyle(
                          fontSize: _resp.smallCaptionSize,
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (hasPhone && !_resp.isVerySmall)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(
                      color: AppColors.success, shape: BoxShape.circle),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    icon: Icon(Icons.phone,
                        color: Colors.white, size: _resp.smallIconSize),
                    onPressed: () => _makePhoneCall(pupil['teacherPhone']),
                    tooltip: 'Call Teacher',
                  ),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.message,
                    color: AppColors.primary, size: _resp.smallIconSize),
                onPressed: () => _startConversationWithTeacher(pupil),
                tooltip: 'Message',
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.chevron_right,
                    color: AppColors.primary, size: _resp.smallIconSize),
                onPressed: () => _showPupilDetails(pupil),
                tooltip: 'Details',
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.discount_rounded,
                    color: AppColors.warning, size: _resp.smallIconSize),
                onPressed: () => _showStudentDiscounts(pupil),
                tooltip: 'Discounts',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCleared
                  ? AppColors.success.withOpacity(0.08)
                  : hasFee
                  ? AppColors.warning.withOpacity(0.08)
                  : AppColors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCleared
                    ? AppColors.success.withOpacity(0.3)
                    : hasFee
                    ? AppColors.warning.withOpacity(0.3)
                    : AppColors.grey.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCleared
                          ? Icons.check_circle
                          : hasFee
                          ? Icons.receipt_long
                          : Icons.info_outline,
                      size: 14,
                      color: isCleared
                          ? AppColors.success
                          : hasFee
                          ? AppColors.warning
                          : AppColors.grey,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Fee Breakdown',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (hasFee)
                  _buildFeeLine(
                    isCleared ? 'Status' : 'Outstanding',
                    isCleared
                        ? 'Fully cleared ✅'
                        : '₦${balance.toStringAsFixed(2)}',
                    isCleared ? AppColors.success : AppColors.warning,
                    bold: true,
                  )
                else
                  Text('No outstanding fees',
                      style: TextStyle(
                          fontSize: _resp.smallCaptionSize,
                          color: AppColors.grey),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: hasFee && !isCleared
                    ? ElevatedButton.icon(
                  onPressed: () => _showFeesScreen(),
                  icon: Icon(Icons.payment,
                      size: _resp.smallIconSize),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Pay Fee',
                        style: TextStyle(
                            fontSize: _resp.buttonTextSize),
                        maxLines: 1),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 6 : 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                )
                    : OutlinedButton(
                  onPressed: () => _showFeesScreen(),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 6 : 8),
                    side: BorderSide(
                        color: hasFee
                            ? AppColors.success
                            : AppColors.info),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('View Fees',
                        style: TextStyle(
                            fontSize: _resp.buttonTextSize,
                            color: hasFee
                                ? AppColors.success
                                : AppColors.info),
                        maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoadingResult
                      ? null
                      : () => _viewPupilResults(pupil),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: _resp.isMobile ? 6 : 8),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoadingResult
                      ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary))
                      : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('View Result',
                        style: TextStyle(
                            fontSize: _resp.buttonTextSize,
                            color: AppColors.primary),
                        maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== WALLET ====================

  Widget _buildWalletScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Wallet',
              style: TextStyle(
                  fontSize: _resp.pageTitleSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(_resp.cardPadding),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                const Text('Available Balance',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.white)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₦${_walletBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: _resp.largeValueSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                    maxLines: 1,
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
                          padding: EdgeInsets.symmetric(
                              vertical: _resp.buttonVerticalPadding),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _resp.isVerySmall ? 'Fund' : 'Fund Wallet',
                            style:
                            TextStyle(fontSize: _resp.buttonTextSize),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showWithdrawDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: AppColors.white),
                          padding: EdgeInsets.symmetric(
                              vertical: _resp.buttonVerticalPadding),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Withdraw',
                              style: TextStyle(
                                  fontSize: _resp.buttonTextSize),
                              maxLines: 1),
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
                const Text('Account Details',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 10),
                _buildInfoRow('Account Name',
                    _accountName.isNotEmpty ? _accountName : 'N/A'),
                _buildInfoRow('Account Number',
                    _accountNumber.isNotEmpty ? _accountNumber : 'N/A'),
                _buildInfoRow('Bank Name',
                    _bankName.isNotEmpty ? _bankName : 'N/A'),
                _buildInfoRow('Ledger Balance',
                    '₦${_ledgerBalance.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PROFILE ====================

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
                    blurRadius: 10),
              ],
            ),
            child: Center(
              child: Text(
                _currentUser.name.isNotEmpty
                    ? _currentUser.name[0].toUpperCase()
                    : 'G',
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
                color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
                const Text('Personal Information',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 12),
                _buildProfileRow(
                    Icons.person,
                    'Full Name',
                    _currentUser.name.isNotEmpty
                        ? _currentUser.name
                        : 'N/A'),
                _buildProfileRow(Icons.email, 'Email', _currentUser.email),
                _buildProfileRow(
                    Icons.phone, 'Phone', _currentUser.phone ?? 'N/A'),
                const SizedBox(height: 12),
                const Text('School Information',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 12),
                _buildProfileRow(
                    Icons.school, 'School', _currentUser.schoolName),
                _buildProfileRow(Icons.calendar_today, 'Session',
                    _currentUser.sessionId),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: _resp.smallIconSize, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: _resp.smallCaptionSize,
                        color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                Text(value,
                    style: TextStyle(
                        fontSize: _resp.smallTextSize,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MORE ====================

  Widget _buildMoreScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('More Options',
              style: TextStyle(
                  fontSize: _resp.pageTitleSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMoreOption(Icons.payments, 'Fees & Payments',
                    'View all outstanding fees', _showFeesScreen),
                _buildMoreOption(Icons.history, 'Payment History',
                    'View all payment transactions', _showTransactionHistory),
                _buildMoreOption(Icons.assignment, 'All Assignments',
                    'View all assignments', _showAllAssignments),
                _buildMoreOption(Icons.discount_rounded, 'Student Discounts',
                    'View all discounts', _showDiscountsScreen),
                _buildMoreOption(Icons.message, 'Messages',
                    'View all messages', _navigateToMessages),
                _buildMoreOption(Icons.newspaper, 'All News',
                    'View all news', _showAllNews),
                _buildMoreOption(Icons.credit_card, 'Request Loan',
                    'Apply for a loan', _navigateToLoanRequest),
                _buildMoreOption(Icons.help, 'Help & Support',
                    'Get assistance', () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Help & Support',
                              style: TextStyle(color: AppColors.primary)),
                          content: const Text(
                            'For assistance, please contact:\n\n'
                                '📧 support@educatmobile.com\n'
                                '📞 +234 800 000 0000\n\n'
                                'Our team is available 24/7 to help you.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }),
                _buildMoreOption(
                    Icons.logout, 'Logout', 'Sign out', _showLogoutDialog,
                    isDestructive: true),
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
          horizontal: _resp.isVerySmall ? 8 : 12,
          vertical: _resp.isMobile ? 6 : 8),
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.primary,
        size: _resp.iconSize,
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDestructive ? AppColors.error : AppColors.textPrimary,
              fontSize: _resp.bodyTextSize),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: _resp.smallTextSize,
              color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
      trailing: Icon(Icons.arrow_forward_ios,
          size: _resp.smallIconSize, color: AppColors.primary),
      onTap: onTap,
    );
  }

  // ==================== LOAN APPLICATIONS ====================

  Widget _buildLoanApplicationsSection() {
    final activeApps = _loanProvider.activeApplications;
    final hasActiveApps = activeApps.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
            'Loan Applications', hasActiveApps ? 'View All' : null),
        const SizedBox(height: 8),
        if (_loanProvider.isLoading)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradientLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
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
                Icon(Icons.credit_card_off,
                    size: 40, color: AppColors.grey),
                const SizedBox(height: 8),
                Text('No active loan applications',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: _resp.bodyTextSize),
                    textAlign: TextAlign.center),
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
              itemBuilder: (context, index) =>
                  _buildLoanApplicationTile(activeApps[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildLoanApplicationTile(LoanApplication application) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
          horizontal: _resp.isVerySmall ? 8 : 12, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: application.statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(application.statusIcon,
            color: application.statusColor, size: _resp.smallIconSize),
      ),
      title: Text(
        'Application #${application.id.length > 8 ? application.id.substring(0, 8) : application.id}',
        style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: _resp.smallTextSize,
            color: AppColors.textPrimary),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: ${application.statusDisplay}',
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: application.statusColor,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          if (application.requestedAmount != null)
            Text(
              'Amount: ₦${application.requestedAmount!.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          Text('Updated: ${_formatDate(application.updatedAt.toString())}',
              style: TextStyle(
                  fontSize: _resp.smallCaptionSize,
                  color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ],
      ),
      trailing: Icon(Icons.chevron_right,
          color: AppColors.primary, size: _resp.smallIconSize),
      onTap: () => _navigateToLoanApplication(application),
    );
  }

  // ==================== DISCOUNT CARDS ====================

  Widget _buildStudentDiscountCard(
      Map<String, dynamic> pupil, List<DiscountModel> discounts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_resp.isVerySmall ? 10 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: discounts.isNotEmpty
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: _resp.isVerySmall ? 16 : 22,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  pupil['name'][0].toUpperCase(),
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: _resp.isVerySmall ? 13 : 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pupil['name'],
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: _resp.isVerySmall ? 13 : 15,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    Text(pupil['class'],
                        style: TextStyle(
                            fontSize: _resp.smallCaptionSize,
                            color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: discounts.isEmpty
                      ? Colors.grey[200]
                      : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  discounts.isEmpty ? 'None' : '${discounts.length}',
                  style: TextStyle(
                      fontSize: _resp.isVerySmall ? 10 : 12,
                      fontWeight: FontWeight.w600,
                      color: discounts.isEmpty
                          ? Colors.grey[600]
                          : AppColors.success),
                ),
              ),
            ],
          ),
          if (discounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...discounts.map((d) => _buildDiscountItem(d)),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountItem(DiscountModel discount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(_resp.isVerySmall ? 8 : 10),
      decoration: BoxDecoration(
        color: discount.isValid
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: discount.isValid
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: discount.isValid
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              discount.isValid ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: discount.isValid ? AppColors.success : AppColors.grey,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(discount.discountType,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: _resp.isVerySmall ? 11 : 13,
                        color: discount.isValid
                            ? AppColors.textPrimary
                            : AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                if (discount.description.isNotEmpty)
                  Text(discount.description,
                      style: TextStyle(
                          fontSize: _resp.smallCaptionSize,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(discount.formattedAmount,
                          style: TextStyle(
                              fontSize: _resp.smallCaptionSize,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: discount.statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(discount.statusText,
                          style: TextStyle(
                              fontSize: _resp.smallCaptionSize,
                              color: discount.statusColor,
                              fontWeight: FontWeight.w500)),
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

  // ==================== HMO RECORD ====================

  Widget _buildHMORecordCard(Map<String, dynamic> record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(_resp.isVerySmall ? 8 : 12),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: record['visitType'] == 'School'
                      ? AppColors.info.withOpacity(0.1)
                      : AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  record['visitType'] == 'School'
                      ? Icons.school
                      : Icons.home,
                  size: 16,
                  color: record['visitType'] == 'School'
                      ? AppColors.info
                      : AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record['hospitalName'] ?? 'Hospital Visit',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: _resp.isVerySmall ? 12 : 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    Text(record['date'] ?? 'Date not specified',
                        style: TextStyle(
                            fontSize: _resp.smallCaptionSize,
                            color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: record['hmoCovered'] == true
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  record['hmoCovered'] == true ? 'HMO' : 'Out of Pocket',
                  style: TextStyle(
                      fontSize: _resp.smallCaptionSize,
                      color: record['hmoCovered'] == true
                          ? AppColors.success
                          : AppColors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (record['diagnosis'] != null &&
              record['diagnosis'].toString().isNotEmpty)
            Text('Diagnosis: ${record['diagnosis']}',
                style: TextStyle(fontSize: _resp.smallTextSize),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          if (record['treatment'] != null &&
              record['treatment'].toString().isNotEmpty)
            Text('Treatment: ${record['treatment']}',
                style: TextStyle(fontSize: _resp.smallTextSize),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          if (record['doctorName'] != null &&
              record['doctorName'].toString().isNotEmpty)
            Text('Doctor: ${record['doctorName']}',
                style: TextStyle(
                    fontSize: _resp.smallCaptionSize,
                    color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Cost',
                    style: TextStyle(
                        fontSize: _resp.smallCaptionSize,
                        color: AppColors.textSecondary)),
                Text(
                  '₦${(record['cost'] as double).toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _resp.smallTextSize,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MISC ====================

  void _showTransactionHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PaymentHistoryScreen(),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title:
        const Text('Logout', style: TextStyle(color: AppColors.error)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LoginScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ==================== RESPONSIVE INFO ====================

class ResponsiveInfo {
  final double screenWidth;

  ResponsiveInfo(this.screenWidth);

  bool get isVerySmall => screenWidth < 380;
  bool get isMobile => screenWidth < 600;
  bool get isTablet => screenWidth >= 600 && screenWidth < 1200;
  bool get isDesktop => screenWidth >= 1200;

  double get padding => isVerySmall ? 8 : isMobile ? 12 : isTablet ? 16 : 20;
  double get cardPadding =>
      isVerySmall ? 8 : isMobile ? 10 : isTablet ? 12 : 16;
  double get gridSpacing => isVerySmall ? 6 : isMobile ? 8 : 12;

  int get statsGridColumns =>
      isVerySmall ? 2 : isMobile ? 2 : (isTablet ? 3 : 4);
  int get quickActionsColumns =>
      isVerySmall ? 3 : isMobile ? 4 : (isTablet ? 5 : 6);
  double get statsAspectRatio => isMobile ? 1.4 : 1.3;
  double get actionAspectRatio => isVerySmall ? 1.0 : isMobile ? 1.0 : 0.9;

  double get titleSize =>
      isVerySmall ? 18 : isMobile ? 20 : (isTablet ? 24 : 28);
  double get pageTitleSize =>
      isVerySmall ? 20 : isMobile ? 24 : (isTablet ? 28 : 32);
  double get sectionTitleSize =>
      isVerySmall ? 14 : isMobile ? 16 : (isTablet ? 18 : 20);
  double get bodyTextSize =>
      isVerySmall ? 12 : isMobile ? 13 : (isTablet ? 14 : 15);
  double get smallTextSize =>
      isVerySmall ? 10 : isMobile ? 11 : (isTablet ? 12 : 13);
  double get captionSize =>
      isVerySmall ? 9 : isMobile ? 10 : (isTablet ? 11 : 12);
  double get smallCaptionSize =>
      isVerySmall ? 8 : isMobile ? 9 : (isTablet ? 10 : 11);
  double get valueSize =>
      isVerySmall ? 13 : isMobile ? 14 : (isTablet ? 16 : 18);
  double get largeValueSize =>
      isVerySmall ? 22 : isMobile ? 28 : (isTablet ? 32 : 36);

  double get iconSize =>
      isVerySmall ? 18 : isMobile ? 20 : (isTablet ? 22 : 24);
  double get smallIconSize =>
      isVerySmall ? 14 : isMobile ? 16 : (isTablet ? 18 : 20);

  double get avatarSize =>
      isVerySmall ? 34 : isMobile ? 40 : (isTablet ? 45 : 50);
  double get avatarLargeSize =>
      isVerySmall ? 70 : isMobile ? 80 : (isTablet ? 90 : 100);
  double get avatarTextSize =>
      isVerySmall ? 14 : isMobile ? 16 : (isTablet ? 18 : 20);
  double get avatarLargeTextSize =>
      isVerySmall ? 28 : isMobile ? 32 : (isTablet ? 36 : 40);

  double get buttonTextSize =>
      isVerySmall ? 10 : isMobile ? 11 : (isTablet ? 12 : 13);
  double get buttonVerticalPadding =>
      isVerySmall ? 6 : isMobile ? 8 : (isTablet ? 10 : 12);
  double get actionLabelSize =>
      isVerySmall ? 8 : isMobile ? 9 : (isTablet ? 10 : 11);
}