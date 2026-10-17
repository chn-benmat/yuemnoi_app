import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/location_service.dart';

class RentalRouteState {
  const RentalRouteState({this.route, this.loading = true});
  final DrivingRouteResult? route;
  final bool loading;
}

class RentalRouteCubit extends Cubit<RentalRouteState> {
  RentalRouteCubit({
    required this.destination,
    required this.fetchRoute,
    required this.cachedRoute,
    required this.isVisible,
  }) : super(const RentalRouteState()) {
    _timer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (_active && isVisible() && _hasMoved) unawaited(_loadRoute());
    });
  }

  final LatLng destination;
  final Future<DrivingRouteResult?> Function(LatLng, LatLng) fetchRoute;
  final DrivingRouteResult? Function(LatLng, LatLng) cachedRoute;
  final bool Function() isVisible;
  late final Timer _timer;
  LatLng? _position;
  LatLng? _routedPosition;
  bool _active = true;
  bool _fetching = false;
  bool _started = false;

  bool get _hasMoved =>
      _position != null &&
      (_routedPosition == null ||
          const Distance().as(LengthUnit.Meter, _routedPosition!, _position!) >=
              3);

  void setActive(bool active) => _active = active;

  void updatePosition(LatLng position) {
    if (isClosed) return;
    _position = position;
    if (!_started && _active && isVisible()) {
      _started = true;
      final cached = cachedRoute(position, destination);
      if (cached != null) emit(RentalRouteState(route: cached, loading: false));
      unawaited(_loadRoute());
    }
  }

  Future<void> _loadRoute() async {
    final start = _position;
    if (start == null || _fetching || isClosed || !_active || !isVisible())
      return;
    _fetching = true;
    try {
      final route = await fetchRoute(start, destination);
      if (!isClosed) {
        if (route != null) _routedPosition = start;
        emit(RentalRouteState(route: route ?? state.route, loading: false));
      }
    } catch (_) {
      if (!isClosed) emit(RentalRouteState(route: state.route, loading: false));
    } finally {
      _fetching = false;
    }
  }

  @override
  Future<void> close() {
    _timer.cancel();
    return super.close();
  }
}
