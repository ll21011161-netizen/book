import '../core/cover_origin.dart';
// lib/widgets/folder_card.dart
import 'package:flutter/material.dart';
import '../models/library_item.dart';
import '../core/theme.dart';
import 'cover_hero.dart';
import 'drag_cover.dart';
import 'spring_press.dart'; // 🌟 引入動畫常數

class FolderCard extends StatefulWidget {
  final MangaFolder folder;
  final VoidCallback onTap;
  final ValueChanged<CoverOrigin?>? onOpen;
  final VoidCallback onLongPress;
  final bool isSelected;
  final DragVisualMode dragVisualMode;

  const FolderCard({
    Key? key,
    required this.folder,
    required this.onTap,
    this.onOpen,
    required this.onLongPress,
    this.isSelected = false,
    this.dragVisualMode = DragVisualMode.none,
  }) : super(key: key);

  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  final _cover = GlobalKey<CoverHeroState>();
  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final isSelected = widget.isSelected;
    final dragVisualMode = widget.dragVisualMode;
    final thumbs = folder.thumbnails;

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
                    child: CoverHero(
                      key: _cover,
                      tag: 'folder_cover_${folder.id}',
                      identity: Object.hashAll(thumbs),
                      builder: (report) => Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTheme.cornerRadius),
                            color: Theme.of(context).cardColor,
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTheme.cornerRadius),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FolderCoverPreview(
                                    paths: thumbs,
                                    onImageProvider: (i, provider) =>
                                        report(i, provider, BoxFit.cover)),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Icon(Icons.folder,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                      decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.cornerRadius),
                                          border: Border.all(
                                              color: Colors.blueAccent,
                                              width: 2)),
                                      child: const Center(
                                          child: Icon(Icons.check_circle,
                                              color: Colors.blueAccent,
                                              size: 32))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: Text(folder.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  height: 16,
                  child: Text("${folder.itemCount} 本",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11)),
                ),
              ],
            ),
          ),
        ));
  }
}
