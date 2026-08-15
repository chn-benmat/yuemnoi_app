import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../data/datasources/call_remote_data_source.dart';

class GlobalCallListener extends StatefulWidget {
  const GlobalCallListener({
    super.key,
    required this.child,
    this.dataSource,
  });

  final Widget child;
  final CallRemoteDataSource? dataSource;

  @override
  State<GlobalCallListener> createState() => _GlobalCallListenerState();
}

class _GlobalCallListenerState extends State<GlobalCallListener> {
  late final CallRemoteDataSource _dataSource;
  StreamSubscription<CallSessionData>? _incomingCallSub;
  String _activeRingingSessionId = '';

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? CallRemoteDataSource();
    _startListening();
  }

  void _startListening() {
    try {
      _incomingCallSub = _dataSource.streamIncomingCalls().listen((callData) {
        if (!mounted) return;

        if (callData.status == 'ringing' &&
            callData.id.isNotEmpty &&
            callData.callerConversation != null &&
            _activeRingingSessionId != callData.id) {
          _activeRingingSessionId = callData.id;
          AppRoutes.openIncomingCall(
            context,
            conversation: callData.callerConversation!,
            sessionId: callData.id,
          );
        } else if (callData.status != 'ringing') {
          _activeRingingSessionId = '';
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
