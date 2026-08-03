import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

/// Reusable persistent banner ad slot: loads, periodically refreshes, and
/// disposes its own [BannerAd], rendering nothing until the first load
/// succeeds. Same lifecycle pattern as the bottom-nav and Sınırsız Mod
/// banners, extracted so new placements (room lobby, room end screen) don't
/// each reimplement the load/refresh/dispose dance.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, this.refreshInterval = const Duration(seconds: 30)});

  final Duration refreshInterval;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _bannerAd;
  bool _isReady = false;
  Timer? _refreshTimer;
  bool _reloadInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _load() {
    AdService.loadBannerAd(
      adSize: AdSize.banner,
      onAdLoaded: (ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        setState(() {
          _bannerAd = ad;
          _isReady = true;
        });
      },
      onAdFailedToLoad: (error) {
        if (!mounted) return;
        Future<void>.delayed(const Duration(seconds: 30), () {
          if (mounted) _reload();
        });
      },
    );
  }

  void _reload() {
    if (!mounted || _reloadInFlight) return;
    _reloadInFlight = true;
    final old = _bannerAd;
    setState(() {
      _bannerAd = null;
      _isReady = false;
    });
    old?.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _reloadInFlight = false;
        return;
      }
      AdService.loadBannerAd(
        adSize: AdSize.banner,
        forceNewLoad: true,
        onAdLoaded: (ad) {
          _reloadInFlight = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad;
            _isReady = true;
          });
        },
        onAdFailedToLoad: (error) {
          _reloadInFlight = false;
          if (!mounted) return;
          Future<void>.delayed(const Duration(seconds: 30), () {
            if (mounted) _reload();
          });
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
