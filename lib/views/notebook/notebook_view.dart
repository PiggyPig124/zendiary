import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/notebook_entry.dart';
import '../../providers/notebook_provider.dart';
import '../navigation_state.dart';
import '../common/page_header.dart';

const List<String> noteTagSuggestions = [
  'AI\u6574\u7406',
  '\u4efb\u52a1',
  '\u7075\u611f',
  '\u4f1a\u8bae',
  '\u65e5\u8bb0',
];
const double noteTagFilterHeight = 34;

class NotebookView extends ConsumerStatefulWidget {
  final String pageTitle;
  final String createLabel;

  const NotebookView({
    super.key,
    this.pageTitle = '笔记',
    this.createLabel = '新建笔记',
  });

  @override
  ConsumerState<NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends ConsumerState<NotebookView> {
  NotebookEntry? _selectedNote;
  String? _selectedTag;
  bool _isPreviewMode = false;
  bool _isDirty = false;
  bool _showArchived = false;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    _titleCtrl.addListener(_markDirty);
    _contentCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _saveCurrentNote();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _markDirty() => _isDirty = true;

  void _saveCurrentNote() {
    if (_selectedNote == null || !_isDirty) return;
    final updated = _selectedNote!.copyWith(
      title: _titleCtrl.text.trim().isEmpty
          ? '\u65e0\u6807\u9898'
          : _titleCtrl.text.trim(),
      content: _contentCtrl.text,
    );
    ref.read(notebookListProvider.notifier).updateNote(updated);
    _selectedNote = updated;
    _isDirty = false;
  }

  void _selectNote(NotebookEntry note) {
    _saveCurrentNote();
    setState(() {
      _selectedNote = note;
      _titleCtrl.text = note.title == '\u65e0\u6807\u9898' ? '' : note.title;
      _contentCtrl.text = note.content;
      _isDirty = false;
      _isPreviewMode = false;
    });
  }

  Future<void> _createNewNote() async {
    _saveCurrentNote();
    final draft = await showDialog<NotebookEntry>(
      context: context,
      builder: (_) => const _CreateNoteDialog(),
    );
    if (draft == null) return;
    ref.read(notebookListProvider.notifier).addNote(draft);
    _selectNote(draft);
  }

  void _deleteNote(NotebookEntry note) {
    if (_selectedNote?.id == note.id) {
      setState(() {
        _selectedNote = null;
        _titleCtrl.clear();
        _contentCtrl.clear();
        _isDirty = false;
      });
    }
    ref.read(notebookListProvider.notifier).deleteNote(note.id);
  }

  Future<void> _editNoteMeta(NotebookEntry note) async {
    _saveCurrentNote();
    final updated = await showDialog<NotebookEntry>(
      context: context,
      builder: (_) => _CreateNoteDialog(note: note),
    );
    if (updated == null) return;
    ref.read(notebookListProvider.notifier).updateNote(updated);
    if (_selectedNote?.id == updated.id) {
      setState(() => _selectedNote = updated);
    }
  }

  void _toggleArchive(NotebookEntry note) {
    _saveCurrentNote();
    final archived = !note.isArchived;
    ref
        .read(notebookListProvider.notifier)
        .archiveNote(note.id, archived: archived);
    if (_selectedNote?.id == note.id) {
      if (archived && !_showArchived) {
        setState(() {
          _selectedNote = null;
          _titleCtrl.clear();
          _contentCtrl.clear();
          _isDirty = false;
        });
      } else {
        setState(() => _selectedNote = note.copyWith(isArchived: archived));
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(archived ? '已归档笔记' : '已恢复笔记'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref
              .read(notebookListProvider.notifier)
              .archiveNote(note.id, archived: !archived),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedNoteIdProvider, (previous, requestedId) {
      if (requestedId == null || requestedId == previous) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final note = ref
            .read(notebookListProvider)
            .cast<NotebookEntry?>()
            .firstWhere(
              (value) => value?.id == requestedId,
              orElse: () => null,
            );
        if (note != null) {
          if (note.isArchived && !_showArchived) {
            setState(() => _showArchived = true);
          }
          _selectNote(note);
        }
        ref.read(selectedNoteIdProvider.notifier).clear();
      });
    });
    final notes = ref.watch(notebookListProvider);
    final visibleNotes = _showArchived
        ? notes
        : notes.where((note) => !note.isArchived).toList();
    final allTags = {
      for (final note in visibleNotes)
        for (final tag in note.tags)
          if (tag.trim().isNotEmpty) tag.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final filteredNotes = switch (_selectedTag) {
      null => visibleNotes,
      '' => visibleNotes.where((note) => note.tags.isEmpty).toList(),
      final tag =>
        visibleNotes.where((note) => note.tags.contains(tag)).toList(),
    };

    return Column(
      children: [
        PageHeader(
          title: widget.pageTitle,
          trailing: Wrap(
            spacing: ZenTheme.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (notes.any((note) => note.isArchived))
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _showArchived = !_showArchived;
                    if (!_showArchived && _selectedNote?.isArchived == true) {
                      _selectedNote = null;
                    }
                  }),
                  icon: Icon(
                    _showArchived
                        ? Icons.archive_outlined
                        : Icons.inventory_2_outlined,
                    size: 17,
                  ),
                  label: Text(_showArchived ? '隐藏归档' : '查看归档'),
                  style: OutlinedButton.styleFrom(
                    textStyle: ZenTheme.labelMedium,
                    foregroundColor: ZenTheme.textBody,
                    side: const BorderSide(color: ZenTheme.borderSubtle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        ZenTheme.radiusButton,
                      ),
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _createNewNote,
                icon: const Icon(Icons.add),
                label: Text(widget.createLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: ZenTheme.accentMatcha,
                  foregroundColor: ZenTheme.backgroundCard,
                  textStyle: ZenTheme.labelMedium,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZenTheme.radiusButton),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final listPanel = SizedBox(
                width: isMobile ? constraints.maxWidth : 300,
                child: ColoredBox(
                  color: ZenTheme.backgroundCanvas,
                  child: Column(
                    children: [
                      if (visibleNotes.isNotEmpty)
                        _TagFilterBar(
                          tags: allTags,
                          selectedTag: _selectedTag,
                          onSelected: (tag) =>
                              setState(() => _selectedTag = tag),
                        ),
                      Expanded(
                        child: visibleNotes.isEmpty
                            ? const _EmptyState(
                                icon: Icons.menu_book_outlined,
                                message: '\u6682\u65e0\u5f53\u524d\u7b14\u8bb0',
                                detail:
                                    '\u70b9\u51fb\u53f3\u4e0a\u89d2\u65b0\u5efa\u7b14\u8bb0\u6216\u67e5\u770b\u5f52\u6863',
                              )
                            : filteredNotes.isEmpty
                            ? const _EmptyState(
                                icon: Icons.filter_alt_off_outlined,
                                message: '\u6682\u65e0\u7b14\u8bb0',
                                detail:
                                    '\u5f53\u524d\u6807\u7b7e\u4e0b\u8fd8\u6ca1\u6709\u7b14\u8bb0',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  bottom: ZenTheme.listBottomPadding,
                                ),
                                itemCount: filteredNotes.length,
                                itemBuilder: (context, index) {
                                  final note = filteredNotes[index];
                                  return _NoteListTile(
                                    note: note,
                                    isSelected: _selectedNote?.id == note.id,
                                    onTap: () => _selectNote(note),
                                    onDelete: () => _deleteNote(note),
                                    onEditMeta: () => _editNoteMeta(note),
                                    onArchive: () => _toggleArchive(note),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
              final editorPanel = ColoredBox(
                color: ZenTheme.backgroundCard,
                child: _selectedNote == null
                    ? const _EmptyState(
                        icon: Icons.edit_note_outlined,
                        message:
                            '\u9009\u62e9\u6216\u65b0\u5efa\u4e00\u7bc7\u7b14\u8bb0',
                        detail:
                            '\u5728\u8fd9\u91cc\u8bb0\u5f55\u4f60\u7684\u60f3\u6cd5',
                      )
                    : _NotebookEditor(
                        note: _selectedNote!,
                        titleController: _titleCtrl,
                        contentController: _contentCtrl,
                        isPreviewMode: _isPreviewMode,
                        onEditMeta: () => _editNoteMeta(_selectedNote!),
                        onPreviewChanged: (value) {
                          _saveCurrentNote();
                          setState(() => _isPreviewMode = value);
                        },
                      ),
              );

              if (!isMobile) {
                return Row(
                  children: [
                    listPanel,
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: ZenTheme.borderSubtle,
                    ),
                    Expanded(child: editorPanel),
                  ],
                );
              }

              if (_selectedNote == null) return listPanel;
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _selectedNote = null),
                      icon: const Icon(Icons.arrow_back, size: 17),
                      label: const Text('全部笔记'),
                    ),
                  ),
                  Expanded(child: editorPanel),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotebookEditor extends StatelessWidget {
  const _NotebookEditor({
    required this.note,
    required this.titleController,
    required this.contentController,
    required this.isPreviewMode,
    required this.onEditMeta,
    required this.onPreviewChanged,
  });

  final NotebookEntry note;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final bool isPreviewMode;
  final VoidCallback onEditMeta;
  final ValueChanged<bool> onPreviewChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZenTheme.spaceXxxl,
            vertical: ZenTheme.spaceLg,
          ),
          decoration: const BoxDecoration(
            color: ZenTheme.backgroundWarm,
            border: Border(bottom: BorderSide(color: ZenTheme.borderSubtle)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final meta = Wrap(
                spacing: ZenTheme.spaceSm,
                runSpacing: ZenTheme.spaceXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '\u6700\u540e\u66f4\u65b0 ${DateFormat('MM-dd HH:mm').format(note.updatedAt)}',
                    style: ZenTheme.labelMedium,
                  ),
                  ...note.tags.take(3).map(_TagChip.new),
                ],
              );
              final controls = Wrap(
                spacing: ZenTheme.spaceXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune_outlined, size: 18),
                    color: ZenTheme.textMuted,
                    tooltip: '\u7f16\u8f91\u6807\u7b7e',
                    onPressed: onEditMeta,
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('\u7f16\u8f91'),
                        icon: Icon(Icons.edit_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('\u9884\u89c8'),
                        icon: Icon(Icons.visibility_outlined, size: 16),
                      ),
                    ],
                    selected: {isPreviewMode},
                    onSelectionChanged: (value) =>
                        onPreviewChanged(value.first),
                    style: SegmentedButton.styleFrom(
                      foregroundColor: ZenTheme.textBody,
                      selectedForegroundColor: ZenTheme.backgroundCard,
                      backgroundColor: ZenTheme.interactivePressed,
                      selectedBackgroundColor: ZenTheme.accentMatcha,
                      side: const BorderSide(color: ZenTheme.borderSubtle),
                      textStyle: ZenTheme.labelMedium,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: meta),
                        controls.children.first,
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: controls.children.last,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: meta),
                  controls,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: isPreviewMode
              ? _NotebookPreview(
                  titleController: titleController,
                  contentController: contentController,
                )
              : _NotebookEditArea(
                  titleController: titleController,
                  contentController: contentController,
                ),
        ),
      ],
    );
  }
}

class _NotebookEditArea extends StatelessWidget {
  const _NotebookEditArea({
    required this.titleController,
    required this.contentController,
  });

  final TextEditingController titleController;
  final TextEditingController contentController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ZenTheme.spaceHuge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            style: ZenTheme.headingZen.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: '\u65e0\u6807\u9898',
              hintStyle: ZenTheme.emptyStateSub,
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: ZenTheme.spaceXl),
          Expanded(
            child: TextField(
              controller: contentController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: ZenTheme.bodyMain.copyWith(fontSize: 16, height: 1.6),
              decoration: const InputDecoration(
                hintText: '\u5728\u8fd9\u91cc\u4e66\u5199 Markdown...',
                hintStyle: ZenTheme.emptyStateSub,
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookPreview extends StatelessWidget {
  const _NotebookPreview({
    required this.titleController,
    required this.contentController,
  });

  final TextEditingController titleController;
  final TextEditingController contentController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ZenTheme.spaceHuge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleController.text.isEmpty
                ? '\u65e0\u6807\u9898'
                : titleController.text,
            style: ZenTheme.headingZen.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ZenTheme.spaceXxxl),
          Expanded(
            child: Markdown(
              data: contentController.text.isEmpty
                  ? '*\u6ca1\u6709\u5185\u5bb9*'
                  : contentController.text,
              padding: EdgeInsets.zero,
              styleSheet: MarkdownStyleSheet(
                p: ZenTheme.bodyMain.copyWith(fontSize: 16, height: 1.6),
                h1: ZenTheme.headingZen.copyWith(fontSize: 24),
                h2: ZenTheme.headingZen.copyWith(fontSize: 20),
                blockquote: ZenTheme.bodyMain.copyWith(
                  color: ZenTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: ZenTheme.borderSage, width: 4),
                  ),
                ),
                code: ZenTheme.bodyMain.copyWith(
                  backgroundColor: ZenTheme.backgroundWarm,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                codeblockDecoration: BoxDecoration(
                  color: ZenTheme.backgroundWarm,
                  borderRadius: BorderRadius.circular(ZenTheme.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });

  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    const visibleTagCount = 2;
    final selectedTagInList = selectedTag != null && tags.contains(selectedTag);
    final visibleTags = <String>[
      if (selectedTagInList) selectedTag!,
      ...tags
          .where((tag) => tag != selectedTag)
          .take(selectedTagInList ? visibleTagCount - 1 : visibleTagCount),
    ];
    final hasMoreTags = tags.length > visibleTags.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        ZenTheme.spaceXl,
        ZenTheme.spaceLg,
        ZenTheme.spaceXl,
        ZenTheme.spaceLg,
      ),
      decoration: const BoxDecoration(
        color: ZenTheme.backgroundMuted,
        border: Border(bottom: BorderSide(color: ZenTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          _TagFilterChip(
            label: '\u5168\u90e8',
            isSelected: selectedTag == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: ZenTheme.spaceSm),
          for (final tag in visibleTags) ...[
            Expanded(
              child: _TagFilterChip(
                label: '#$tag',
                isSelected: selectedTag == tag,
                onTap: () => onSelected(tag),
              ),
            ),
            const SizedBox(width: ZenTheme.spaceSm),
          ],
          if (hasMoreTags)
            _TagMoreButton(
              tags: tags,
              selectedTag: selectedTag,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }
}

class _TagMoreButton extends StatelessWidget {
  const _TagMoreButton({
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });

  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '\u66f4\u591a\u6807\u7b7e',
      child: InkWell(
        onTap: () => _showTagPicker(context),
        borderRadius: BorderRadius.circular(ZenTheme.radiusChip),
        child: Container(
          width: 42,
          height: noteTagFilterHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZenTheme.backgroundWarm,
            borderRadius: BorderRadius.circular(ZenTheme.radiusChip),
            border: Border.all(color: ZenTheme.borderSage),
          ),
          child: const Icon(
            Icons.more_horiz,
            size: 18,
            color: ZenTheme.textBody,
          ),
        ),
      ),
    );
  }

  Future<void> _showTagPicker(BuildContext context) async {
    const allTagsValue = '__all_notes__';
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _TagPickerDialog(
        tags: tags,
        selectedTag: selectedTag,
        allTagsValue: allTagsValue,
      ),
    );
    if (!context.mounted || picked == null) return;
    onSelected(picked == allTagsValue ? null : picked);
  }
}

class _TagPickerDialog extends StatefulWidget {
  const _TagPickerDialog({
    required this.tags,
    required this.selectedTag,
    required this.allTagsValue,
  });

  final List<String> tags;
  final String? selectedTag;
  final String allTagsValue;

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTags = _query.isEmpty
        ? widget.tags
        : widget.tags
              .where((tag) => tag.toLowerCase().contains(_query))
              .toList();

    return Dialog(
      backgroundColor: ZenTheme.backgroundCanvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZenTheme.radiusDialog),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(ZenTheme.spaceXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '\u9009\u62e9\u6807\u7b7e',
                      style: ZenTheme.headingZen,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: ZenTheme.textMuted,
                    tooltip: '\u5173\u95ed',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: ZenTheme.spaceLg),
              TextField(
                controller: _searchCtrl,
                style: ZenTheme.bodyMain,
                decoration: _inputDecoration(
                  hintText: '\u641c\u7d22\u6807\u7b7e',
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: ZenTheme.spaceLg),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: ZenTheme.spaceMd,
                    runSpacing: ZenTheme.spaceMd,
                    children: [
                      _TagFilterChip(
                        label: '\u5168\u90e8',
                        isSelected: widget.selectedTag == null,
                        onTap: () =>
                            Navigator.pop(context, widget.allTagsValue),
                      ),
                      for (final tag in filteredTags)
                        _TagFilterChip(
                          label: '#$tag',
                          isSelected: widget.selectedTag == tag,
                          onTap: () => Navigator.pop(context, tag),
                        ),
                    ],
                  ),
                ),
              ),
              if (filteredTags.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: ZenTheme.spaceLg),
                  child: Text(
                    '\u6ca1\u6709\u5339\u914d\u7684\u6807\u7b7e',
                    style: ZenTheme.emptyStateSub,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagFilterChip extends StatelessWidget {
  const _TagFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: noteTagFilterHeight,
      child: ChoiceChip(
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZenTheme.labelMedium.copyWith(
            color: isSelected ? ZenTheme.backgroundCard : ZenTheme.textBody,
          ),
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: ZenTheme.backgroundWarm,
        selectedColor: ZenTheme.accentMatcha,
        side: BorderSide(
          color: isSelected ? ZenTheme.accentMatcha : ZenTheme.borderSage,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZenTheme.radiusChip),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        showCheckmark: false,
      ),
    );
  }
}

class _CreateNoteDialog extends StatefulWidget {
  const _CreateNoteDialog({this.note});

  final NotebookEntry? note;

  @override
  State<_CreateNoteDialog> createState() => _CreateNoteDialogState();
}

class _CreateNoteDialogState extends State<_CreateNoteDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _tagsCtrl;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleCtrl = TextEditingController(text: note?.title ?? '');
    _tagsCtrl = TextEditingController(text: note?.tags.join('\uFF0C') ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.note != null;

    return AlertDialog(
      backgroundColor: ZenTheme.backgroundCanvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZenTheme.radiusDialog),
      ),
      title: Text(
        isEdit ? '\u7f16\u8f91\u7b14\u8bb0' : '\u65b0\u5efa\u7b14\u8bb0',
        style: ZenTheme.headingZen,
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QuietField(
              controller: _titleCtrl,
              label: '\u6807\u9898',
              hint: '\u65e0\u6807\u9898',
            ),
            const SizedBox(height: ZenTheme.spaceXl),
            _QuietField(
              controller: _tagsCtrl,
              label: '\u6807\u7b7e',
              hint:
                  '\u8f93\u5165\u6807\u7b7e\uff0c\u7528\u9017\u53f7\u6216\u7a7a\u683c\u5206\u9694',
            ),
            const SizedBox(height: ZenTheme.spaceLg),
            Wrap(
              spacing: ZenTheme.spaceSm,
              runSpacing: ZenTheme.spaceSm,
              children: noteTagSuggestions
                  .map(
                    (tag) =>
                        _SoftChip(label: '#$tag', onTap: () => _appendTag(tag)),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final tags = _parseTags(_tagsCtrl.text);
            final note = widget.note;
            Navigator.pop(
              context,
              note == null
                  ? NotebookEntry(
                      title: title.isEmpty ? '\u65e0\u6807\u9898' : title,
                      content: '',
                      tags: tags,
                    )
                  : note.copyWith(
                      title: title.isEmpty ? '\u65e0\u6807\u9898' : title,
                      tags: tags,
                    ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: ZenTheme.accentMatcha,
            foregroundColor: ZenTheme.backgroundCard,
          ),
          child: const Text('\u4fdd\u5b58'),
        ),
      ],
    );
  }

  void _appendTag(String tag) {
    final tags = _parseTags(_tagsCtrl.text);
    if (!tags.contains(tag)) tags.add(tag);
    _tagsCtrl.text = tags.join('\uFF0C');
  }

  List<String> _parseTags(String value) {
    return value
        .split(RegExp('[,\uFF0C\\s]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }
}

class _QuietField extends StatelessWidget {
  const _QuietField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: ZenTheme.bodyMain,
      decoration: _inputDecoration(
        hintText: hint,
      ).copyWith(labelText: label, labelStyle: ZenTheme.labelMedium),
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: ZenTheme.labelMedium),
      onPressed: onTap,
      backgroundColor: ZenTheme.backgroundWarm,
      side: const BorderSide(color: ZenTheme.borderSage),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZenTheme.radiusChip),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onEditMeta,
    required this.onArchive,
  });

  final NotebookEntry note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditMeta;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final previewText = note.content.replaceAll(RegExp(r'\n'), ' ');

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: note.isArchived ? 0.62 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZenTheme.spaceXxl,
            vertical: ZenTheme.spaceXl,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? ZenTheme.backgroundMuted
                : ZenTheme.backgroundCard,
            border: Border(
              left: BorderSide(
                color: isSelected
                    ? ZenTheme.accentMatcha
                    : ZenTheme.borderSubtle,
                width: isSelected ? 3 : 1,
              ),
              bottom: const BorderSide(color: ZenTheme.borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZenTheme.headingSection.copyWith(
                        color: isSelected
                            ? ZenTheme.accentGreen
                            : ZenTheme.textHeading,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: ZenTheme.textMuted,
                    ),
                    color: ZenTheme.backgroundCard,
                    onSelected: (value) {
                      if (value == 'meta') onEditMeta();
                      if (value == 'archive') onArchive();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'meta',
                        child: Text('\u8bbe\u7f6e', style: ZenTheme.bodyMain),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(
                          note.isArchived
                              ? '\u6062\u590d\u7b14\u8bb0'
                              : '\u5f52\u6863\u7b14\u8bb0',
                          style: ZenTheme.bodyMain,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          '\u5220\u9664',
                          style: ZenTheme.bodyMain.copyWith(
                            color: ZenTheme.accentWarnOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (note.isArchived) ...[
                const SizedBox(height: ZenTheme.spaceXs),
                Text('\u5df2\u5f52\u6863', style: ZenTheme.labelMedium),
              ],
              const SizedBox(height: ZenTheme.spaceSm),
              Text(
                previewText.isEmpty ? '\u65e0\u6b63\u6587' : previewText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZenTheme.labelMedium.copyWith(height: 1.4),
              ),
              const SizedBox(height: ZenTheme.spaceMd),
              Row(
                children: [
                  if (note.tags.isNotEmpty)
                    Flexible(
                      child: Text(
                        note.tags.take(2).map((tag) => '#$tag').join(' '),
                        overflow: TextOverflow.ellipsis,
                        style: ZenTheme.labelMedium,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    DateFormat('MM-dd').format(note.updatedAt),
                    style: ZenTheme.labelMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: ZenTheme.spaceXs),
      padding: const EdgeInsets.symmetric(
        horizontal: ZenTheme.spaceSm,
        vertical: ZenTheme.spaceXxs,
      ),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundMuted,
        borderRadius: BorderRadius.circular(ZenTheme.radiusBadge),
        border: Border.all(color: ZenTheme.borderSage),
      ),
      child: Text('#$label', style: ZenTheme.labelMedium),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.detail,
  });

  final IconData icon;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: ZenTheme.textCompleted),
          const SizedBox(height: ZenTheme.spaceXl),
          Text(message, style: ZenTheme.emptyState),
          const SizedBox(height: ZenTheme.spaceXs),
          Text(detail, style: ZenTheme.emptyStateSub),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration({String? hintText, Widget? prefixIcon}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: ZenTheme.emptyStateSub,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: ZenTheme.backgroundWarm,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ZenTheme.radiusInput),
      borderSide: const BorderSide(color: ZenTheme.borderSubtle),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ZenTheme.radiusInput),
      borderSide: const BorderSide(color: ZenTheme.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ZenTheme.radiusInput),
      borderSide: const BorderSide(color: ZenTheme.accentMatcha),
    ),
  );
}
