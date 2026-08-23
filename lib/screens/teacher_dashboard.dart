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
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ==================== CONSTANTS ====================

const kPrimary = Color(0xFFFF6B35);
const kPrimaryLight = Color(0xFFFF8A5C);
const kPrimaryDark = Color(0xFFE85A2A);
const kSecondary = Color(0xFF1A2340);
const kBackground = Color(0xFFF8F9FA);
const kCardBg = Colors.white;
const kSuccess = Color(0xFF2ECC71);
const kWarning = Color(0xFFF39C12);
const kDanger = Color(0xFFE74C3C);
const kInfo = Color(0xFF3498DB);
const kPurple = Color(0xFF9B59B6);
const kTextPrimary = Color(0xFF2C3E50);
const kTextSecondary = Color(0xFF7F8C8D);
const kBorder = Color(0xFFECF0F1);
const kShadow = Color(0x1A000000);

// ==================== RESPONSIVE DATA ====================

class ResponsiveData {
  final BuildContext context;

  ResponsiveData(this.context);

  double get screenWidth => MediaQuery.of(context).size.width;

  bool get isMobile => screenWidth < 600;
  bool get isTablet => screenWidth >= 600 && screenWidth < 1200;
  bool get isDesktop => screenWidth >= 1200;

  double get padding => isMobile ? 16 : (isTablet ? 24 : 32);
  double get spacing => isMobile ? 12 : (isTablet ? 16 : 20);
  double get radius => isMobile ? 12 : (isTablet ? 16 : 20);

  double get fontSizeH1 => isMobile ? 24 : (isTablet ? 28 : 32);
  double get fontSizeH2 => isMobile ? 20 : (isTablet ? 24 : 28);
  double get fontSizeH3 => isMobile ? 16 : (isTablet ? 18 : 20);
  double get fontSizeBody => isMobile ? 14 : (isTablet ? 15 : 16);
  double get fontSizeMedium => isMobile ? 16 : (isTablet ? 18 : 20);
  double get fontSizeSmall => isMobile ? 12 : (isTablet ? 13 : 14);
  double get fontSizeCaption => isMobile ? 10 : (isTablet ? 11 : 12);

  int get gridColumns => isMobile ? 2 : (isTablet ? 3 : 4);
  int get quickActionsCount => isMobile ? 4 : (isTablet ? 6 : 8);
  double get slideshowHeight => isMobile ? 150.0 : (isTablet ? 180.0 : 200.0);
}

// ==================== CLOCK IN/OUT WIDGET ====================

class ClockInOutWidget extends StatefulWidget {
  final UserModel user;
  final ApiService apiService;
  final VoidCallback onStatusChanged;

  const ClockInOutWidget({
    super.key,
    required this.user,
    required this.apiService,
    required this.onStatusChanged,
  });

  @override
  State<ClockInOutWidget> createState() => _ClockInOutWidgetState();
}

class _ClockInOutWidgetState extends State<ClockInOutWidget> {
  bool _isLoading = false;
  bool _isClockedIn = false;
  String? _clockInTime;
  String? _clockOutTime;
  String? _statusMessage;
  bool _isLoadingStatus = true;
  String? _scannedQrCode;

  double _latitude = 6.636814;
  double _longitude = 3.514077;

  @override
  void initState() {
    super.initState();
    _loadAttendanceStatus();
  }

  Future<void> _loadAttendanceStatus() async {
    setState(() => _isLoadingStatus = true);

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final clockInKey = 'clock_in_${widget.user.id}_$dateKey';
    final clockOutKey = 'clock_out_${widget.user.id}_$dateKey';

    _clockInTime = prefs.getString(clockInKey);
    _clockOutTime = prefs.getString(clockOutKey);
    _isClockedIn = _clockInTime != null && _clockOutTime == null;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      if (token != null) {
        final result = await widget.apiService.getTeacherAttendanceStatus(
          token: token,
          teacherId: widget.user.id,
        );
        if (result['success'] && mounted) {
          final data = result['data'];
          if (data != null) {
            setState(() {
              if (data['clockInTime'] != null) {
                _clockInTime = data['clockInTime'];
                prefs.setString(clockInKey, _clockInTime!);
              }
              if (data['clockOutTime'] != null) {
                _clockOutTime = data['clockOutTime'];
                prefs.setString(clockOutKey, _clockOutTime!);
              }
              _isClockedIn = _clockInTime != null && _clockOutTime == null;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading attendance status: $e');
    }

    setState(() => _isLoadingStatus = false);
  }

  void _showQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Scan QR Code',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kSecondary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: kSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (detectEvent) {
                  final barcodes = detectEvent.barcodes;
                  if (barcodes.isNotEmpty) {
                    final qrCodeValue = barcodes.first.rawValue;
                    if (qrCodeValue != null && qrCodeValue.isNotEmpty) {
                      Navigator.pop(context);
                      _clockInWithQrCode(qrCodeValue);
                    }
                  }
                },
                errorBuilder: (context, error, child) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: kDanger),
                        const SizedBox(height: 16),
                        const Text(
                          'Camera Error',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: kSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please grant camera permission to scan QR codes',
                          style: TextStyle(color: kTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showManualQrEntry();
                    },
                    child: const Text('Enter Manually'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualQrEntry() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Enter QR Code',
          style: TextStyle(color: kSecondary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste or type the QR code value from the admin dashboard',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.pop(context);
                  _clockInWithQrCode(value);
                }
              },
              decoration: InputDecoration(
                hintText: 'Paste QR Code here',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kPrimary),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clock In'),
          ),
        ],
      ),
    );
  }

  Future<void> _clockInWithQrCode(String qrCodeValue) async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null) {
        _showError('Not authenticated. Please login again.');
        setState(() => _isLoading = false);
        return;
      }

      final qrParts = qrCodeValue.split('|');
      if (qrParts.length != 4 || qrParts[0] != 'SCHOOL_ATTENDANCE') {
        _showError('Invalid QR Code format. Please scan a valid attendance QR code.');
        setState(() => _isLoading = false);
        return;
      }

      final qrSchoolId = qrParts[1];
      if (qrSchoolId != widget.user.schoolId) {
        _showError('This QR code is for a different school.');
        setState(() => _isLoading = false);
        return;
      }

      final deviceInfo = await _getDeviceInfo();
      final ipAddress = await _getIpAddress();

      final result = await widget.apiService.clockIn(
        token: token,
        teacherId: widget.user.id,
        schoolId: widget.user.schoolId,
        qrCodeValue: qrCodeValue,
        latitude: _latitude,
        longitude: _longitude,
        deviceModel: deviceInfo['model'] ?? 'Unknown',
        appVersion: 'v1',
        ipAddress: ipAddress,
        userAgent: 'educat',
      );

      if (result['success'] && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now();
        final dateKey = '${today.year}-${today.month}-${today.day}';
        final clockInKey = 'clock_in_${widget.user.id}_$dateKey';

        final data = result['data'];
        if (data != null && data['clockInTime'] != null) {
          _clockInTime = data['clockInTime'];
          await prefs.setString(clockInKey, _clockInTime!);
        } else {
          _clockInTime = DateTime.now().toIso8601String();
          await prefs.setString(clockInKey, _clockInTime!);
        }

        _isClockedIn = true;
        _clockOutTime = null;
        _scannedQrCode = qrCodeValue;

        setState(() => _statusMessage = '✅ Clock in successful!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Clock in successful!'), backgroundColor: kSuccess),
        );
        widget.onStatusChanged();
      } else {
        _showError(result['message'] ?? 'Clock in failed. Please try again.');
      }
    } catch (e) {
      print('Clock in error: $e');
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clockOut() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null) {
        _showError('Not authenticated. Please login again.');
        setState(() => _isLoading = false);
        return;
      }

      final result = await widget.apiService.clockOut(
        token: token,
        schoolId: widget.user.schoolId,
        teacherId: widget.user.id,
      );

      if (result['success'] && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now();
        final dateKey = '${today.year}-${today.month}-${today.day}';
        final clockOutKey = 'clock_out_${widget.user.id}_$dateKey';

        final data = result['data'];
        if (data != null && data['clockOutTime'] != null) {
          _clockOutTime = data['clockOutTime'];
          await prefs.setString(clockOutKey, _clockOutTime!);
        } else {
          _clockOutTime = DateTime.now().toIso8601String();
          await prefs.setString(clockOutKey, _clockOutTime!);
        }

        _isClockedIn = false;
        _scannedQrCode = null;

        setState(() => _statusMessage = '✅ Clock out successful!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Clock out successful!'), backgroundColor: kSuccess),
        );
        widget.onStatusChanged();
      } else {
        _showError(result['message'] ?? 'Clock out failed. Please try again.');
      }
    } catch (e) {
      print('Clock out error: $e');
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    setState(() => _statusMessage = '❌ $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: kDanger),
    );
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return {
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        return {
          'model': iosInfo.model,
          'manufacturer': 'Apple',
          'version': iosInfo.systemVersion,
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }
    return {'model': 'Unknown', 'manufacturer': 'Unknown', 'version': '1.0'};
  }

  Future<String> _getIpAddress() async {
    try {
      final networkInfo = NetworkInfo();
      final ip = await networkInfo.getWifiIP();
      return ip ?? '0.0.0.0';
    } catch (e) {
      print('Error getting IP: $e');
      return '0.0.0.0';
    }
  }

  String _formatTime(String timestamp) {
    try {
      final time = DateTime.parse(timestamp);
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resp = ResponsiveData(context);

    return Container(
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimary, kPrimaryDark],
        ),
        borderRadius: BorderRadius.circular(resp.radius + 4),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isClockedIn ? Icons.work_rounded : Icons.work_outline_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isClockedIn ? 'Currently Clocked In' : 'Not Clocked In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_clockInTime != null)
                      Text(
                        'In: ${_formatTime(_clockInTime!)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _isClockedIn
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isClockedIn ? 'ACTIVE' : 'OFF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingStatus)
            const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading || _isClockedIn ? null : _showQrScanner,
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        label: const Text('Scan QR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading || _isClockedIn ? null : () {
                          if (_scannedQrCode != null) {
                            _clockInWithQrCode(_scannedQrCode!);
                          } else {
                            _showQrScanner();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading && !_isClockedIn
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kPrimary,
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _scannedQrCode != null ? Icons.qr_code : Icons.login_rounded,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _scannedQrCode != null ? 'Clock In' : 'Clock In',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading || !_isClockedIn ? null : _clockOut,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isClockedIn ? kDanger : Colors.white.withOpacity(0.3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading && _isClockedIn
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Clock Out',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (_scannedQrCode != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'QR Code scanned',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

// ==================== TEACHER DASHBOARD ====================

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

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _classrooms = [];
  String _selectedClassroomId = '';
  String _selectedClassName = '';
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  Map<String, Map<String, bool>> _attendanceRecords = {};
  DateTime _attendanceDate = DateTime.now();
  bool _isSavingAttendance = false;
  Set<String> _savedAttendanceDates = {};

  List<Map<String, dynamic>> _subjects = [];
  Map<String, Map<String, Map<String, dynamic>>> _studentScores = {};
  bool _isSavingResults = false;
  bool _isLoadingSubjects = false;

  List<Map<String, dynamic>> _news = [];
  bool _isLoadingNews = false;

  bool _isAddingSubject = false;
  final TextEditingController _subjectNameController = TextEditingController();
  final TextEditingController _subjectDescriptionController = TextEditingController();

  List<Map<String, dynamic>> _assignments = [];
  bool _isLoadingAssignments = false;
  String? _selectedAssignmentClassId;

  int _unreadMessageCount = 0;

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

  @override
  void dispose() {
    _searchController.dispose();
    _subjectNameController.dispose();
    _subjectDescriptionController.dispose();
    _pageController.dispose();
    super.dispose();
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
      setState(() => _unreadMessageCount = unreadCount);
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
        await _fetchSubjectsFromApi(token, _selectedClassroomId);
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

  Future<void> _fetchSubjectsFromApi(String token, String classroomId) async {
    setState(() { _isLoadingSubjects = true; });

    try {
      final result = await _apiService.getSubjectsByClass(
        token: token,
        schoolId: _currentUser.schoolId,
        classroomId: classroomId,
      );

      if (result['success'] && mounted) {
        final subjects = result['subjects'] as List<Map<String, dynamic>>? ?? [];

        await _localStorage.saveSubjects(classroomId, subjects);

        setState(() {
          _subjects = subjects;
          _isLoadingSubjects = false;
        });

        _initializeStudentScores();

        print('✅ Loaded ${_subjects.length} subjects from API');
      } else {
        await _loadSubjectsFromLocal();
        print('⚠️ Using local subjects data');
      }
    } catch (e) {
      print('❌ Error fetching subjects: $e');
      await _loadSubjectsFromLocal();
    } finally {
      if (mounted) {
        setState(() { _isLoadingSubjects = false; });
      }
    }
  }

  Future<void> _loadSubjectsFromLocal() async {
    final subjects = await _localStorage.getSubjects(_selectedClassroomId);
    setState(() {
      _subjects = subjects;
      _initializeStudentScores();
    });
    print('📚 Loaded ${_subjects.length} subjects from local storage');
  }

  Future<void> _refreshSubjects() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: kPrimary),
      ),
    );

    try {
      await _fetchSubjectsFromApi(token, _selectedClassroomId);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Subjects refreshed successfully!'),
          backgroundColor: kSuccess,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error refreshing subjects: $e'),
          backgroundColor: kDanger,
        ),
      );
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
      await _fetchSubjectsFromApi(token, _selectedClassroomId);
      await _fetchAssignments(token);
    }
    await _fetchNews();
    await _fetchUnreadMessages();
    setState(() { _isRefreshing = false; });
  }

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
        const SnackBar(content: Text('Parent ID not found'), backgroundColor: kDanger),
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

  void _showCreateAssignmentDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? dueDate;
    String? selectedClassId = _selectedClassroomId;
    final resp = ResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Create Assignment', style: TextStyle(color: kPrimary)),
            content: SizedBox(
              width: resp.isMobile ? null : 500,
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
                          setState(() => selectedClassId = value);
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
                        setState(() => dueDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: kBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: kPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Due Date *', style: TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  dueDate != null
                                      ? '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
                                      : 'Select a date',
                                  style: TextStyle(
                                    fontWeight: dueDate != null ? FontWeight.bold : FontWeight.normal,
                                    color: dueDate != null ? kTextPrimary : kTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: kPrimary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: kPrimary, size: 20),
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
                      const SnackBar(content: Text('Please fill all fields'), backgroundColor: kWarning),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                ),
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
        child: CircularProgressIndicator(color: kPrimary),
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
          SnackBar(content: Text(result['message']), backgroundColor: kSuccess),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']), backgroundColor: kDanger),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: kDanger),
      );
    }
  }

  void _showViewAssignmentsScreen() {
    final resp = ResponsiveData(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(resp.padding),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assignments',
                    style: TextStyle(
                      fontSize: resp.fontSizeH2,
                      fontWeight: FontWeight.bold,
                      color: kSecondary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: kSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingAssignments
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : _assignments.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 64, color: kBorder),
                    const SizedBox(height: 16),
                    const Text(
                      'No assignments yet',
                      style: TextStyle(color: kTextSecondary),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showCreateAssignmentDialog();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create Assignment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: EdgeInsets.all(resp.padding),
                itemCount: _assignments.length,
                itemBuilder: (context, index) {
                  final assignment = _assignments[index];
                  return _buildAssignmentCard(assignment, resp);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment, ResponsiveData resp) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(resp.radius),
        border: Border.all(color: isOverdue ? kDanger.withOpacity(0.3) : kBorder),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 10,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOverdue ? kDanger.withOpacity(0.1) : kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment,
                  color: isOverdue ? kDanger : kPrimary,
                  size: 20,
                ),
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
                        fontSize: resp.fontSizeBody,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: ${_formatDate(assignment['dueDate'])}',
                      style: TextStyle(
                        fontSize: resp.fontSizeSmall,
                        color: isOverdue ? kDanger : kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverdue ? kDanger.withOpacity(0.1) : kSuccess.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isOverdue ? 'Overdue' : 'Active',
                  style: TextStyle(
                    fontSize: resp.fontSizeCaption,
                    color: isOverdue ? kDanger : kSuccess,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            assignment['description'] ?? 'No description',
            style: TextStyle(
              fontSize: resp.fontSizeSmall,
              color: kTextSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.class_, size: 16, color: kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  assignment['classroom']?['name'] ?? _selectedClassName,
                  style: TextStyle(
                    fontSize: resp.fontSizeSmall,
                    color: kTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAssignmentDetails(assignment, resp),
                icon: Icon(Icons.visibility, size: 18),
                label: Text('Details', style: TextStyle(fontSize: resp.fontSizeSmall)),
                style: TextButton.styleFrom(foregroundColor: kPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAssignmentDetails(Map<String, dynamic> assignment, ResponsiveData resp) {
    final dueDate = DateTime.tryParse(assignment['dueDate'] ?? '');
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          assignment['title'] ?? 'Assignment Details',
          style: const TextStyle(color: kPrimary),
        ),
        content: SizedBox(
          width: resp.isMobile ? null : 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      assignment['description'] ?? 'No description',
                      style: TextStyle(color: kTextSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: isOverdue ? kDanger : kPrimary),
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
                              color: isOverdue ? kDanger : kTextPrimary,
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
                  color: isOverdue ? kDanger.withOpacity(0.1) : kSuccess.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(isOverdue ? Icons.warning : Icons.check_circle, color: isOverdue ? kDanger : kSuccess),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isOverdue ? 'This assignment is overdue' : 'This assignment is active',
                        style: TextStyle(color: isOverdue ? kDanger : kSuccess),
                      ),
                    ),
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
        ],
      ),
    );
  }

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
    if (picked != null) setState(() => _attendanceDate = picked);
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

    setState(() => _isSavingAttendance = true);

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
      SnackBar(
        content: Text('✅ Attendance saved for $successCount students!'),
        backgroundColor: kSuccess,
      ),
    );
  }

  Future<void> _saveSubjectScores(Map<String, dynamic> subject) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    setState(() => _isSavingResults = true);

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No scores to save'), backgroundColor: kWarning),
      );
      setState(() => _isSavingResults = false);
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
      setState(() => _isSavingResults = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scores saved locally! Will sync when online.'),
          backgroundColor: kSuccess,
        ),
      );
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

    setState(() => _isSavingResults = false);

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scores for $subjectName saved!'),
          backgroundColor: kSuccess,
        ),
      );
    } else {
      await _localStorage.queuePendingScores({
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classroomId': _selectedClassroomId,
        'scores': scores,
        'timestamp': DateTime.now().toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['message']}. Saved locally.'),
          backgroundColor: kWarning,
        ),
      );
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return kSuccess;
    if (score >= 50) return kWarning;
    return kDanger;
  }

  void _handleActivityTap(String action) {
    switch (action) {
      case 'Take Attendance':
        setState(() => _selectedIndex = 2);
        break;
      case 'Record Results':
        if (_subjects.isEmpty) {
          _showAddSubjectDialog();
        } else {
          setState(() => _selectedIndex = 3);
        }
        break;
      case 'Add Subject':
        _showAddSubjectDialog();
        break;
      case 'Create Assignment':
        _showCreateAssignmentDialog();
        break;
      case 'Chat with Parents':
        _navigateToChatList();
        break;
      case 'View Students':
        setState(() => _selectedIndex = 1);
        break;
    }
  }

  void _showAddSubjectDialog() {
    _subjectNameController.clear();
    _subjectDescriptionController.clear();
    final resp = ResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add New Subject', style: TextStyle(color: kPrimary)),
        content: SizedBox(
          width: resp.isMobile ? null : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _subjectNameController,
                decoration: const InputDecoration(
                  labelText: 'Subject Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subjectDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final subjectName = _subjectNameController.text.trim();
              if (subjectName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a subject name'),
                    backgroundColor: kWarning,
                  ),
                );
                return;
              }

              setState(() => _isAddingSubject = true);

              final token = Provider.of<AuthProvider>(context, listen: false).token;
              if (token == null) {
                setState(() => _isAddingSubject = false);
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

              setState(() => _isAddingSubject = false);

              if (result['success']) {
                await _fetchSubjectsFromApi(token, _selectedClassroomId);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Subject "$subjectName" added!'),
                    backgroundColor: kSuccess,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Failed to add subject'),
                    backgroundColor: kDanger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
            ),
            child: _isAddingSubject
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add Subject'),
          ),
        ],
      ),
    );
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    final resp = ResponsiveData(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(student['name'], style: const TextStyle(color: kPrimary)),
        content: SizedBox(
          width: resp.isMobile ? null : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Admission', student['admissionNo'], resp),
              _buildDetailRow('Class', student['className'], resp),
              const SizedBox(height: 12),
              const Text(
                'Parent Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('Name', student['parentName'], resp),
              _buildDetailRow('Email', student['parentEmail'], resp),
              InkWell(
                onTap: () => _makePhoneCall(student['parentPhone']),
                child: _buildDetailRow('Phone', student['parentPhone'], resp, isClickable: true),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
            ),
          ),
          if (student['parentPhone'] != null && student['parentPhone'].toString().isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _makePhoneCall(student['parentPhone']),
              icon: const Icon(Icons.phone),
              label: const Text('Call Parent'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kSuccess,
                foregroundColor: Colors.white,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ResponsiveData resp, {bool isClickable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: resp.isMobile ? 70 : 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: resp.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: kTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: resp.fontSizeSmall,
                color: isClickable ? kPrimary : kTextPrimary,
                decoration: isClickable ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (isClickable && value.isNotEmpty && value != 'N/A')
            Icon(Icons.phone, size: 16, color: kPrimary),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == 'N/A') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available'), backgroundColor: kWarning),
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
        SnackBar(content: Text('Could not dial $phoneNumber'), backgroundColor: kDanger),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(color: kDanger)),
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
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showAttendanceHistory() {
    final resp = ResponsiveData(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * (resp.isMobile ? 0.8 : 0.7),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(resp.padding),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attendance History',
                    style: TextStyle(
                      fontSize: resp.fontSizeH2,
                      fontWeight: FontWeight.bold,
                      color: kSecondary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: kSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: _apiService.getAttendanceByActiveTerm(
                  token: Provider.of<AuthProvider>(context, listen: false).token!,
                  schoolId: _currentUser.schoolId,
                  classroomId: _selectedClassroomId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: kPrimary));
                  }
                  if (!snapshot.hasData || snapshot.data == null || !snapshot.data!['success']) {
                    return const Center(child: Text('No attendance records found'));
                  }
                  final records = snapshot.data!['data'] as List? ?? [];
                  if (records.isEmpty) {
                    return const Center(child: Text('No attendance records found'));
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(resp.padding),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: record['status'] == 1
                                ? kSuccess.withOpacity(0.1)
                                : kDanger.withOpacity(0.1),
                            child: Icon(
                              record['status'] == 1 ? Icons.check : Icons.close,
                              color: record['status'] == 1 ? kSuccess : kDanger,
                            ),
                          ),
                          title: Text(
                            record['studentName'] ?? 'Student',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'Date: ${record['date']?.toString().split('T')[0] ?? 'N/A'}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: record['status'] == 1
                                  ? kSuccess.withOpacity(0.1)
                                  : kDanger.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              record['status'] == 1 ? 'Present' : 'Absent',
                              style: TextStyle(
                                color: record['status'] == 1 ? kSuccess : kDanger,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resp = ResponsiveData(context);

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _errorMessage != null
            ? _buildErrorView(resp)
            : RefreshIndicator(
          onRefresh: _refreshData,
          color: kPrimary,
          child: _selectedIndex == 0
              ? _buildHomeScreen(resp)
              : _buildScreenForIndex(_selectedIndex, resp),
        ),
      ),
      bottomNavigationBar: _isLoading || _errorMessage != null ? null : _buildBottomNavigationBar(resp),
    );
  }

  Widget _buildErrorView(ResponsiveData resp) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: kDanger),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: kTextSecondary, fontSize: resp.fontSizeBody),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchDashboardData,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(ResponsiveData resp) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: resp.isMobile ? BottomNavigationBarType.fixed : BottomNavigationBarType.shifting,
        backgroundColor: Colors.transparent,
        selectedItemColor: kPrimary,
        unselectedItemColor: kTextSecondary,
        currentIndex: _selectedIndex,
        elevation: 0,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_rounded),
            label: 'Students',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.checklist_rounded),
            label: 'Attendance',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.grade_rounded),
            label: 'Results',
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
          const BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeScreen(ResponsiveData resp) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        children: [
          _buildHeader(resp),
          const SizedBox(height: 16),
          ClockInOutWidget(
            user: _currentUser,
            apiService: _apiService,
            onStatusChanged: () {
              print('Clock status changed');
            },
          ),
          const SizedBox(height: 20),
          if (_classrooms.length > 1)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
              ),
              child: DropdownButton<String>(
                value: _selectedClassroomId,
                dropdownColor: Colors.white,
                underline: const SizedBox(),
                icon: Icon(Icons.arrow_drop_down, color: kPrimary),
                style: TextStyle(
                  color: kTextPrimary,
                  fontSize: resp.fontSizeBody,
                ),
                isExpanded: true,
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
                      await _fetchSubjectsFromApi(token, value);
                      await _fetchAssignments(token);
                    }
                    setState(() => _isLoading = false);
                  }
                },
              ),
            ),
          _buildStatsGrid(resp),
          const SizedBox(height: 20),
          _buildActivitySlideshow(resp),
          const SizedBox(height: 20),
          _buildQuickActions(resp),
          const SizedBox(height: 20),
          _buildAssignmentsPreview(resp),
          const SizedBox(height: 20),
          _buildNewsSection(resp),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader(ResponsiveData resp) {
    return Container(
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(resp.radius),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: resp.isMobile ? 50 : 60,
            height: resp.isMobile ? 50 : 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimary, kPrimaryDark],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _currentUser.name.isNotEmpty ? _currentUser.name[0].toUpperCase() : 'T',
                style: TextStyle(
                  fontSize: resp.fontSizeH2,
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
                  'Hello, ${_currentUser.name.split(' ').first}!',
                  style: TextStyle(
                    fontSize: resp.fontSizeH3,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                  ),
                ),
                Text(
                  _currentUser.schoolName,
                  style: TextStyle(
                    fontSize: resp.fontSizeSmall,
                    color: kTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _selectedClassName,
                    style: TextStyle(
                      fontSize: resp.fontSizeCaption,
                      color: kPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.message_rounded,
                  color: kPrimary,
                  size: resp.isMobile ? 24 : 28,
                ),
                onPressed: _navigateToMessages,
              ),
              if (_unreadMessageCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
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
      ),
    );
  }

  Widget _buildStatsGrid(ResponsiveData resp) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: resp.gridColumns,
      mainAxisSpacing: resp.spacing,
      crossAxisSpacing: resp.spacing,
      childAspectRatio: 1.2,
      children: [
        _buildStatCard(
          icon: Icons.people,
          value: _students.length.toString(),
          label: 'Students',
          color: kPrimary,
        ),
        _buildStatCard(
          icon: Icons.check_circle,
          value: '${_getTodayAttendanceCount()}/${_students.length}',
          label: 'Present Today',
          color: kSuccess,
        ),
        _buildStatCard(
          icon: Icons.class_,
          value: _selectedClassName,
          label: 'Class',
          color: kWarning,
        ),
        _buildStatCard(
          icon: Icons.book,
          value: _subjects.length.toString(),
          label: 'Subjects',
          color: kInfo,
        ),
        _buildStatCard(
          icon: Icons.assignment,
          value: _assignments.length.toString(),
          label: 'Assignments',
          color: kPurple,
        ),
        _buildStatCard(
          icon: Icons.message,
          value: _unreadMessageCount.toString(),
          label: 'Messages',
          color: kPrimary,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: kTextSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySlideshow(ResponsiveData resp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '✨ Teacher Activities',
            style: TextStyle(
              fontSize: resp.fontSizeH3,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
          ),
        ),
        SizedBox(
          height: resp.slideshowHeight,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentSlideIndex = index),
            itemCount: _activitySlides.length,
            itemBuilder: (context, index) {
              final slide = _activitySlides[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimary, kPrimaryDark],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleActivityTap(slide['action'] as String),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.all(resp.padding),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              slide['icon'] as IconData,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slide['title'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  slide['description'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    slide['action'] as String,
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${index + 1}/${_activitySlides.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _activitySlides.length,
                (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: resp.isMobile ? 5 : 6,
              height: resp.isMobile ? 5 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentSlideIndex == index ? kPrimary : kBorder,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(ResponsiveData resp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: resp.fontSizeH3,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: resp.quickActionsCount,
          mainAxisSpacing: resp.spacing,
          crossAxisSpacing: resp.spacing,
          childAspectRatio: 1,
          children: [
            _buildActionTile(Icons.checklist, 'Attendance', () => setState(() => _selectedIndex = 2), resp),
            _buildActionTile(Icons.grade, 'Results', () => {
              if (_subjects.isEmpty) {
                _showAddSubjectDialog()
              } else {
                setState(() => _selectedIndex = 3)
              }
            }, resp),
            _buildActionTile(Icons.library_add, 'Add Subject', _showAddSubjectDialog, resp),
            _buildActionTile(Icons.assignment_add, 'Assignment', _showCreateAssignmentDialog, resp),
            _buildActionTile(Icons.chat, 'Chat Parents', _navigateToChatList, resp),
            _buildActionTile(Icons.people, 'Students', () => setState(() => _selectedIndex = 1), resp),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap, ResponsiveData resp) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: kPrimary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: kTextPrimary,
                fontSize: resp.fontSizeCaption,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsPreview(ResponsiveData resp) {
    if (_isLoadingAssignments) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    if (_assignments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.assignment_turned_in, size: 48, color: kBorder),
            const SizedBox(height: 12),
            Text(
              'No assignments yet',
              style: TextStyle(color: kTextSecondary),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showCreateAssignmentDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create First Assignment'),
              style: TextButton.styleFrom(foregroundColor: kPrimary),
            ),
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
            Text(
              'Recent Assignments',
              style: TextStyle(
                fontSize: resp.fontSizeH3,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
            ),
            TextButton(
              onPressed: _showViewAssignmentsScreen,
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: kShadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _assignments.length > 3 ? 3 : _assignments.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: kBorder),
            itemBuilder: (context, index) => _buildAssignmentCard(_assignments[index], resp),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection(ResponsiveData resp) {
    if (_isLoadingNews) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    if (_news.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'School News',
          style: TextStyle(
            fontSize: resp.fontSizeH3,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: kShadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _news.length > 3 ? 3 : _news.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: kBorder),
            itemBuilder: (context, index) {
              final item = _news[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: kPrimary.withOpacity(0.1),
                  child: Icon(Icons.newspaper, color: kPrimary),
                ),
                title: Text(
                  item['title'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item['date'] ?? 'Recent',
                  style: TextStyle(fontSize: 10, color: kTextSecondary),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 14, color: kPrimary),
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(item['title']),
                    content: SingleChildScrollView(
                      child: Text(item['content']),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenForIndex(int index, ResponsiveData resp) {
    switch (index) {
      case 1: return _buildStudentsScreen(resp);
      case 2: return _buildAttendanceScreen(resp);
      case 3: return _buildResultsScreen(resp);
      case 4: return _buildMessagesScreen(resp);
      case 5: return _buildMoreScreen(resp);
      default: return _buildHomeScreen(resp);
    }
  }

  Widget _buildStudentsScreen(ResponsiveData resp) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(resp.padding),
          color: Colors.white,
          child: TextField(
            controller: _searchController,
            onChanged: _filterStudents,
            decoration: InputDecoration(
              hintText: 'Search by name or admission...',
              prefixIcon: Icon(Icons.search, color: kPrimary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
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
              fillColor: kBackground,
              contentPadding: EdgeInsets.symmetric(
                horizontal: resp.padding,
                vertical: resp.isMobile ? 12 : 16,
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: kPrimary,
            child: _isSearching && _filteredStudents.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 48, color: kBorder),
                  SizedBox(height: 12),
                  Text('No students found'),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(resp.padding),
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) =>
                  _buildStudentCard(_filteredStudents[index], resp),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, ResponsiveData resp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(resp.radius),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: resp.isMobile ? 40 : 45,
                height: resp.isMobile ? 40 : 45,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimary, kPrimaryDark],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    student['name'][0],
                    style: TextStyle(
                      fontSize: resp.fontSizeMedium,
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
                        fontSize: resp.fontSizeBody,
                        color: kTextPrimary,
                      ),
                    ),
                    Text(
                      'Admission: ${student['admissionNo']}',
                      style: TextStyle(
                        fontSize: resp.fontSizeSmall,
                        color: kTextSecondary,
                      ),
                    ),
                    Text(
                      'Parent: ${student['parentName']}',
                      style: TextStyle(
                        fontSize: resp.fontSizeSmall,
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.message, color: kPrimary, size: 22),
                onPressed: () => _startConversationWithParent(student),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStudentInfo('Attendance', '${student['attendance']}%', Icons.calendar_today, resp),
              _buildStudentInfo('Average', '${student['averageScore']}%', Icons.grade, resp),
              _buildStudentInfo('Gender', student['gender'], Icons.person, resp),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showStudentDetails(student),
                  icon: Icon(Icons.visibility, size: 18),
                  label: Text('Details', style: TextStyle(fontSize: resp.fontSizeSmall)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimary,
                    side: const BorderSide(color: kPrimary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _startConversationWithParent(student),
                  icon: Icon(Icons.message, size: 18),
                  label: Text('Message Parent', style: TextStyle(fontSize: resp.fontSizeSmall)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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

  Widget _buildStudentInfo(String label, String value, IconData icon, ResponsiveData resp) {
    return Column(
      children: [
        Icon(icon, size: 18, color: kPrimary),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: resp.fontSizeBody,
            color: kTextPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: resp.fontSizeCaption,
            color: kTextSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceScreen(ResponsiveData resp) {
    int presentCount = _getAttendanceCountForDate(_attendanceDate);
    bool isAttendanceSaved = _isAttendanceSavedForDate(_attendanceDate);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(resp.padding),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Take Attendance',
                    style: TextStyle(
                      fontSize: resp.fontSizeH2,
                      fontWeight: FontWeight.bold,
                      color: kPrimary,
                    ),
                  ),
                  if (isAttendanceSaved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kSuccess.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Completed',
                        style: TextStyle(
                          color: kSuccess,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(resp.padding),
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today, color: kPrimary),
                        const SizedBox(width: 10),
                        const Text('Select Date'),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          '${_attendanceDate.day}/${_attendanceDate.month}/${_attendanceDate.year}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_drop_down, color: kPrimary),
                          onPressed: isAttendanceSaved ? null : _selectDate,
                        ),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSuccess,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isAttendanceSaved ? null : () => _markAllAttendance(false),
                      icon: const Icon(Icons.cancel),
                      label: const Text('All Absent'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kDanger,
                        side: const BorderSide(color: kDanger),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(resp.padding),
          margin: EdgeInsets.all(resp.padding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: kShadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Present', presentCount.toString(), Icons.check_circle, kSuccess, resp),
              _buildSummaryItem('Absent', (_students.length - presentCount).toString(), Icons.cancel, kDanger, resp),
              _buildSummaryItem('Total', _students.length.toString(), Icons.people, kPrimary, resp),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: resp.padding),
            itemCount: _students.length,
            itemBuilder: (context, index) =>
                _buildAttendanceItem(_students[index], resp, isAttendanceSaved),
          ),
        ),
        Container(
          padding: EdgeInsets.all(resp.padding),
          color: Colors.white,
          child: SafeArea(
            child: ElevatedButton(
              onPressed: (isAttendanceSaved || _isSavingAttendance) ? null : _saveAttendance,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAttendanceSaved ? kBorder : kPrimary,
                foregroundColor: isAttendanceSaved ? kTextSecondary : Colors.white,
                minimumSize: const Size(double.infinity, 45),
              ),
              child: _isSavingAttendance
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : (isAttendanceSaved
                  ? const Text('Attendance Completed')
                  : const Text('Save Attendance')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color, ResponsiveData resp) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: resp.fontSizeH3,
            color: kTextPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: resp.fontSizeCaption,
            color: kTextSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceItem(Map<String, dynamic> student, ResponsiveData resp, bool isAttendanceSaved) {
    String dateKey = '${_attendanceDate.year}-${_attendanceDate.month}-${_attendanceDate.day}';
    bool isPresent = _attendanceRecords[student['id']]?[dateKey] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(resp.radius),
        boxShadow: [
          BoxShadow(
            color: kShadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: resp.fontSizeBody,
                  ),
                ),
                Text(
                  'Admission: ${student['admissionNo']}',
                  style: TextStyle(
                    fontSize: resp.fontSizeSmall,
                    color: kTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_isSavingAttendance)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: isPresent,
              onChanged: isAttendanceSaved
                  ? null
                  : (value) {
                setState(() {
                  _attendanceRecords[student['id']]![dateKey] = value;
                });
              },
              activeColor: kSuccess,
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPresent ? kSuccess.withOpacity(0.1) : kDanger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isPresent ? 'Present' : 'Absent',
              style: TextStyle(
                color: isPresent ? kSuccess : kDanger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(ResponsiveData resp) {
    if (_isLoadingSubjects) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimary),
            SizedBox(height: 16),
            Text('Loading subjects...'),
          ],
        ),
      );
    }

    if (_subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: kWarning),
            const SizedBox(height: 16),
            const Text(
              'No subjects added yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please add subjects to this classroom first',
              style: TextStyle(color: kTextSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _showAddSubjectDialog,
                  icon: const Icon(Icons.library_add),
                  label: const Text('Add Subject'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _refreshSubjects,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimary,
                    side: const BorderSide(color: kPrimary),
                  ),
                ),
              ],
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
            indicatorColor: kPrimary,
            labelColor: kPrimary,
            unselectedLabelColor: kTextSecondary,
            tabs: _subjects.map((subject) => Tab(text: subject['name'])).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshSubjects,
              tooltip: 'Refresh Subjects',
            ),
          ],
        ),
        body: TabBarView(
          children: _subjects.map((subject) => _buildSubjectScoreForm(subject, resp)).toList(),
        ),
      ),
    );
  }

  Widget _buildSubjectScoreForm(Map<String, dynamic> subject, ResponsiveData resp) {
    final subjectId = subject['id'].toString();

    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Container(
        padding: EdgeInsets.all(resp.padding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(resp.radius),
          boxShadow: [
            BoxShadow(
              color: kShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: resp.isMobile ? 50 : 60,
                  height: resp.isMobile ? 50 : 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kPrimary, kPrimaryDark],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.book, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject['name'],
                        style: TextStyle(
                          fontSize: resp.fontSizeH2,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                      Text(
                        'Enter scores for all students',
                        style: TextStyle(
                          color: kTextSecondary,
                          fontSize: resp.fontSizeSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final student = _students[index];
                final studentId = student['id'].toString();
                final scores = _studentScores[studentId]?[subjectId];
                return _buildStudentScoreCard(student, subject, scores, resp);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSavingResults ? null : () => _saveSubjectScores(subject),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, resp.isMobile ? 45 : 50),
                padding: EdgeInsets.symmetric(vertical: resp.isMobile ? 12 : 16),
              ),
              child: _isSavingResults
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Save All Scores'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentScoreCard(Map<String, dynamic> student, Map<String, dynamic> subject, Map<String, dynamic>? scores, ResponsiveData resp) {
    int caScore = scores?['ca'] ?? 0;
    int examScore = scores?['exam'] ?? 0;
    int total = caScore + examScore;
    final subjectId = subject['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(resp.padding),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(resp.radius),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: resp.isMobile ? 35 : 40,
                height: resp.isMobile ? 35 : 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimary, kPrimaryDark],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    student['name'][0],
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
                      student['name'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: resp.fontSizeBody,
                      ),
                    ),
                    Text(
                      'Admission: ${student['admissionNo']}',
                      style: TextStyle(
                        fontSize: resp.fontSizeSmall,
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(total).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total: $total%',
                  style: TextStyle(
                    color: _getScoreColor(total),
                    fontWeight: FontWeight.bold,
                    fontSize: resp.fontSizeSmall,
                  ),
                ),
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
                    const Text(
                      'CA Score',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                      ),
                    ),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: kBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    const Text(
                      'Exam Score',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                      ),
                    ),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: kBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  Widget _buildMessagesScreen(ResponsiveData resp) {
    return const MessagesScreen();
  }

  Widget _buildMoreScreen(ResponsiveData resp) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(resp.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More Options',
            style: TextStyle(
              fontSize: resp.fontSizeH2,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(resp.radius),
              boxShadow: [
                BoxShadow(
                  color: kShadow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildMoreOption(
                  Icons.assignment,
                  'All Assignments',
                  'View all assignments',
                  _showViewAssignmentsScreen,
                  resp,
                ),
                _buildMoreOption(
                  Icons.history,
                  'Attendance History',
                  'View records',
                  _showAttendanceHistory,
                  resp,
                ),
                _buildMoreOption(
                  Icons.message,
                  'Messages',
                  'View all messages',
                  _navigateToMessages,
                  resp,
                ),
                _buildMoreOption(
                  Icons.logout,
                  'Logout',
                  'Sign out',
                  _showLogoutDialog,
                  resp,
                  isDestructive: true,
                ),
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
      VoidCallback onTap,
      ResponsiveData resp, {
        bool isDestructive = false,
      }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive ? kDanger.withOpacity(0.1) : kPrimary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive ? kDanger : kPrimary,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? kDanger : kTextPrimary,
          fontWeight: FontWeight.w500,
          fontSize: resp.fontSizeBody,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: resp.fontSizeSmall,
          color: kTextSecondary,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 18,
        color: isDestructive ? kDanger : kPrimary,
      ),
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(
        horizontal: resp.padding,
        vertical: resp.isMobile ? 8 : 12,
      ),
    );
  }
}

// ==================== CHAT LIST SCREEN ====================

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
        const SnackBar(content: Text('Parent ID not found'), backgroundColor: kDanger),
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

  @override
  Widget build(BuildContext context) {
    final resp = ResponsiveData(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parents Chat'),
        backgroundColor: kPrimary,
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
                  setState(() => _isLoading = false);
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: kDanger),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: kTextSecondary,
                fontSize: resp.fontSizeBody,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchData,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Container(
            padding: EdgeInsets.all(resp.padding),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: _filterStudents,
              decoration: InputDecoration(
                hintText: 'Search by student or parent name...',
                prefixIcon: Icon(Icons.search, color: kPrimary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, size: 18),
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
                fillColor: kBackground,
                contentPadding: EdgeInsets.symmetric(
                  vertical: resp.isMobile ? 10 : 12,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          if (_isSearching)
            Container(
              padding: EdgeInsets.symmetric(horizontal: resp.padding, vertical: 8),
              color: kPrimary.withOpacity(0.05),
              child: Text(
                'Found ${_filteredStudents.length} student${_filteredStudents.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: resp.fontSizeSmall,
                  color: kPrimary,
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
                  Icon(Icons.chat_bubble_outline, size: 64, color: kBorder),
                  const SizedBox(height: 16),
                  Text(
                    _isSearching ? 'No parents found' : 'No students in this class',
                    style: TextStyle(
                      fontSize: resp.fontSizeBody,
                      color: kTextSecondary,
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
                    padding: EdgeInsets.all(resp.padding),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: kBorder, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: resp.isMobile ? 50 : 55,
                          height: resp.isMobile ? 50 : 55,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kPrimary, kPrimaryDark],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              student['parentName'][0].toUpperCase(),
                              style: TextStyle(
                                fontSize: resp.fontSizeH2,
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
                                  fontSize: resp.fontSizeBody,
                                  color: kTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Student: ${student['name']} • Class: ${student['className']}',
                                style: TextStyle(
                                  fontSize: resp.fontSizeSmall,
                                  color: kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            color: kPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.message,
                              color: Colors.white,
                              size: 22,
                            ),
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
}