import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_service.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
