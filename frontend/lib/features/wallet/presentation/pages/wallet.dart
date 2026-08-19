import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/wallet_transaction.dart';
import '../bloc/wallet_cubit.dart';
import '../bloc/wallet_state.dart';
import '../widgets/wallet_credit_card.dart';
import '../widgets/wallet_custom_amount_bottom_sheet.dart';
import '../widgets/wallet_filter_bottom_sheet.dart';
import '../widgets/wallet_summary_bottom_sheet.dart';

class WalletScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const WalletScreen({super.key, this.onBack});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  final List<double> _presetAmounts = [1000, 2500, 5000, 10000, 50000];
  WalletFilterOptions _filterOptions = const WalletFilterOptions();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<WalletTransaction> _filterTransactions(List<WalletTransaction> list) {
    var result = List<WalletTransaction>.from(list);
    final now = DateTime.now();

    // 1. Filter by Period
    switch (_filterOptions.period) {
      case WalletFilterPeriod.today:
        result = result
            .where(
              (tx) =>
                  tx.dateTime.year == now.year &&
                  tx.dateTime.month == now.month &&
                  tx.dateTime.day == now.day,
            )
            .toList();
        break;
      case WalletFilterPeriod.last7Days:
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        result = result
            .where((tx) => tx.dateTime.isAfter(sevenDaysAgo))
            .toList();
        break;
      case WalletFilterPeriod.thisMonth:
        result = result
            .where(
              (tx) =>
                  tx.dateTime.year == now.year &&
                  tx.dateTime.month == now.month,
            )
            .toList();
        break;
      case WalletFilterPeriod.thisYear:
        result = result.where((tx) => tx.dateTime.year == now.year).toList();
        break;
      case WalletFilterPeriod.all:
        break;
    }

    // 2. Filter by Amount Range
    switch (_filterOptions.amountRange) {
      case WalletFilterAmountRange.under1000:
        result = result.where((tx) => tx.amount < 1000).toList();
        break;
      case WalletFilterAmountRange.from1000To5000:
        result = result
            .where((tx) => tx.amount >= 1000 && tx.amount <= 5000)
            .toList();
        break;
      case WalletFilterAmountRange.over5000:
        result = result.where((tx) => tx.amount > 5000).toList();
        break;
      case WalletFilterAmountRange.all:
        break;
    }

    // 3. Sort
    switch (_filterOptions.sort) {
      case WalletFilterSort.newest:
        result.sort((a, b) => b.dateTime.compareTo(a.dateTime));
        break;
      case WalletFilterSort.oldest:
        result.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        break;
      case WalletFilterSort.highestAmount:
        result.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case WalletFilterSort.lowestAmount:
        result.sort((a, b) => a.amount.compareTo(b.amount));
        break;
    }

    return result;
  }

  void _onAmountSelected(double amount) {
    WalletSummaryBottomSheet.show(
      context,
      amount: amount,
      onConfirm: () {
        AppRoutes.openWalletPayment(context, amount: amount);
      },
    );
  }

  void _showCustomAmountDialog() {
    WalletCustomAmountBottomSheet.show(
      context,
      onAmountConfirmed: (amount) {
        _onAmountSelected(amount);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletCubit, WalletState>(
      builder: (context, state) {
        final formattedBalance =
            '${_currencyFormat.format(state.balance)}฿';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: AppColors.primaryColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  AppRoutes.goToHome(context);
                }
              },
            ),
            title: const Text(
              'เงินในบัญชี',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Bank Credit/Debit Style Card: กระเป๋าเงินของคุณ ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: WalletCreditCard(
                  balance: state.balance,
                  formattedBalance: formattedBalance,
                ),
              ),

              // ── Custom Tab Bar ──
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.primaryColor,
                  indicatorWeight: 2.5,
                  labelColor: AppColors.primaryColor,
                  unselectedLabelColor: const Color(0xFF6B7280),
                  labelStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: const [
                    Tab(text: 'เติมเงิน'),
                    Tab(text: 'ประวัติการเติมเงิน'),
                  ],
                ),
              ),

              // ── Tab Views ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: เติมเงิน (Amount Grid)
                    _buildTopUpTabView(),

                    // Tab 2: ประวัติการเติมเงิน (Transaction History)
                    _buildHistoryTabView(state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1 Content: เติมเงิน Grid ──
  Widget _buildTopUpTabView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildAmountButton(_presetAmounts[0])),
              const SizedBox(width: 14),
              Expanded(child: _buildAmountButton(_presetAmounts[1])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildAmountButton(_presetAmounts[2])),
              const SizedBox(width: 14),
              Expanded(child: _buildAmountButton(_presetAmounts[3])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildAmountButton(_presetAmounts[4])),
              const SizedBox(width: 14),
              Expanded(child: _buildCustomAmountButton()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountButton(double amount) {
    final label = NumberFormat('#,###', 'en_US').format(amount);

    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: () => _onAmountSelected(amount),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          side: const BorderSide(color: Color(0xFFD1D5DB), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAmountButton() {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: _showCustomAmountDialog,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          side: const BorderSide(color: Color(0xFFD1D5DB), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: const Text(
          'ระบุจำนวนเงิน',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ),
    );
  }

  // ── Tab 2 Content: ประวัติการเติมเงิน ──
  Widget _buildHistoryTabView(WalletState state) {
    final filteredTransactions = _filterTransactions(state.transactions);
    final hasActiveFilter = !_filterOptions.isDefault;

    return Column(
      children: [
        // Subheader: ประวัติการเติมเงิน & Filter Button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'ประวัติการเติมเงิน',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filteredTransactions.length}',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  WalletFilterBottomSheet.show(
                    context,
                    currentOptions: _filterOptions,
                    onApply: (opts) {
                      setState(() {
                        _filterOptions = opts;
                      });
                    },
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: hasActiveFilter
                        ? AppColors.primaryColor
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 15,
                        color: hasActiveFilter
                            ? Colors.white
                            : const Color(0xFF4B5563),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'กรอง',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasActiveFilter
                              ? Colors.white
                              : const Color(0xFF4B5563),
                        ),
                      ),
                      if (hasActiveFilter) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Active Filter Banner (if any)
        if (hasActiveFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt,
                  size: 14,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 4),
                const Text(
                  'กำลังใช้ตัวกรอง',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _filterOptions = const WalletFilterOptions();
                    });
                  },
                  child: const Text(
                    'ล้างตัวกรอง',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const Divider(height: 1, color: Color(0xFFF3F4F6)),

        // Transactions List
        Expanded(
          child: filteredTransactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          size: 32,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasActiveFilter
                            ? 'ไม่พบรายการที่ตรงกับตัวกรอง'
                            : 'ยังไม่มีประวัติการเติมเงิน',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasActiveFilter
                            ? 'ลองเปลี่ยนเงื่อนไขหรือล้างตัวกรอง'
                            : 'รายการเติมเงินของคุณจะแสดงที่นี่',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      if (hasActiveFilter) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _filterOptions = const WalletFilterOptions();
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'ล้างตัวกรอง',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: filteredTransactions.length,
                  itemBuilder: (context, index) {
                    final tx = filteredTransactions[index];
                    final amountFormatted =
                        '+ ${_currencyFormat.format(tx.amount)}';

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF1F3F5),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Modern emerald icon badge
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.arrow_downward_rounded,
                              color: Color(0xFF059669),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Title & Date
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx.title,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      tx.formattedDateThai,
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Amount
                          Text(
                            amountFormatted,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
