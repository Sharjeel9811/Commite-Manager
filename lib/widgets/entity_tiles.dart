import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/currency_formatter.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../models/member.dart';
import 'app_card.dart';

/// A committee row for the list screen.
class CommitteeTile extends StatelessWidget {
  const CommitteeTile({required this.committee, required this.onTap, super.key});

  final Committee committee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color statusColor = committeeStatusColor(committee.status, scheme);

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          AppIconBadge(
            icon: committee.status.icon,
            foreground: statusColor,
            background: statusColor.withValues(alpha: 0.12),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  committee.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${committee.memberCount} members • ${CurrencyFormatter.format(committee.contributionAmount)} ${committee.frequency.label.toLowerCase()}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppProgressBar(
                  value: committee.progressPercent / 100,
                  label: '${committee.completedTurns}/${committee.durationPeriods} turns',
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusChip(label: committee.status.label, color: statusColor, compact: true),
        ],
      ),
    );
  }
}

/// A member row for the members screen.
class MemberTile extends StatelessWidget {
  const MemberTile({
    required this.member,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.leadingBadge,
  });

  final Member member;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? leadingBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: <Widget>[
          if (leadingBadge != null)
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                leadingBadge!,
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
              ),
            )
          else
            CircleAvatar(
              radius: 20,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                member.initials,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        member.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isOrganizer) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      StatusChip(
                        label: 'Organizer',
                        color: AppColors.brandAmber,
                        compact: true,
                        icon: Icons.star_rounded,
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The colour used for a committee status, resolved against the current scheme.
Color committeeStatusColor(CommitteeStatus status, ColorScheme scheme) {
  switch (status) {
    case CommitteeStatus.draft:
      return scheme.onSurfaceVariant;
    case CommitteeStatus.active:
      return AppColors.success;
    case CommitteeStatus.completed:
      return AppColors.info;
    case CommitteeStatus.archived:
      return AppColors.neutral;
  }
}

/// A small coloured dot, used in legends and inline status text.
class StatusDot extends StatelessWidget {
  const StatusDot({required this.color, super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
