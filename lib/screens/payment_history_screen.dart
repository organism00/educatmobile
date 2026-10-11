import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

enum _DateFilter { all, thisTerm, lastTerm, thisYear }

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late ApiService _apiService;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _allPayments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  double _totalPaid = 0.0;
  String _guardianName = '';

  // Search & filter
  final TextEditingController _searchController = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.all;
  final Set<String> _expandedIds = {};

  // Distinct terms found in the data (for filter chips)
  List<String> _availableTerms = [];
  String? _selectedTerm; // null = all terms

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _fetchPaymentHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==================== SNACKBAR HELPER ====================

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==================== DATA ====================

  Future<void> _fetchPaymentHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    final guardianId = authProvider.currentUser?.id;

    if (token == null || guardianId == null) {
      setState(() {
        _errorMessage = 'Not authenticated';
        _isLoading = false;
      });
      return;
    }

    final result = await _apiService.getGuardianPaymentHistory(
      token: token,
      guardianId: guardianId,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _allPayments = (result['payments'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
            [];
        // Sort newest first
        _allPayments.sort((a, b) {
          final da = _parseDate(_paymentDate(a));
          final db = _parseDate(_paymentDate(b));
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
        _totalPaid = (result['totalPaid'] as num?)?.toDouble() ?? 0.0;
        _guardianName = result['guardianName'] ?? '';

        // Build distinct term list
        final termSet = <String>{};
        for (final p in _allPayments) {
          final t = _extractTerm(p);
          if (t != null && t.isNotEmpty) termSet.add(t);
        }
        _availableTerms = termSet.toList()
          ..sort((a, b) => b.compareTo(a)); // newest-looking first

        _applyFilters();
      } else {
        _errorMessage =
            result['message'] ?? 'Failed to load payment history';
      }
    });
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  dynamic _paymentDate(Map<String, dynamic> p) =>
      p['paymentDate'] ?? p['date'] ?? p['createdAt'];

  /// Try hard to find a term for a payment.
  String? _extractTerm(Map<String, dynamic> p) {
    final candidates = [
      p['termName'],
      p['term'],
      p['termLabel'],
      p['academicTerm'],
      p['sessionTerm'],
      p['termId'],
    ];
    for (final c in candidates) {
      if (c != null && c.toString().trim().isNotEmpty) {
        return c.toString().trim();
      }
    }
    // Nested fallback: payment['fee']['term'] etc.
    for (final key in ['fee', 'student', 'classroom']) {
      final nested = p[key];
      if (nested is Map) {
        final t = nested['termName'] ??
            nested['term'] ??
            nested['academicTerm'];
        if (t != null && t.toString().trim().isNotEmpty) {
          return t.toString().trim();
        }
      }
    }
    return null;
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();

    _filteredPayments = _allPayments.where((p) {
      // Explicit term filter
      if (_selectedTerm != null) {
        final t = _extractTerm(p);
        if (t != _selectedTerm) return false;
      }

      // Date-based filter (kept for convenience)
      final date = _parseDate(_paymentDate(p));
      if (_dateFilter != _DateFilter.all && date != null) {
        switch (_dateFilter) {
          case _DateFilter.thisYear:
            if (date.year != now.year) return false;
            break;
          case _DateFilter.thisTerm:
          case _DateFilter.lastTerm:
          case _DateFilter.all:
          // Term-based filters rely on _selectedTerm,
          // these placeholders won't restrict date-wise
            break;
        }
      }

      // Search filter
      if (query.isNotEmpty) {
        final fee =
        (p['feeName'] ?? p['feeType'] ?? '').toString().toLowerCase();
        final student =
        (p['studentName'] ?? p['student']?['name'] ?? '')
            .toString()
            .toLowerCase();
        final ref = (p['reference'] ?? p['transactionReference'] ?? '')
            .toString()
            .toLowerCase();
        final term = (_extractTerm(p) ?? '').toLowerCase();
        return fee.contains(query) ||
            student.contains(query) ||
            ref.contains(query) ||
            term.contains(query);
      }
      return true;
    }).toList();
  }

  void _onFilterChanged(_DateFilter f) {
    setState(() {
      _dateFilter = f;
      if (f == _DateFilter.all) {
        _selectedTerm = null;
      }
      _applyFilters();
    });
  }

  void _onTermSelected(String? term) {
    setState(() {
      _selectedTerm = term;
      _applyFilters();
    });
  }

  // ==================== HELPERS ====================

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      final d = DateTime.parse(dateValue.toString());
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return 'N/A';
    }
  }

  String _monthLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  double _sumFiltered() => _filteredPayments.fold<double>(
    0.0,
        (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0.0),
  );

  double _avgFiltered() => _filteredPayments.isEmpty
      ? 0.0
      : _sumFiltered() / _filteredPayments.length;

  /// Group by term. Falls back to month grouping if no term is found.
  List<MapEntry<String, List<Map<String, dynamic>>>> _groupByTerm() {
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final p in _filteredPayments) {
      final term = _extractTerm(p);
      String key;
      if (term != null && term.isNotEmpty) {
        key = term;
      } else {
        final d = _parseDate(_paymentDate(p));
        key = d != null ? _monthLabel(d) : 'Other payments';
      }
      groups.putIfAbsent(key, () => []).add(p);
    }

    // Sort groups: try to keep most recent term first.
    // (We just sort alphabetically descending — usually works for
    // things like "2024/2025 Term 3" vs "2023/2024 Term 1".)
    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  Future<void> _copyReference(String ref) async {
    await Clipboard.setData(ClipboardData(text: ref));
    _showSnack('Reference copied');
  }

  Future<void> _copyReceipt(Map<String, dynamic> p) async {
    final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
    final feeName = p['feeName'] ?? p['feeType'] ?? 'Fee Payment';
    final student = p['studentName'] ?? p['student']?['name'] ?? 'N/A';
    final date = _formatDate(_paymentDate(p));
    final reference = p['reference'] ?? p['transactionReference'] ?? '';
    final status = p['status'] ?? 'Completed';
    final term = _extractTerm(p) ?? '';

    final text = '''
PAYMENT RECEIPT
━━━━━━━━━━━━━━━━━━
Fee:        $feeName
Student:    $student
${term.isNotEmpty ? 'Term:       $term\n' : ''}Amount:     ₦${amount.toStringAsFixed(2)}
Date:       $date
Status:     $status
${reference.isNotEmpty ? 'Reference:  $reference\n' : ''}━━━━━━━━━━━━━━━━━━
''';

    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('Receipt copied to clipboard');
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
      case 'paid':
        return AppColors.success;
      case 'pending':
      case 'processing':
        return AppColors.warning;
      case 'failed':
      case 'cancelled':
      case 'reversed':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
      case 'paid':
        return Icons.check_circle;
      case 'pending':
      case 'processing':
        return Icons.access_time_filled;
      case 'failed':
      case 'cancelled':
      case 'reversed':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  IconData _feeIcon(String feeName) {
    final n = feeName.toLowerCase();
    if (n.contains('tuition') || n.contains('class')) return Icons.school;
    if (n.contains('transport')) return Icons.directions_bus;
    if (n.contains('health') || n.contains('hmo')) {
      return Icons.health_and_safety;
    }
    if (n.contains('uniform')) return Icons.checkroom;
    if (n.contains('book')) return Icons.menu_book;
    if (n.contains('meal') || n.contains('lunch')) {
      return Icons.restaurant;
    }
    return Icons.receipt_long;
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? _buildSkeletonLoader()
          : _errorMessage != null
          ? _buildErrorView()
          : RefreshIndicator(
        onRefresh: _fetchPaymentHistory,
        color: AppColors.primary,
        child: Column(
          children: [
            _buildSummaryCard(),
            _buildTermFilterRow(),
            _buildDateFilterRow(),
            _buildSearchBar(),
            Expanded(
              child: _filteredPayments.isEmpty
                  ? _buildEmptyView()
                  : _buildPaymentsList(),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SUMMARY ====================

  Widget _buildSummaryCard() {
    final shown = _sumFiltered();
    final avg = _avgFiltered();
    final isFiltered = _dateFilter != _DateFilter.all ||
        _searchController.text.isNotEmpty ||
        _selectedTerm != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_guardianName.isNotEmpty)
                      Text(
                        _guardianName,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.white.withOpacity(0.9),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    const SizedBox(height: 2),
                    Text(
                      isFiltered ? 'Filtered Total' : 'Total Amount Paid',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.white),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '₦${(isFiltered ? shown : _totalPaid).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${_filteredPayments.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
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
              _buildMiniStat(
                'Payments',
                '${_filteredPayments.length}',
                Icons.receipt,
              ),
              const SizedBox(width: 8),
              _buildMiniStat(
                'Average',
                '₦${avg.toStringAsFixed(0)}',
                Icons.trending_up,
              ),
              const SizedBox(width: 8),
              _buildMiniStat(
                'All Time',
                '₦${_totalPaid.toStringAsFixed(0)}',
                Icons.history,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.white.withOpacity(0.85),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FILTERS ====================

  Widget _buildTermFilterRow() {
    if (_availableTerms.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _buildTermChip('All Terms', null),
          const SizedBox(width: 8),
          for (final term in _availableTerms) ...[
            _buildTermChip(term, term),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildTermChip(String label, String? termValue) {
    final selected = _selectedTerm == termValue;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => _onTermSelected(termValue),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.white,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.greyLight,
        ),
      ),
    );
  }

  Widget _buildDateFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip('All Time', _DateFilter.all),
          const SizedBox(width: 8),
          _buildFilterChip('This Year', _DateFilter.thisYear),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _DateFilter value) {
    final selected = _dateFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => _onFilterChanged(value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.white,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.greyLight,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(_applyFilters),
        decoration: InputDecoration(
          hintText: 'Search fee, student, term, or reference...',
          hintStyle: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () {
              _searchController.clear();
              setState(_applyFilters);
            },
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
      ),
    );
  }

  // ==================== LIST ====================

  Widget _buildPaymentsList() {
    final groups = _groupByTerm();
    final items = <Widget>[];

    for (final entry in groups) {
      items.add(_buildTermHeader(entry.key, entry.value));
      for (final p in entry.value) {
        items.add(_buildPaymentCard(p));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: items,
    );
  }

  Widget _buildTermHeader(String label, List<Map<String, dynamic>> items) {
    final total = items.fold<double>(
      0.0,
          (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Text(
            '₦${total.toStringAsFixed(2)} • ${items.length}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PAYMENT CARD ====================

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final studentName =
        payment['studentName'] ?? payment['student']?['name'] ?? 'N/A';
    final feeName =
        payment['feeName'] ?? payment['feeType'] ?? 'Fee Payment';
    final date = _paymentDate(payment);
    final reference =
        payment['reference'] ?? payment['transactionReference'] ?? '';
    final status = (payment['status'] ?? 'Completed').toString();
    final term = _extractTerm(payment) ?? '';
    final statusColor = _statusColor(status);
    final statusIcon = _statusIcon(status);

    final id = reference.isNotEmpty
        ? reference
        : '${feeName}_${date}_$amount';
    final isExpanded = _expandedIds.contains(id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isExpanded ? 0.08 : 0.05),
            blurRadius: isExpanded ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isExpanded
              ? AppColors.primary.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedIds.remove(id);
            } else {
              _expandedIds.add(id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _feeIcon(feeName),
                      color: statusColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 11, color: AppColors.textSecondary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                studentName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₦${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 12, color: AppColors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(date),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (term.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.menu_book,
                        size: 12, color: AppColors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        term,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 10, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: _buildExpandedDetails(
                  reference: reference,
                  amount: amount,
                  date: date,
                  status: status,
                  studentName: studentName,
                  feeName: feeName,
                  term: term,
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails({
    required String reference,
    required double amount,
    required dynamic date,
    required String status,
    required String studentName,
    required String feeName,
    required String term,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.greyLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Fee', feeName),
            _detailRow('Student', studentName),
            if (term.isNotEmpty) _detailRow('Term', term),
            _detailRow('Amount', '₦${amount.toStringAsFixed(2)}'),
            _detailRow('Date', _formatDate(date)),
            _detailRow('Status', status),
            if (reference.isNotEmpty) _detailRow('Reference', reference),
            const SizedBox(height: 10),
            Row(
              children: [
                if (reference.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyReference(reference),
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copy Ref',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                if (reference.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyReceipt({
                      'feeName': feeName,
                      'studentName': studentName,
                      'amount': amount,
                      'paymentDate': date,
                      'status': status,
                      'reference': reference,
                      'termName': term,
                    }),
                    icon: const Icon(Icons.receipt, size: 14),
                    label: const Text('Receipt',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATES ====================

  Widget _buildSkeletonLoader() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _skeletonBox(height: 140, radius: 16),
        const SizedBox(height: 12),
        _skeletonBox(height: 40, radius: 20, width: 120),
        const SizedBox(height: 8),
        _skeletonBox(height: 48, radius: 12),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++) ...[
          _skeletonBox(height: 90, radius: 12),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _skeletonBox({
    required double height,
    required double radius,
    double? width,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchPaymentHistory,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    final isFiltered = _dateFilter != _DateFilter.all ||
        _searchController.text.isNotEmpty ||
        _selectedTerm != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered ? Icons.search_off : Icons.receipt_long,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No payments match your filter'
                  : 'No payment history yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try adjusting your search or filters.'
                  : 'Your completed payments will appear here.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (isFiltered) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _dateFilter = _DateFilter.all;
                    _selectedTerm = null;
                    _applyFilters();
                  });
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear filters'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}