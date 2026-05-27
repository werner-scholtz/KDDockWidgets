// ignore_for_file: public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'dart:io';

import 'package:flutter/material.dart';

import 'src/dock_controller.dart';
import 'src/dock_runtime.dart';
import 'src/dock_window_page.dart';
import 'src/experimental_window_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    runApp(const MainApp());
    return;
  }

  runWidget(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final DockController _controller = DockController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final bool _useBootstrapMainWindow = Platform.isWindows;
  late final ExperimentalWindowController? _rootWindowController = !_useBootstrapMainWindow
      ? ExperimentalWindowController(preferredSize: const Size(980, 680), title: 'KDDockWidgets Flutter POC')
      : null;
  late final DockRuntimeCoordinator _runtimeCoordinator = DockRuntimeCoordinator(
    controller: _controller,
    rootWindowController: _rootWindowController,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncDetachedNativeWindows);
    _runtimeCoordinator.syncRequestHandler = _syncDetachedNativeWindows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _runtimeCoordinator.registerRootWindow();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_syncDetachedNativeWindows);
    _runtimeCoordinator.dispose();
    _rootWindowController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  ThemeData _buildTheme() =>
      ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F78)), useMaterial3: true);

  @override
  Widget build(BuildContext context) {
    final Widget rootApp = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: _controller.windowTitle(DockController.mainWindowId),
        theme: _buildTheme(),
        home: DockWindowPage(
          controller: _controller,
          windowId: DockController.mainWindowId,
          nativeDockDragCoordinator: _runtimeCoordinator.nativeDockDragCoordinator,
          detachedWindowCountBuilder: () => _controller.detachedWindows.length,
        ),
      ),
    );

    if (_rootWindowController == null) {
      return rootApp;
    }

    return ExperimentalWindowHost(controller: _rootWindowController, child: rootApp);
  }

  void _syncDetachedNativeWindows() => _runtimeCoordinator.syncDetachedNativeWindows(
    navigatorKey: _navigatorKey,
    buildDetachedWindowRoot: (int windowId) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: _controller.windowTitle(windowId),
      theme: _buildTheme(),
      home: DockWindowPage(
        controller: _controller,
        windowId: windowId,
        nativeDockDragCoordinator: _runtimeCoordinator.nativeDockDragCoordinator,
        onDockBackRequested: () {
          _controller.closeDetachedWindow(windowId);
          _syncDetachedNativeWindows();
        },
      ),
    ),
  );
}
