import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/entities/rental_income.dart';
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
  RentalIncomeSummary? _summary;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _getRentalIncomeUseCase =
        widget.getRentalIncomeUseCase ??
        GetRentalIncomeUseCase(RentalManagementRepositoryImpl());
    _loadRentalIncome();
  }

  Future<void> _loadRentalIncome() async {
    if (_loadFailed) {
      setState(() => _loadFailed = false);
    }
    try {
      final summary = await _getRentalIncomeUseCase.execute();
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _loadFailed = true;
      });
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'โหลดข้อมูลรายได้ไม่สำเร็จ กรุณาลองใหม่',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadRentalIncome,
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    // ระหว่างโหลดครั้งแรก summary เป็น null: ส่วนหัวแสดงขีดแทนตัวเลข
    // เพื่อไม่ให้เข้าใจผิดว่ารายได้เป็น 0 และใช้ skeleton เฉพาะส่วนประวัติ
    final summary = _summary;
    final isLoading = summary == null;
    final transactions = summary?.transactions ?? const <RentalIncomeEntry>[];
    return RefreshIndicator(
      color: AppColors.primaryColor,
      onRefresh: _loadRentalIncome,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.primaryColor,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
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
                    isLoading
                        ? '฿ –'
                        : '฿ ${(summary.totalSatang / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  RentalIncomeStatCard(
                    title: 'ยืนยันรับเงินแล้ว',
                    value: isLoading
                        ? '– รายการ'
                        : '${transactions.length} รายการ',
                    icon: Icons.check_circle_outline_rounded,
                    color: const Color(0xFF81C784),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Text(
                'ประวัติการรับเงิน',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
          if (isLoading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: 4,
                itemBuilder: (_, _) => const RentalIncomeTransactionSkeleton(),
              ),
            )
          else if (transactions.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'ยังไม่มีรายการยืนยันรับเงิน',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: AppColors.hintTextColor,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: transactions.length,
                itemBuilder: (_, index) =>
                    RentalIncomeTransactionItem(tx: transactions[index]),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}
