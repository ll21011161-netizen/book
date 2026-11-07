import 'package:flutter/material.dart';
import '../models/library_item.dart';
import 'app_image.dart';

class BookshelfHeader extends StatelessWidget {
  const BookshelfHeader({super.key, required this.recent, required this.selectedFilter, required this.onFilter, this.onContinue});
  final MangaBook? recent;
  final int selectedFilter;
  final ValueChanged<int> onFilter;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = recent;
    final total = book?.totalPageCount ?? 0;
    final page = total > 0 ? ((book?.lastReadPage ?? 0) + 1).clamp(1, total) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (book != null) Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 80, height: 112, child: AppImage(path: book.coverPath, fit: BoxFit.contain))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('繼續閱讀', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              Text('$page / $total 頁', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total > 0 ? page / total : 0, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: onContinue, child: const Text('繼續閱讀')),
            ])),
          ]),
        ),
      ),
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        for (final (index, label) in ['全部', '最近閱讀', '資料夾', '未閱讀'].indexed)
          Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(label), selected: selectedFilter == index, onSelected: (_) => onFilter(index))),
      ])),
    ]);
  }
}
