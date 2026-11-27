import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';

class RentalHandoverPaymentWatcher {
  RentalHandoverPaymentWatcher({
    required int bookingId,
    required String channelName,
    required void Function() onChanged,
  }) : _timer = Timer.periodic(
         const Duration(milliseconds: 1500),
         (_) => onChanged(),
       ) {
    if (!SupabaseConfig.isInitialized) return;
    _channel = SupabaseConfig.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_tb',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: bookingId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  final Timer _timer;
  RealtimeChannel? _channel;

  void dispose() {
    _timer.cancel();
    _channel?.unsubscribe();
  }
}
