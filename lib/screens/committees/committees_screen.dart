import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';
import '../../models/committee.dart';
import '../../models/enums.dart';
import '../../providers/committee_provider.dart' show AsyncValue, CommitteeProvider;
import '../../providers/locale_provider.dart';
import '../../widgets/entity_tiles.dart';
import '../../widgets/state_views.dart';

/// Every committee, searchable and filterable by status.
///
/// Search runs entirely in the provider against the already-loaded list: typing
/// in the box never touches SQLite, so results appear on the same frame.
class CommitteesScreen extends StatefulWidget {
  const CommitteesScreen({super.key});

  @override
  State<CommitteesScreen> createState() => _CommitteesScreenState();
}

class _CommitteesScreenState extends State<CommitteesScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final AppLocalizations s = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final CommitteeProvider provider = context.watch<CommitteeProvider>();
    final AsyncValue<List<Committee>> state = provider.state;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.navCommittees),
        actions: <Widget>[
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: provider.load,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.createCommittee),
        icon: const Icon(Icons.add_rounded),
        label: Text(s.newCommittee),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
            child: TextField(
              controller: _search,
              onChanged: provider.search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.searchCommittees,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: provider.isSearching
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          provider.search('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              children: <Widget>[
                _FilterChip(
                  label: '${s.allCount} (${provider.totalCount})',
                  selected: provider.statusFilter == null,
                  onTap: () => provider.setStatusFilter(null),
                ),
                _FilterChip(
                  label: '${s.activeCount} (${provider.activeCount})',
                  selected: provider.statusFilter == CommitteeStatus.active,
                  onTap: () => provider.setStatusFilter(CommitteeStatus.active),
                ),
                _FilterChip(
                  label: '${s.completedCount} (${provider.completedCount})',
                  selected: provider.statusFilter == CommitteeStatus.completed,
                  onTap: () => provider.setStatusFilter(CommitteeStatus.completed),
                ),
                _FilterChip(
                  label: s.archived,
                  selected: provider.statusFilter == CommitteeStatus.archived,
                  onTap: () => provider.setStatusFilter(CommitteeStatus.archived),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, provider, state, theme, s)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CommitteeProvider provider,
    AsyncValue<List<Committee>> state,
    ThemeData theme,
    AppLocalizations s,
  ) {
    if (state.isLoading && state.isEmpty) return const LoadingState();
    if (state.hasError && state.isEmpty) {
      return ErrorState(message: state.error!, onRetry: provider.load);
    }
    if (provider.items.isEmpty) {
      if (provider.isSearching) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: s.noMatches,
          message: s.noMatchesMsg,
          actionLabel: s.clearSearch,
          onAction: () { _search.clear(); provider.search(''); },
        );
      }
      if (provider.statusFilter != null) {
        return EmptyState(
          icon: Icons.filter_alt_off_rounded,
          title: s.nothingHere,
          message: '${s.nothingHere} ${provider.statusFilter!.label.toLowerCase()}.',
          actionLabel: s.allCount,
          onAction: () => provider.setStatusFilter(null),
        );
      }
      return EmptyState(
        icon: Icons.groups_2_outlined,
        title: s.noCommitteesYet,
        message: s.noCommitteesMsg,
        actionLabel: s.createACommittee,
        onAction: () => Navigator.of(context).pushNamed(AppRoutes.createCommittee),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 96),
        itemCount: provider.items.length,
        itemBuilder: (BuildContext context, int index) {
          final Committee item = provider.items[index];
          return CommitteeTile(
            committee: item,
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.committeeDetails, arguments: item.id),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}
