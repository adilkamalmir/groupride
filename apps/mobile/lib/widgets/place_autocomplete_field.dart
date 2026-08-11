import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/maps_service.dart';
import '../theme.dart';

/// Google Places-backed location field with debounced, location-biased suggestions.
class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.onPlaceSelected,
    this.enabled = true,
    this.biasLat,
    this.biasLng,
    this.nearbyKind,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<GeocodedPlace>? onPlaceSelected;
  final bool enabled;
  final double? biasLat;
  final double? biasLng;
  final String? nearbyKind;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  final _focus = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;
  int _requestId = 0;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant PlaceAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.biasLat != widget.biasLat || oldWidget.biasLng != widget.biasLng) {
      if (_focus.hasFocus) _scheduleSearch(widget.controller.text);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _removeOverlay();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _scheduleSearch(widget.controller.text);
    } else {
      _debounce?.cancel();
      setState(() => _loading = false);
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!_focus.hasFocus) _removeOverlay();
      });
    }
  }

  void _onTextChanged() {
    if (_selecting || !_focus.hasFocus) return;
    _scheduleSearch(widget.controller.text);
  }

  void _scheduleSearch(String raw) {
    // Suggestions only while the field is actively selected.
    if (!_focus.hasFocus) return;

    _debounce?.cancel();
    final q = raw.trim();
    final hasBias = widget.biasLat != null && widget.biasLng != null;
    if (q.length < 2 && !hasBias) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      _removeOverlay();
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 280), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!_focus.hasFocus) return;
    final id = ++_requestId;
    try {
      final maps = context.read<MapsService>();
      List<PlaceSuggestion> results;
      if (q.length < 2 && widget.biasLat != null && widget.biasLng != null) {
        results = await maps.nearby(
          lat: widget.biasLat!,
          lng: widget.biasLng!,
          kind: widget.nearbyKind,
        );
      } else {
        results = await maps.autocomplete(
          q,
          lat: widget.biasLat,
          lng: widget.biasLng,
        );
      }
      if (!mounted || id != _requestId || !_focus.hasFocus) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      _showOverlay();
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      _removeOverlay();
    }
  }

  Future<void> _pick(PlaceSuggestion suggestion) async {
    _selecting = true;
    _removeOverlay();
    widget.controller.text = suggestion.description;
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    _focus.unfocus();

    try {
      final place = await context.read<MapsService>().placeDetails(suggestion.placeId);
      if (place != null && mounted) {
        widget.controller.text = place.formattedAddress;
        widget.onPlaceSelected?.call(place);
      } else if (mounted) {
        // Fallback: treat description as a geocode query.
        final geo = await context.read<MapsService>().geocode(suggestion.description);
        if (geo != null) {
          widget.controller.text = geo.formattedAddress;
          widget.onPlaceSelected?.call(geo);
        }
      }
    } finally {
      _selecting = false;
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty && !_loading) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? MediaQuery.sizeOf(context).width - 32;

    _overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, (renderBox?.size.height ?? 56) + 4),
            child: Material(
              elevation: 8,
              color: AppTheme.asphaltLight,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _loading && _suggestions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppTheme.steel),
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, color: AppTheme.signalSoft),
                            title: Text(
                              s.mainText ?? s.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.mist, fontWeight: FontWeight.w600),
                            ),
                            subtitle: s.secondaryText == null
                                ? null
                                : Text(
                                    s.secondaryText!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.steel, fontSize: 12),
                                  ),
                            onTap: () => _pick(s),
                          );
                        },
                      ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search, color: AppTheme.steel),
        ),
        textInputAction: TextInputAction.next,
      ),
    );
  }
}
