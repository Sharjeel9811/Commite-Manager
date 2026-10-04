import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'app_logo.dart';

/// The "nothing here yet" state.
///
/// Every list in the app routes its empty case through this widget so the copy,
/// spacing and call-to-action look identical everywhere.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 64 : 88,
              height: compact ? 64 : 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 30 : 40, color: scheme.onPrimaryContainer),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (onAction != null) ...<Widget>[
              SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel ?? 'Get started'),
              ),
            ],
            if (onSecondary != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel ?? 'Not now')),
            ],
          ],
        ),
      ),
    );
  }
}

/// A friendly error state with a retry button.
///
/// The raw exception never reaches the user — [onRetry] is offered instead, so a
/// transient database error is always recoverable.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, super.key, this.onRetry, this.compact = false});

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: compact ? 36 : 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Something went wrong',
              style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centred spinner used while a screen's first load is in flight.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          if (label != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// A full-screen splash with the app mark and a subtle progress hint.
///
/// The launch animation fades the mark in with a gentle scale so cold starts
/// feel welcoming instead of abrupt, then the title follows.
class SplashBody extends StatefulWidget {
  const SplashBody({super.key, this.caption});

  final String? caption;

  @override
  State<SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<SplashBody> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.65, curve: Curves.easeOut));
    _scaleIn = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.55, curve: Curves.easeOutBack)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FadeTransition(
      opacity: _fadeIn,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScaleTransition(
              scale: _scaleIn,
              child: const AppLogo(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Committee Manager', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text('Bachat Committee, perfectly managed.', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xxxl),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (widget.caption != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(widget.caption!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
