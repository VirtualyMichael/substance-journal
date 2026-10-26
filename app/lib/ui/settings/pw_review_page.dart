import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/pw_journal_import.dart';
import '../design.dart';

/// The review step of a PsychonautWiki Journal import: which experiences to bring over, and
/// which compound and route each substance in the file becomes. Returns true to import.
///
/// Nothing leaves the device; the plan only changes how the file is read into the journal.
class PwReviewPage extends StatefulWidget {
  const PwReviewPage({super.key, required this.plan});

  final PwImportPlan plan;

  @override
  State<PwReviewPage> createState() => _PwReviewPageState();
}

class _PwReviewPageState extends State<PwReviewPage> {
  PwImportPlan get plan => widget.plan;

  String _targetName(PwCompound c) => c.key != null ? (plan.reference.byKey[c.key]?.name ?? c.key!) : '${c.customName} (new custom compound)';

  /// check = fully matched, timing = compound known but a route is borrowed, add = will be created.
  ({IconData icon, Color color, String note}) _status(List<PwIngestion> doses, ColorScheme scheme) {
    final compound = plan.compoundFor(doses.first);
    if (compound.key == null) {
      return (icon: Icons.add_circle_outline, color: scheme.primary, note: 'Will be added as a custom compound');
    }
    final substance = plan.reference.byKey[compound.key];
    final borrowed = {
      for (final d in doses)
        if (substance != null && substance.route(plan.routeFor(d)) == null) plan.routeFor(d),
    };
    if (borrowed.isEmpty) return (icon: Icons.check_circle_outline, color: Colors.green, note: 'Matched');
    return (
      icon: Icons.timelapse,
      color: Colors.orange,
      note: 'No ${borrowed.join('/')} data for ${substance?.name}; the curve borrows another route\'s timing',
    );
  }

  Future<PwCompound?> _pickCompound(String pwName) {
    return showDialog<PwCompound>(context: context, builder: (_) => _CompoundSearchDialog(plan: plan, pwName: pwName));
  }

  Future<void> _individually(String name, List<PwIngestion> doses) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _IndividualDosesDialog(plan: plan, pwName: name, doses: doses, pick: _pickCompound),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final export = plan.export;
    final chosen = plan.chosenIngestions.toList();
    final selectedExperiences = [for (final i in plan.selected.toList()..sort()) export.experiences[i]];
    final notes = selectedExperiences.fold(0, (n, e) => n + e.notes.length);
    final ratings = selectedExperiences.fold(0, (n, e) => n + e.ratings.length);
    final others = {
      for (final i in chosen)
        if (i.consumer != null && i.consumer!.trim().isNotEmpty && i.consumer!.trim().toLowerCase() != 'me') i.consumer!.trim(),
    }.toList()
      ..sort();

    final byName = <String, List<PwIngestion>>{};
    for (final i in chosen) {
      byName.putIfAbsent(PwImportPlan.nameKey(i.substanceName), () => []).add(i);
    }
    final names = byName.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Import from PsychonautWiki Journal')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(key: const ValueKey('import-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              const SizedBox(width: Gap.sm),
              FilledButton(
                key: const ValueKey('import-confirm'),
                onPressed: plan.selected.isEmpty ? null : () => Navigator.of(context).pop(true),
                child: Text('Import ${chosen.length} doses'),
              ),
            ],
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
            children: [
              Text(
                '${selectedExperiences.length} experiences (${chosen.length} ingestions, $notes timed notes, $ratings ratings)'
                '${selectedExperiences.isEmpty ? '' : ' from ${formatDate(selectedExperiences.map((e) => e.sortDate).reduce((a, b) => a.isBefore(b) ? a : b))} to ${formatDate(selectedExperiences.map((e) => e.sortDate).reduce((a, b) => a.isAfter(b) ? a : b))}'}.',
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'Ingestions with no consumer go to your own journal.'
                '${others.isEmpty ? '' : ' People: ${others.join(', ')} (added if they do not exist yet).'} '
                'Experiences already in the journal are skipped, so importing the same file again adds nothing.'
                '${export.problems.isEmpty ? '' : ' ${export.problems.length} entries could not be read and will be skipped.'}',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.sm),
              SwitchListTile(
                key: const ValueKey('pw-combine'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Combine doses taken close together'),
                subtitle: const Text('Doses by the same person within 12 hours of each other go on one timeline, so a day shows together.'),
                value: plan.combine,
                onChanged: (v) => setState(() => plan.combine = v),
              ),
              Card(
                child: ExpansionTile(
                  key: const ValueKey('pw-file-details'),
                  title: const Text('File details'),
                  subtitle: const Text('Field names only, no values'),
                  childrenPadding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('Experience fields: ${export.experienceKeys.join(', ')}', style: text.bodySmall),
                    const SizedBox(height: 4),
                    SelectableText('Dose fields: ${export.ingestionKeys.join(', ')}', style: text.bodySmall),
                    for (final p in export.problems.take(5))
                      Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(p, style: text.bodySmall)),
                  ],
                ),
              ),
              const SizedBox(height: Gap.sm),
              Card(
                child: ExpansionTile(
                  key: const ValueKey('pw-experiences'),
                  title: Text('Experiences (${plan.selected.length} of ${export.experiences.length} selected)'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                      child: Row(
                        children: [
                          TextButton(
                            key: const ValueKey('pw-select-all'),
                            onPressed: () => setState(() => plan.selected.addAll(List.generate(export.experiences.length, (i) => i))),
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            key: const ValueKey('pw-select-none'),
                            onPressed: () => setState(plan.selected.clear),
                            child: const Text('Select none'),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < export.experiences.length; i++)
                      CheckboxListTile(
                        key: ValueKey('pw-experience-$i'),
                        dense: true,
                        value: plan.selected.contains(i),
                        onChanged: (v) => setState(() => v == true ? plan.selected.add(i) : plan.selected.remove(i)),
                        title: Text(export.experiences[i].title.isEmpty ? 'Untitled' : export.experiences[i].title),
                        subtitle: Text('${formatDate(export.experiences[i].sortDate)}, ${export.experiences[i].ingestions.length} doses'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Text('Compounds', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Each substance in the file is matched by name. Change a match here and it applies to every dose with that name; '
                'open "Doses individually" to give one dose its own compound or route. Your choices are remembered for next time.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.sm),
              if (names.isEmpty) const Text('No experiences selected.'),
              for (final key in names)
                Builder(builder: (context) {
                  final doses = byName[key]!;
                  final pwName = doses.first.substanceName;
                  final status = _status(doses, scheme);
                  final routes = {for (final d in doses) d.route}.toList()..sort();
                  return Card(
                    child: ExpansionTile(
                      key: ValueKey('pw-name-$key'),
                      leading: Icon(status.icon, color: status.color),
                      title: Text(pwName == _targetName(plan.compoundFor(doses.first)) ? pwName : '$pwName  ->  ${_targetName(plan.compoundFor(doses.first))}'),
                      subtitle: Text('${doses.length} doses. ${status.note}'),
                      childrenPadding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey('pw-compound-$key'),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('Change compound'),
                            onPressed: () async {
                              final picked = await _pickCompound(pwName);
                              if (picked != null) setState(() => plan.compoundByName[key] = picked);
                            },
                          ),
                        ),
                        const SizedBox(height: Gap.sm),
                        for (final route in routes)
                          Row(
                            children: [
                              Expanded(child: Text('$route (${doses.where((d) => d.route == route).length} doses)')),
                              DropdownButton<String>(
                                key: ValueKey('pw-route-$key-$route'),
                                value: plan.routeByGroup[PwImportPlan.groupKey(pwName, route)] ?? route,
                                items: [
                                  for (final r in {...pwRoutes, route}) DropdownMenuItem(value: r, child: Text(r)),
                                ],
                                onChanged: (v) => setState(() {
                                  if (v == null || v == route) {
                                    plan.routeByGroup.remove(PwImportPlan.groupKey(pwName, route));
                                  } else {
                                    plan.routeByGroup[PwImportPlan.groupKey(pwName, route)] = v;
                                  }
                                }),
                              ),
                            ],
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: ValueKey('pw-individual-$key'),
                            onPressed: () => _individually(pwName, doses),
                            child: const Text('Doses individually...'),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search the reference compounds (and your custom ones), or keep the name as a custom compound.
class _CompoundSearchDialog extends StatefulWidget {
  const _CompoundSearchDialog({required this.plan, required this.pwName});

  final PwImportPlan plan;
  final String pwName;

  @override
  State<_CompoundSearchDialog> createState() => _CompoundSearchDialogState();
}

class _CompoundSearchDialogState extends State<_CompoundSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = orderCompounds(
      all: widget.plan.reference.substances,
      query: _query,
      sort: CompoundSort.alphabetical,
    ).take(40).toList();
    return AlertDialog(
      title: Text('Match "${widget.pwName}"'),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('pw-search'),
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search compounds'),
              onChanged: (v) => setState(() => _query = v),
            ),
            ListTile(
              key: const ValueKey('pw-as-custom'),
              dense: true,
              leading: const Icon(Icons.add_circle_outline),
              title: Text('Keep as a custom compound "${widget.pwName.trim()}"'),
              onTap: () => Navigator.of(context).pop(PwCompound.custom(widget.pwName.trim())),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final s in results)
                    ListTile(
                      key: ValueKey('pw-pick-${s.key}'),
                      dense: true,
                      title: Text(s.name),
                      subtitle: s.category.isEmpty ? null : Text(s.category, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(PwCompound.reference(s.key)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

/// Every dose of one substance, each with its own route and compound if they should differ.
class _IndividualDosesDialog extends StatefulWidget {
  const _IndividualDosesDialog({required this.plan, required this.pwName, required this.doses, required this.pick});

  final PwImportPlan plan;
  final String pwName;
  final List<PwIngestion> doses;
  final Future<PwCompound?> Function(String pwName) pick;

  @override
  State<_IndividualDosesDialog> createState() => _IndividualDosesDialogState();
}

class _IndividualDosesDialogState extends State<_IndividualDosesDialog> {
  PwImportPlan get plan => widget.plan;

  @override
  Widget build(BuildContext context) {
    final doses = [...widget.doses]..sort((a, b) => a.time.compareTo(b.time));
    return AlertDialog(
      title: Text('${widget.pwName}: doses'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: ListView(
          children: [
            for (final d in doses)
              ListTile(
                key: ValueKey('pw-dose-${d.id}'),
                dense: true,
                title: Text('${formatDate(d.time)} ${formatClock(d.time)}  ${d.dose == null ? '' : formatDose(d.dose, d.unit)}'),
                subtitle: Text(plan.overrides.containsKey(d.id) ? 'Changed: ${plan.compoundFor(d).key ?? plan.compoundFor(d).customName}, ${plan.routeFor(d)}' : 'Same as the group'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      key: ValueKey('pw-dose-route-${d.id}'),
                      value: plan.routeFor(d),
                      items: [for (final r in {...pwRoutes, plan.routeFor(d)}) DropdownMenuItem(value: r, child: Text(r))],
                      onChanged: (v) => setState(() {
                        if (v == null) return;
                        final current = plan.overrides[d.id];
                        plan.overrides[d.id] = PwOverride(compound: current?.compound, route: v);
                      }),
                    ),
                    IconButton(
                      tooltip: 'Choose a compound for this dose',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: () async {
                        final picked = await widget.pick(widget.pwName);
                        if (picked == null) return;
                        final current = plan.overrides[d.id];
                        setState(() => plan.overrides[d.id] = PwOverride(compound: picked, route: current?.route));
                      },
                    ),
                    if (plan.overrides.containsKey(d.id))
                      IconButton(
                        tooltip: 'Back to the group',
                        icon: const Icon(Icons.undo),
                        onPressed: () => setState(() => plan.overrides.remove(d.id)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}
