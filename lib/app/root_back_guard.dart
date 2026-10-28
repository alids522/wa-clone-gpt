import 'dart:async';
import 'package:flutter/material.dart';
import 'package:device_runtime/device_runtime.dart';

/// Keep the process available to FCM and ongoing calls when leaving the UI.
class RootBackGuard extends StatefulWidget {
  const RootBackGuard({
    super.key,
    required this.child,
    required this.returnToChats,
  });
  final Widget child;
  final bool Function() returnToChats;
  @override
  State<RootBackGuard> createState() => _RootBackGuardState();
}

class _RootBackGuardState extends State<RootBackGuard> {
  Timer? _window;
  bool _armed = false;
  Future<void> back() async {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (widget.returnToChats()) {
      _window?.cancel();
      _armed = false;
      return;
    }
    if (_armed) {
      _window?.cancel();
      _armed = false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await DeviceRuntime.backgroundApp();
      return;
    }
    _armed = true;
    _window = Timer(const Duration(seconds: 2), () => _armed = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tekan sekali lagi untuk keluar'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _window?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: widget.child,
  );
}
