import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/pages/info.dart';
import 'package:animestream/ui/pages/mangaDetails.dart';

/// The wide "Continue Watching"-style row card.
///
/// It owns its [InkWell], so a caller that wraps it in another one never sees
/// the tap. Callers that need different navigation pass [onTap]; callers that
/// only need a different destination pass [contentType].
class AnimeCardExtended extends StatelessWidget {
  final int id;
  final String title;
  final String imageUrl;
  final double rating;
  final bool shouldNavigate;
  final bool isAnime;
  final void Function()? afterNavigation;
  final int? watchedEpisodeCount;
  final int? totalEpisodes;
  final String? bannerImageUrl;
  final Color? surfaceColor;
  final double? customWidth;

  /// "anime" or "manga" -- which details page this row opens.
  final String contentType;

  /// Replaces the built-in tap behaviour entirely.
  final void Function()? onTap;

  /// Overrides the built-in route's id.
  ///
  /// [id] stays an int because anime ids are ints everywhere in this app, but a
  /// manga row's id may not be one. Rather than widen the field and churn every
  /// anime call site, a manga row passes the real id here and [id] is ignored.
  final String? routeId;

  const AnimeCardExtended({
    super.key,
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.rating,
    this.shouldNavigate = true,
    this.isAnime = true,
    this.afterNavigation,
    this.watchedEpisodeCount,
    this.totalEpisodes,
    this.bannerImageUrl,
    this.customWidth,
    this.surfaceColor,
    this.contentType = 'anime',
    this.onTap,
    this.routeId,
  });

  bool get _isManga => contentType.toLowerCase() == 'manga';

  void _handleTap(BuildContext context) {
    if (onTap != null) return onTap!();

    // Content type is consulted BEFORE `isAnime`.
    //
    // `isAnime` is a legacy gate that only ever meant "this card cannot open a
    // details page". A manga row *can* -- it just opens a different one. Asking
    // `isAnime` first meant every manga row routed by [contentType] fell
    // through to the "not supported" snackbar and its [routeId] was never read,
    // which is what made this card useless for manga rails.
    if (_isManga) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => MangaDetailsPage(id: routeId ?? id.toString()),
            ),
          )
          .then((val) {
        if (afterNavigation != null) afterNavigation?.call();
      });
      return;
    }

    // A row that is not an anime routes to the manga details page instead of
    // being refused. Manga is a first-class content type now, so "not an anime"
    // no longer means "unsupported" -- the old refusal's premise is simply
    // false, and it was a dead end from every caller that passed isAnime:
    // false. `isAnime` survives as a routing hint: "do not open Info(id:)".
    if (!isAnime) {
      final mangaId = routeId ?? (id > 0 ? id.toString() : null);
      // The one case that genuinely cannot be routed: a card built with no real
      // id at all. Still worth saying out loud rather than swallowing the tap.
      if (mangaId == null) {
        return floatingSnackBar("This row has no id to open.");
      }
      if (!shouldNavigate) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute(builder: (context) => MangaDetailsPage(id: mangaId)),
          )
          .then((val) {
        if (afterNavigation != null) afterNavigation?.call();
      });
      return;
    }

    if (!shouldNavigate) return;

    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (context) => Info(id: id)),
        )
        .then((val) {
      if (afterNavigation != null) afterNavigation?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: appTheme.backgroundColor,
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusColor: appTheme.textSubColor,
          onTap: () => _handleTap(context),
          child: Container(
            width: customWidth ?? 305,
            height: 150,
            color: surfaceColor,
            child: Stack(
              children: [
                if (bannerImageUrl != null)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Opacity(
                      opacity: 0.5,
                      child: CachedNetworkImage(
                        imageUrl: bannerImageUrl!,
                        errorWidget: (context, url, error) {
                          return Image.asset("lib/assets/images/broken_heart.png");
                        },
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                  ),
                Container(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration(milliseconds: 200),
                          fadeInCurve: Curves.easeIn,
                          width: 100,
                          height: 130,
                          errorWidget: (context, url, error) {
                            return Image.asset("lib/assets/images/broken_heart.png");
                          },
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.only(left: 15, top: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: appTheme.textMainColor,
                                  fontFamily: "NotoSans",
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              Container(
                                margin: EdgeInsets.only(bottom: 15),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 52,
                                      padding: EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                          color: appTheme.accentColor.withValues(alpha: 0.8),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.star,
                                            color: appTheme.onAccent,
                                            size: 15,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(left: 3),
                                            child: Text(
                                              "$rating",
                                              style: TextStyle(
                                                color: appTheme.onAccent,
                                                fontFamily: "NotoSans",
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 13, right: 13),
                                      child: Text(
                                        '•',
                                        style: TextStyle(
                                            fontSize: 17, color: Theme.of(context).colorScheme.secondary),
                                      ),
                                    ),
                                    Container(
                                      child: Row(
                                        children: [
                                          Text(
                                            "${watchedEpisodeCount ?? "~"} ",
                                            style: TextStyle(
                                              fontFamily: "NunitoSans",
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          Text(
                                            "/ ${totalEpisodes ?? "??"}",
                                            style: TextStyle(
                                              fontFamily: "NunitoSans",
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
