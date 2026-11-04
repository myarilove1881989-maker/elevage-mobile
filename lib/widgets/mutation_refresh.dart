import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

final businessRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// Refresh read views after a successful write, including a return from a form.
/// Form states never subscribe; their unsaved input remains untouched.
mixin MutationRefresh<T extends StatefulWidget> on State<T> implements RouteAware {
  ModalRoute<dynamic>? _dataRoute;
  Timer? _dataTimer;
  bool _dataDirty = false;
  bool _dataRefreshing = false;
  Future<void> refreshAfterMutation();

  void markDataFresh() {
    _dataDirty = false;
    _dataTimer?.cancel();
  }

  @override
  void initState() {
    super.initState();
    ApiService.businessChanges.addListener(_dataChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _dataRoute) {
      businessRouteObserver.unsubscribe(this);
      _dataRoute = route;
      if (route != null) businessRouteObserver.subscribe(this, route);
    }
  }

  void _dataChanged() {
    _dataDirty = true;
    _scheduleDataRefresh();
  }

  void _scheduleDataRefresh() {
    if (!mounted || !_dataDirty || _dataRoute?.isCurrent != true) return;
    _dataTimer?.cancel();
    _dataTimer = Timer(const Duration(milliseconds: 120), () async {
      if (!mounted || !_dataDirty || _dataRefreshing || _dataRoute?.isCurrent != true) return;
      _dataRefreshing = true;
      _dataDirty = false;
      try { await refreshAfterMutation(); }
      finally { _dataRefreshing = false; _scheduleDataRefresh(); }
    });
  }

  @override
  void didPopNext() => _scheduleDataRefresh();
  @override
  void didPush() => _scheduleDataRefresh();
  @override
  void didPushNext() {}
  @override
  void didPop() {}
  @override
  void dispose() {
    ApiService.businessChanges.removeListener(_dataChanged);
    businessRouteObserver.unsubscribe(this);
    _dataTimer?.cancel();
    super.dispose();
  }
}
