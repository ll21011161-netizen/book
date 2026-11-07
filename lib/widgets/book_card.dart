import '../core/cover_origin.dart';
// lib/widgets/book_card.dart
import 'package:flutter/material.dart';
import '../models/library_item.dart';
import 'page_thumbnail.dart';
import '../core/theme.dart';
import '../core/config.dart';
import 'cover_hero.dart';
import 'drag_cover.dart';
import 'spring_press.dart';

class BookCard extends StatefulWidget {
  final MangaBook book;
  final VoidCallback onTap;
  final ValueChanged<CoverOrigin?>? onOpen;
  final VoidCallback onLongPress;
  final bool isSelected;
  final DragVisualMode dragVisualMode;
  final bool cropCover;
  final bool allowThumbnailWork;

  const BookCard({
    Key? key,
    required this.book,
    required this.onTap,
    this.onOpen,
    required this.onLongPress,
    this.isSelected = false,
    this.dragVisualMode = DragVisualMode.none,
    this.cropCover = true,
    this.allowThumbnailWork = true,
  }) : super(key: key);

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  final _cover = GlobalKey<CoverHeroState>();
  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final isSelected = widget.isSelected;
    final dragVisualMode = widget.dragVisualMode;
    final cropCover = widget.cropCover;
    // 保留進度計算，用來判斷是否顯示「已看完」的打勾圖示
    final double progress = book.totalPageCount > 0
        ? (book.lastReadPage + 1) / book.totalPageCount
        : 0.0;
    final bool isCompleted = progress >= 1.0;

    return HeroMode(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: SpringPress(
          onTap: () => widget.onOpen != null
              ? widget.onOpen!(_cover.currentState?.origin)
              : onTap(),
          onLongPress: onLongPress,
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DragCover(
                    mode: dragVisualMode,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverHero(
                          key: _cover,
                          tag: 'book_cover_${book.id}',
                          identity: book.coverPath,
                          builder: (report) => ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTheme.cornerRadius),
                            child: Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: !widget.allowThumbnailWork
                                  ? const SizedBox.expand()
                                  : PageThumbnail(
                                      path: book.coverPath ?? '',
                                      onImageProvider: (provider) => report(
                                          0,
                                          provider,
                                          cropCover
                                              ? BoxFit.cover
                                              : BoxFit.contain),
                                      fit: cropCover
                                          ? BoxFit.cover
                                          : BoxFit.contain,
                                      cacheWidth: AppConfig.thumbnailCacheWidth,
                                      borderRadius: BorderRadius.zero,
                                      preserveAnimation: true,
                                      deferGenerationUntilReady: true,
                                    ),
                            ),
                          ),
                        ),

                        // 🌟 已經把這裡原本的進度條 (Progress Bar) 溫柔地移除了喔！

                        if (isSelected)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.cornerRadius),
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2),
                            ),
                            child: Center(
                                child: Icon(Icons.check_circle,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: 32)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: Theme.of(context).textTheme.bodyLarge?.color),
                  ),
                ),
                SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      Text("${book.totalPageCount} 頁",
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color)),
                      const Spacer(),
                      // 🌟 已經把原本的百分比文字移除了，只保留看完時的溫馨小勾勾！
                      if (isCompleted)
                        const Icon(Icons.check_circle,
                            size: 12, color: Colors.greenAccent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
