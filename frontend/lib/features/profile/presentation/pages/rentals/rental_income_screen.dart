import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/usecases/get_rental_income_usecase.dart';
import '../../widgets/rentals/rental_income_widgets.dart';

class RentalIncomeScreen extends StatefulWidget {
  final GetRentalIncomeUseCase? getRentalIncomeUseCase;

  const RentalIncomeScreen({super.key, this.getRentalIncomeUseCase});

  @override
  State<RentalIncomeScreen> createState() => _RentalIncomeScreenState();
}

class _RentalIncomeScreenState extends State<RentalIncomeScreen> {
  late final GetRentalIncomeUseCase _getRentalIncomeUseCase;
  bool _isLoading = true;
  double _totalIncome = 0.0;
  double _pendingIncome = 0.0;
  List<RentalIncomeTransaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _getRentalIncomeUseCase =
        widget.getRentalIncomeUseCase ??
        GetRentalIncomeUseCase(RentalManagementRepositoryImpl());
    _loadRentalIncome();
  }

  Future<void> _loadRentalIncome() async {
    setState(() => _isLoading = true);
    final currentUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id ?? ''
        : '';
    try {
      final summary = await _getRentalIncomeUseCase.execute(currentUserId);
      if (mounted) {
        setState(() {
          _totalIncome = summary.totalIncome;
          _pendingIncome = summary.pendingIncome;
          _transactions = summary.transactions
              .map(RentalIncomeTransaction.fromEntity)
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'รายได้การปล่อยเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadRentalIncome,
              child: CustomScrollView(
                slivers: [
                  // ── Dashboard Overview ──
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.primaryColor,
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 30,
                        top: 10,
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'รายได้รวมทั้งหมด',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '฿ ${_totalIncome.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: RentalIncomeStatCard(
                                  title: 'รายได้ที่รอรับ',
                                  value:
                                      '฿ ${_pendingIncome.toStringAsFixed(0)}',
                                  icon: Icons.pending_actions_rounded,
                                  color: const Color(0xFFFFB74D),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: RentalIncomeStatCard(
                                  title: 'ปล่อยเช่าสำเร็จ',
                                  value: '${_transactions.length} รายการ',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: const Color(0xFF81C784),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── History List ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ประวัติการปล่อยเช่า',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primaryColor,
                              textStyle: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('ทั้งหมด'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_transactions.isEmpty)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'ยังไม่มีรายการปล่อยเช่า',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              color: AppColors.hintTextColor,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final tx = _transactions[index];
                          return RentalIncomeTransactionItem(tx: tx);
                        }, childCount: _transactions.length),
                      ),
                    ),

                  const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
                ],
              ),
            ),
    );
  }
}
