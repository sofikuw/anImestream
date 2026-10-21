import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/ui/models/widgets/floatyBar/controller.dart';
import 'package:flutter/material.dart';

class FloatyBarItem {
  final String title;
  final IconData icon;

  const FloatyBarItem({
    required this.title,
    required this.icon,
  });
}

/// Divergent's mobile navigation.
///
/// The active destination is a slanted, two-tone slab instead of upstream's
/// rounded expanded pill. The cut is the same "split" used by the header, so
/// the bar reads as part of the fork rather than a themed copy of the original.
class FloatyBottomBar extends StatefulWidget {
  final List<FloatyBarItem> items;
  final FloatyBottomBarController controller;
  final double height;
  final double bottomPadding;
  final Color backgroundColor;
  final Color accentColor;
  final Duration animationDuration;
  final double detachGap;
  final double outerRadius;
  final double activeRadius;

  const FloatyBottomBar({
    super.key,
    required this.items,
    required this.controller,
    this.height = 50,
    this.bottomPadding = 10,
    this.backgroundColor = Colors.black,
    this.accentColor = const Color(0xffcaf979),
    this.animationDuration = const Duration(milliseconds: 200),
    this.detachGap = 5,
    this.outerRadius = 20,
    this.activeRadius = 20,
  });

  @override
  State<FloatyBottomBar> createState() => _FloatyBottomBarState();
}

class _FloatyBottomBarState extends State<FloatyBottomBar> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.controller.currentIndex;
    widget.controller.currentIndexNotifier.addListener(_onControllerIndexChanged);
  }

  @override
  void dispose() {
    widget.controller.currentIndexNotifier.removeListener(_onControllerIndexChanged);
    super.dispose();
  }

  void _onControllerIndexChanged() {
    final newIndex = widget.controller.currentIndex;
    if (newIndex != _currentIndex) {
      setState(() => _currentIndex = newIndex);
    }
  }

  void _onItemTap(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      widget.controller.currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + widget.bottomPadding),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.outerRadius + 4),
            border: Border.all(color: appTheme.accentColor.withAlpha(45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.outerRadius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(widget.items.length, _buildItem),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int i) {
    final item = widget.items[i];
    final isActive = i == _currentIndex;

    return GestureDetector(
      onTap: () => _onItemTap(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedSize(
        duration: widget.animationDuration,
        curve: Curves.easeInOutCubic,
        child: AnimatedContainer(
          duration: widget.animationDuration,
          curve: Curves.easeInOut,
          height: widget.height,
          child: Stack(
            children: [
              if (isActive)
                Positioned.fill(
                  child: ClipPath(
                    clipper: _SplitClipper(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [widget.accentColor, appTheme.secondaryColor],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  left: isActive ? 26 : 18,
                  right: isActive ? 20 : 18,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      color: isActive ? appTheme.onAccent : appTheme.textSubColor,
                    ),
                    if (isActive) ...[
                      SizedBox(width: 8),
                      Text(
                        item.title.toUpperCase(),
                        style: TextStyle(
                          color: appTheme.onAccent,
                          fontFamily: "Poppins",
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final cut = size.height * 0.30;
    return Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
