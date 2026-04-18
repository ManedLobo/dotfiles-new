import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health/health.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'audit_trail_screen.dart';
import 'auth_service.dart';
import 'constants.dart';
import 'health_service.dart';
import 'login_page.dart';
import 'models.dart';
import 'widgets/data_card.dart';
import 'widgets/health_chart.dart';
import 'widgets/today_value_display.dart';

import 'firebase_options.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health App',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.pinkAccent,
          surface: Color(0xFF1E1E2C),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E1E2C),
          centerTitle: true,
          titleTextStyle: HealthTextStyles.appBarTitle,
          elevation: 0,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const HealthDashboardPage();
          }
          return const LoginPage();
        },
      ),
    );
  }
}

class HealthDashboardPage extends StatefulWidget {
  const HealthDashboardPage({super.key});

  @override
  State<HealthDashboardPage> createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage>
    with WidgetsBindingObserver {
  final HealthService _healthService = HealthService();
  final AuthService _authService = AuthService();
  bool _loading = false;
  bool _healthAccessGranted = false;
  HealthData _data = const HealthData(
    days: [],
    stepTotals: [],
    heartAvg: [],
    hourlyStepTotals: [],
    hourlyHeartAvg: [],
  );

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapHealthAccess());
  }

  Future<void> _bootstrapHealthAccess() async {
    final connectReady = await _healthService.ensureHealthConnectAvailable();
    if (!mounted || !connectReady) {
      return;
    }

    final granted = await _healthService.hasReadPermissions();
    if (!mounted) return;

    setState(() {
      _healthAccessGranted = granted;
    });

    if (granted) {
      _startAutoRefresh();
      await _refreshData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAccessGranted) {
      _refreshData();
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: HealthChartConfig.dataRefreshIntervalSeconds),
      (_) {
        if (mounted && !_loading) {
          _refreshData();
        }
      },
    );
  }

  Future<void> _connectHealthSensor() async {
    final connectReady = await _healthService.ensureHealthConnectAvailable();
    if (!mounted) return;

    if (!connectReady) {
      final status = await _healthService.getHealthConnectStatus();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == HealthConnectSdkStatus.sdkUnavailable
                ? 'Health Connect is not available on this device.'
                : 'Health Connect needs install/update. Play Store was opened.',
          ),
        ),
      );
      return;
    }

    final granted = await _healthService.requestReadPermissions();
    if (!mounted) return;

    setState(() {
      _healthAccessGranted = granted;
    });

    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Health Connect access granted. Syncing...'),
        ),
      );
      _startAutoRefresh();
      await _refreshData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Health access not granted. Open Health Connect app and allow Steps + Heart Rate.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    if (_loading || !_healthAccessGranted) return;

    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: HealthChartConfig.dataHistoryDays));
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final stepData = await _healthService.fetchStepsData(start, end);
      final heartRateData = await _healthService.fetchHeartRateData(start, end);
      final hourlySteps = await _healthService.fetchTodayStepsByHour();
      final hourlyHeart = await _healthService.fetchTodayHeartRateByHour();

      final allDays = <DateTime>{...stepData.keys, ...heartRateData.keys};
      final sortedDays = allDays.toList()..sort();

      if (!mounted) return;

      setState(() {
        _data = HealthData(
          days: sortedDays,
          stepTotals: sortedDays.map((d) => stepData[d] ?? 0.0).toList(),
          heartAvg: sortedDays.map((d) => heartRateData[d] ?? 0.0).toList(),
          hourlyStepTotals: hourlySteps,
          hourlyHeartAvg: hourlyHeart,
        );
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _getTodayValue(List<double> values, List<DateTime> days) {
    if (days.isEmpty || values.isEmpty) return 0;

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final index = days.indexWhere(
      (d) =>
          d.year == todayKey.year &&
          d.month == todayKey.month &&
          d.day == todayKey.day,
    );

    if (index == -1) return 0;
    return values[index].toInt();
  }

  @override
  Widget build(BuildContext context) {
    final todaySteps = _getTodayValue(_data.stepTotals, _data.days);
    final todayBpm = _getTodayValue(_data.heartAvg, _data.days);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Health'),
        actions: [
          IconButton(
            onPressed: _connectHealthSensor,
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Sync Health Data',
          ),
          IconButton(
            onPressed: () async {
              await _authService.signOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: HealthDimensions.paddingMedium,
            vertical: HealthDimensions.paddingLarge,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataCard(
                title: 'Steps',
                value: todaySteps.toString(),
                unit: 'steps today',
                color: Theme.of(context).colorScheme.primary,
                icon: Icons.directions_walk,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HealthDetailScreen(
                        title: 'Steps History',
                        dataLabel: 'Steps',
                        color: Theme.of(context).colorScheme.primary,
                        data: _data,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: HealthDimensions.paddingLarge),
              DataCard(
                title: 'Heart Rate',
                value: todayBpm.toString(),
                unit: 'bpm avg today',
                color: Theme.of(context).colorScheme.secondary,
                icon: Icons.favorite,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HealthDetailScreen(
                        title: 'Heart Rate History',
                        dataLabel: 'BPM',
                        color: Theme.of(context).colorScheme.secondary,
                        data: _data,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: HealthDimensions.paddingLarge),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AuditTrailScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('View Audit Logs'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: HealthDimensions.paddingMedium),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HealthDetailScreen extends StatelessWidget {
  final String title;
  final String dataLabel;
  final Color color;
  final HealthData data;

  const HealthDetailScreen({
    super.key,
    required this.title,
    required this.dataLabel,
    required this.color,
    required this.data,
  });

  int get _todayValue {
    if (data.days.isEmpty) return 0;

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final index = data.days.indexWhere(
      (d) =>
          d.year == todayKey.year &&
          d.month == todayKey.month &&
          d.day == todayKey.day,
    );

    if (index == -1) return 0;
    return dataLabel == 'Steps'
        ? data.stepTotals[index].toInt()
        : data.heartAvg[index].toInt();
  }

  double _calculateAverage(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'This Week'),
            ],
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            _buildTodayTab(context),
            _buildWeekTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTab(BuildContext context) {
    final isSteps = dataLabel == 'Steps';
    final values = isSteps ? data.hourlyStepTotals : data.hourlyHeartAvg;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        HealthDimensions.paddingMedium,
        HealthDimensions.paddingMedium,
        HealthDimensions.paddingMedium,
        HealthDimensions.paddingMedium + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: [
          TodayValueDisplay(
            dataLabel: dataLabel,
            value: _todayValue,
            color: color,
          ),
          const SizedBox(height: HealthDimensions.paddingLarge),
          Expanded(
            child: HealthChart(
              values: values,
              days: data.days,
              color: color,
              dataLabel: dataLabel,
              isHourly: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekTab(BuildContext context) {
    final isSteps = dataLabel == 'Steps';
    final values = isSteps ? data.stepTotals : data.heartAvg;

    if (data.days.isEmpty || values.isEmpty) {
      return const Center(child: Text('No data available this week.'));
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        HealthDimensions.paddingMedium,
        HealthDimensions.paddingLarge,
        HealthDimensions.paddingMedium,
        HealthDimensions.paddingMedium + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: HealthDimensions.paddingSmall,
              ),
              child: HealthChart(
                values: values,
                days: data.days,
                color: color,
                dataLabel: dataLabel,
                isHourly: false,
              ),
            ),
          ),
          const SizedBox(height: HealthDimensions.paddingLarge),
          Text(
            '7-Day Average $dataLabel: ${_calculateAverage(values).toInt()}',
            style: HealthTextStyles.averageLabel,
          ),
        ],
      ),
    );
  }
}
