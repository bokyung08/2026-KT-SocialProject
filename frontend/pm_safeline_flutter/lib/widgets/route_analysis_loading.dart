import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RouteAnalysisLoading extends StatefulWidget {
  const RouteAnalysisLoading({
    super.key,
    required this.responseReady,
    required this.onCancel,
  });

  final bool responseReady;
  final VoidCallback onCancel;

  @override
  State<RouteAnalysisLoading> createState() => _RouteAnalysisLoadingState();
}

class _RouteAnalysisLoadingState extends State<RouteAnalysisLoading>
    with TickerProviderStateMixin {
  static const _steps = [
    '도로 네트워크 불러오기',
    '자전거도로 연결 상태 분석',
    '위험 구간 비용 계산',
    '후보 경로 생성',
  ];

  late final AnimationController _pathController;
  late final AnimationController _pulseController;
  Timer? _stepTimer;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0,
      upperBound: 1,
      value: 1,
    );

    if (widget.responseReady) {
      _currentStep = _steps.length;
    } else {
      _stepTimer = Timer.periodic(const Duration(milliseconds: 240), (_) {
        if (!mounted) return;
        if (_currentStep < _steps.length - 1) {
          setState(() => _currentStep++);
          if (_currentStep == _steps.length - 1) {
            _pulseController.repeat(reverse: true);
          }
        } else {
          _stepTimer?.cancel();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant RouteAnalysisLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.responseReady && widget.responseReady) {
      _stepTimer?.cancel();
      _pulseController
        ..stop()
        ..value = 1;
      _pathController.animateTo(
        1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      setState(() => _currentStep = _steps.length);
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _pathController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFAFAFB),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        child: Column(
          children: [
            const Spacer(flex: 2),
            SizedBox(
              key: const ValueKey('analysis-path-animation'),
              width: 270,
              height: 145,
              child: AnimatedBuilder(
                animation: _pathController,
                builder: (context, _) => CustomPaint(
                  painter: _RoutePathPainter(
                    progress: Curves.easeInOutCubic.transform(
                      _pathController.value,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '안전 경로를 분석하고 있어요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '도로 연결 상태와 위험 요소를 차분히 살펴보는 중이에요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 34),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 310),
              child: Column(
                children: [
                  for (final (index, label) in _steps.indexed)
                    _AnalysisStep(
                      label: label,
                      state: index < _currentStep
                          ? _AnalysisStepState.completed
                          : index == _currentStep
                          ? _AnalysisStepState.current
                          : _AnalysisStepState.pending,
                      pulse: _pulseController,
                    ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            TextButton(
              key: const ValueKey('cancel-route-analysis'),
              onPressed: widget.onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondary,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _AnalysisStepState { completed, current, pending }

class _AnalysisStep extends StatelessWidget {
  const _AnalysisStep({
    required this.label,
    required this.state,
    required this.pulse,
  });

  final String label;
  final _AnalysisStepState state;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final current = state == _AnalysisStepState.current;
    final completed = state == _AnalysisStepState.completed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: completed
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.muted,
                    )
                  : current
                  ? ScaleTransition(
                      scale: Tween<double>(begin: .78, end: 1).animate(
                        CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
                      ),
                      child: const _StepDot(color: AppColors.brand, size: 11),
                    )
                  : const _StepDot(color: AppColors.border, size: 11),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: current ? AppColors.brand : AppColors.muted,
                fontSize: 15,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: SizedBox.square(dimension: size),
  );
}

class _RoutePathPainter extends CustomPainter {
  const _RoutePathPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(24, size.height - 28);
    final end = Offset(size.width - 24, 28);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * .30,
        size.height * .98,
        size.width * .34,
        size.height * .20,
        size.width * .54,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .72,
        size.height * .72,
        size.width * .72,
        size.height * .06,
        end.dx,
        end.dy,
      );

    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    final metric = route.computeMetrics().first;
    final visibleRoute = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      visibleRoute,
      Paint()
        ..color = AppColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(start, 7, Paint()..color = AppColors.ink);
    canvas.drawCircle(end, 8, Paint()..color = AppColors.brand);
    canvas.drawCircle(
      end,
      3,
      Paint()..color = Colors.white.withValues(alpha: .92),
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePathPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
