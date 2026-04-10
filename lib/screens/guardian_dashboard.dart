import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
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
  double _walletBalance = 0.00;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Account details
  String _accountNumber = '';
  String _accountName = '';
  double _ledgerBalance = 0.00;

  // News data
  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  // HMO Data
  List<Map<String, dynamic>> _hospitalRecords = [];
  bool _isLoadingHMO = false;
  int _selectedPupilForHMO = 0;

  // Controllers
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadUserData();
    _fetchDashboardData();
  }

  void _loadUserData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;
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

    // Fetch students
    final studentsResult = await _apiService.getGuardianStudents(
      token: token,
      guardianId: _currentUser.id,
    );

    if (studentsResult['success'] && mounted) {
      final studentsData = studentsResult['data'] as List? ?? [];

      final List<Map<String, dynamic>> mappedPupils = studentsData.map((student) {
        return {
          'id': student['studentId'] ?? '',
          'name': '${student['firstname'] ?? ''} ${student['lastname'] ?? ''}'.trim(),
          'class': student['classroom']?['name'] ?? student['classroomId'] ?? 'N/A',
          'classroomId': student['classroomId'] ?? '',
          'feeStatus': 'Pending',
          'feeAmount': 0.0,
          'averageScore': 0,
          'attendance': 0,
          'admissionNo': student['studentNo'] ?? '',
          'teacherName': student['teacher'] != null
              ? '${student['teacher']['firstname'] ?? ''} ${student['teacher']['lastname'] ?? ''}'.trim()
              : 'Not Assigned',
          'teacherPhone': student['teacher']?['phone'] ?? 'Not available',
          'teacherEmail': student['teacher']?['email'] ?? 'Not available',
        };
      }).toList();

      setState(() {
        _pupils = mappedPupils;
      });

      // Fetch wallet and account details
      await _fetchWalletAndAccount(token);

      // Fetch news
      await _fetchNews(token);

      setState(() {
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _errorMessage = studentsResult['message'] ?? 'Failed to load students data';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchWalletAndAccount(String token) async {
    final accountResult = await _apiService.getGuardianSavingsAccount(
      token: token,
      guardianId: _currentUser.id,
    );

    if (accountResult['success'] && mounted) {
      setState(() {
        _walletBalance = accountResult['balance'];
        _accountNumber = accountResult['accountNumber'] ?? '';
        _accountName = accountResult['accountName'] ?? '';
        _ledgerBalance = accountResult['ledgerBalance'] ?? 0.0;
      });
    }
  }

  Future<void> _fetchNews(String token) async {
    setState(() {
      _isLoadingNews = true;
    });

    final newsResult = await _apiService.getAllNews(token: token);

    if (newsResult['success'] && mounted) {
      final newsData = newsResult['data'] as List? ?? [];
      setState(() {
        _news = newsData.map((item) => {
          'id': item['id'] ?? '',
          'title': item['title'] ?? 'No Title',
          'content': item['content'] ?? item['description'] ?? '',
          'date': _formatDate(item['date'] ?? item['publishedDate'] ?? item['createdAt']),
          'author': item['author'] ?? 'School Admin',
        }).toList();
        _isLoadingNews = false;
      });
    } else {
      setState(() {
        _isLoadingNews = false;
      });
    }
  }

  // Future<void> _fetchHospitalRecords(String token, String studentId) async {
  //   setState(() {
  //     _isLoadingHMO = true;
  //   });
  //
  //   final recordsResult = await _apiService.getChildHospitalRecords(
  //     token: token,
  //     studentId: studentId,
  //     schoolId: _currentUser.schoolId,
  //     sessionId: _currentUser.sessionId,
  //   );
  //
  //   if (recordsResult['success'] && mounted) {
  //     setState(() {
  //       _hospitalRecords = (recordsResult['data'] as List?)?.map((record) => {
  //         'id': record['id'],
  //         'date': record['visitDate'] ?? record['date'],
  //         'hospitalName': record['hospitalName'],
  //         'diagnosis': record['diagnosis'],
  //         'treatment': record['treatment'],
  //         'doctorName': record['doctorName'],
  //         'visitType': record['visitType'] ?? 'School',
  //         'cost': record['cost'] ?? 0.0,
  //         'hmoCovered': record['hmoCovered'] ?? true,
  //       }).toList() ?? [];
  //       _isLoadingHMO = false;
  //     });
  //   } else {
  //     setState(() {
  //       _isLoadingHMO = false;
  //     });
  //   }
  // }

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
    setState(() {
      _isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
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
          BottomNavigationBarItem(icon: Icon(Icons.school_rounded), label: 'Pupils'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildHomeScreen() {
    double outstandingFees = _pupils.fold(0.0, (sum, pupil) {
      if (pupil['feeStatus'] == 'Pending') return sum + (pupil['feeAmount'] as double);
      return sum;
    });

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildWalletCard(),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _buildStatCard('Total Pupils', '${_pupils.length}', Icons.people, AppColors.primary),
              _buildStatCard('Outstanding Fees', '₦${outstandingFees.toStringAsFixed(0)}', Icons.payments, AppColors.error),
              _buildStatCard('Active Loans', '₦0', Icons.credit_card, AppColors.warning),
              _buildStatCard('HMO Active', 'Yes', Icons.health_and_safety, AppColors.success),
            ],
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('My Children', 'View All'),
          const SizedBox(height: 12),
          _buildPupilsList(),
          const SizedBox(height: 20),
          _buildSectionTitle('Quick Actions', null),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 20),
          _buildSectionTitle('News & Events', null),
          const SizedBox(height: 12),
          _buildNewsAndEvents(),
        ],
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
            Text(
              _currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian',
              style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(_currentUser.schoolName, style: TextStyle(color: AppColors.white.withOpacity(0.8), fontSize: 14)),
          ],
        ),
        GestureDetector(
          onTap: () => setState(() => _selectedIndex = 3),
          child: Container(
            width: 55, height: 55,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.white, AppColors.cream]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
            ),
            child: Center(
              child: Text(
                _currentUser.name.isNotEmpty ? _currentUser.name[0].toUpperCase() : 'G',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.white, AppColors.cream]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Wallet Balance', style: TextStyle(fontSize: 14, color: AppColors.grey)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Active', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₦${_walletBalance.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _showFundWalletDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Fund Wallet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _showLoanRequestDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Get Loan'),
                ),
              ),
            ],
          ),
        ],
      ),
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

  Widget _buildSectionTitle(String title, String? action) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.white)),
        if (action != null)
          Text(action, style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPupilsList() {
    if (_pupils.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
        child: const Center(child: Text('No wards found', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _pupils.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final pupil = _pupils[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text((pupil['name'] as String)[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(pupil['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pupil['class'] as String),
                Text('Teacher: ${pupil['teacherName']}', style: const TextStyle(fontSize: 12, color: AppColors.grey)),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pupil['feeStatus'] == 'Paid' ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(pupil['feeStatus'] as String, style: TextStyle(fontSize: 12, color: pupil['feeStatus'] == 'Paid' ? AppColors.success : AppColors.error)),
            ),
            onTap: () => _showPupilDetails(pupil),
          );
        },
      ),
    );
  }

  Widget _buildQuickActions() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1,
      children: [
        _buildActionTile(Icons.payments, 'Pay Fees', () => _showFeesScreen()),
        _buildActionTile(Icons.grade, 'Results', () => _showResultsScreen()),
        _buildActionTile(Icons.local_hospital, 'HMO', () => _showHMOScreen()),
        _buildActionTile(Icons.history, 'History', () => _showTransactionHistory()),
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

  Widget _buildNewsAndEvents() {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_news.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
        child: const Center(child: Text('No news available', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _news.length > 5 ? 5 : _news.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _news[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Icon(Icons.newspaper, color: AppColors.primary),
            ),
            title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item['date'] as String),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showNewsDetails(item),
          );
        },
      ),
    );
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 1: return _buildPupilsScreen();
      case 2: return _buildWalletScreen();
      case 3: return _buildProfileScreen();
      case 4: return _buildMoreScreen();
      default: return _buildHomeScreen();
    }
  }

  Widget _buildPupilsScreen() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Children', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.white)),
            const SizedBox(height: 20),
            ..._pupils.map((pupil) => _buildDetailedPupilCard(pupil)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedPupilCard(Map<String, dynamic> pupil) {
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
                child: Center(child: Text((pupil['name'] as String)[0].toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.white))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pupil['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Admission: ${pupil['admissionNo']}', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  Text('Class: ${pupil['class']}', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: pupil['feeStatus'] == 'Paid' ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(pupil['feeStatus'] as String, style: TextStyle(color: pupil['feeStatus'] == 'Paid' ? AppColors.success : AppColors.error, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Class Teacher', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.person, size: 14, color: AppColors.grey), const SizedBox(width: 8), Expanded(child: Text(pupil['teacherName'] as String, style: const TextStyle(fontSize: 13)))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.phone, size: 14, color: AppColors.grey), const SizedBox(width: 8), Text(pupil['teacherPhone'] as String, style: const TextStyle(fontSize: 13))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.email, size: 14, color: AppColors.grey), const SizedBox(width: 8), Expanded(child: Text(pupil['teacherEmail'] as String, style: const TextStyle(fontSize: 13)))]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _payFeesForPupil(pupil),
                  icon: const Icon(Icons.payments),
                  label: const Text('Pay Fees'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _viewPupilResults(pupil),
                  icon: const Icon(Icons.grade),
                  label: const Text('View Result'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Wallet', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.white)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                const Text('Available Balance', style: TextStyle(fontSize: 16, color: AppColors.grey)),
                const SizedBox(height: 8),
                Text('₦${_walletBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showFundWalletDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Fund Wallet'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showWithdrawDialog,
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Withdraw'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 16),
                _buildDetailRow('Account Name', _accountName.isNotEmpty ? _accountName : 'N/A'),
                _buildDetailRow('Account Number', _accountNumber.isNotEmpty ? _accountNumber : 'N/A'),
                _buildDetailRow('Ledger Balance', '₦${_ledgerBalance.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.white, AppColors.cream]), shape: BoxShape.circle),
            child: Center(child: Text((_currentUser.name.isNotEmpty ? _currentUser.name[0] : 'G').toUpperCase(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.primary))),
          ),
          const SizedBox(height: 16),
          Text(_currentUser.name.isNotEmpty ? _currentUser.name : 'Guardian', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.white)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 20),
                _buildProfileRow(Icons.person, 'Full Name', _currentUser.name.isNotEmpty ? _currentUser.name : 'N/A'),
                _buildProfileRow(Icons.email, 'Email', _currentUser.email),
                _buildProfileRow(Icons.phone, 'Phone', _currentUser.phone ?? 'N/A'),
                const SizedBox(height: 16),
                const Text('School Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 16),
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

  Widget _buildMoreScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('More Options', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.white)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(color: AppColors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                _buildMoreOption(Icons.newspaper, 'All News', 'View all news', () => _showAllNews()),
                _buildMoreOption(Icons.help, 'Help & Support', 'Get assistance', () {}),
                _buildMoreOption(Icons.logout, 'Logout', 'Sign out', _showLogoutDialog, isDestructive: true),
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
      title: Text(title, style: TextStyle(color: isDestructive ? AppColors.error : AppColors.black)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 14)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.grey)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  // Action Methods
  void _showFundWalletDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fund Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send payment to:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _buildDetailRow('Account Name', _accountName.isNotEmpty ? _accountName : 'CHIDON MONTESORRI SCHOOL'),
                  _buildDetailRow('Account Number', _accountNumber.isNotEmpty ? _accountNumber : 'CHI9578732'),
                  _buildDetailRow('Bank Name', 'Wema Bank'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _accountNumber));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account number copied!'), backgroundColor: AppColors.success));
            },
            child: const Text('Copy Number'),
          ),
        ],
      ),
    );
  }

  void _showLoanRequestDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Loan'),
        content: const Text('Loan request feature coming soon. Please visit the school for assistance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showWithdrawDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds'),
        content: const Text('Withdrawal feature coming soon. Please contact support for assistance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showFeesScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pay School Fees', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._pupils.map((pupil) => ListTile(
              title: Text(pupil['name']),
              subtitle: Text(pupil['class']),
              trailing: const Text('₦0', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _payFeesForPupil(pupil);
              },
            )).toList(),
          ],
        ),
      ),
    );
  }

  void _payFeesForPupil(Map<String, dynamic> pupil) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay Fees for ${pupil['name']}'),
        content: const Text('Fee payment feature coming soon.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showResultsScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('View Results', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._pupils.map((pupil) => ListTile(
              title: Text(pupil['name']),
              subtitle: Text(pupil['class']),
              trailing: const Text('0%'),
              onTap: () {
                Navigator.pop(context);
                _viewPupilResults(pupil);
              },
            )).toList(),
          ],
        ),
      ),
    );
  }

  Future<void> _viewPupilResults(Map<String, dynamic> pupil) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await Future.delayed(const Duration(seconds: 1));
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${pupil['name']} - Results'),
        content: const Text('No results available yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showHMOScreen() {
    if (_pupils.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pupils found'), backgroundColor: AppColors.warning));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Health Records', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedPupilForHMO,
                  decoration: const InputDecoration(labelText: 'Select Child'),
                  items: _pupils.asMap().entries.map((entry) {
                    return DropdownMenuItem(value: entry.key, child: Text(entry.value['name']));
                  }).toList(),
                  onChanged: (value) async {
                    setState(() => _selectedPupilForHMO = value ?? 0);
                    final token = Provider.of<AuthProvider>(context, listen: false).token;
                    if (token != null) {
                     // await _fetchHospitalRecords(token, _pupils[_selectedPupilForHMO]['id']);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoadingHMO
                      ? const Center(child: CircularProgressIndicator())
                      : _hospitalRecords.isEmpty
                      ? const Center(child: Text('No hospital records found'))
                      : ListView.builder(
                    itemCount: _hospitalRecords.length,
                    itemBuilder: (context, index) {
                      final record = _hospitalRecords[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.local_hospital),
                          title: Text(record['hospitalName'] ?? 'Hospital Visit'),
                          subtitle: Text('${record['date']} - ${record['diagnosis'] ?? 'N/A'}'),
                          trailing: Chip(
                            label: Text(record['visitType'] ?? 'School'),
                            backgroundColor: record['visitType'] == 'School' ? AppColors.info.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                          ),
                        ),
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

  void _showTransactionHistory() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Transaction History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const ListTile(title: Text('No transactions yet'), leading: Icon(Icons.history)),
          ],
        ),
      ),
    );
  }

  void _showPupilDetails(Map<String, dynamic> pupil) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              CircleAvatar(radius: 30, child: Text((pupil['name'] as String)[0])),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(pupil['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(pupil['class']), Text('Admission: ${pupil['admissionNo']}')])),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildQuickChip(Icons.payments, 'Pay Fees', () => _payFeesForPupil(pupil))),
                const SizedBox(width: 8),
                Expanded(child: _buildQuickChip(Icons.grade, 'Results', () => _viewPupilResults(pupil))),
                const SizedBox(width: 8),
                Expanded(child: _buildQuickChip(Icons.local_hospital, 'HMO', () => _showHMOScreen())),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [Icon(icon, color: AppColors.primary, size: 20), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11))]),
      ),
    );
  }

  void _showAllNews() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('All News', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: _news.isEmpty
                  ? const Center(child: Text('No news available'))
                  : ListView.builder(
                itemCount: _news.length,
                itemBuilder: (context, index) {
                  final item = _news[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(item['date']),
                      onTap: () => _showNewsDetails(item),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}