import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/maps_service.dart';
import '../theme.dart';

/// Google Places-backed location field with debounced suggestions.
class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.onPlaceSelected,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<GeocodedPlace>? onPlaceSelected;
  final bool enabled;

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
      // Delay so a tap on a suggestion can register first.
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!_focus.hasFocus) _removeOverlay();
      });
    }
  }

  void _onTextChanged() {
    if (_selecting) return;
    _scheduleSearch(widget.controller.text);
  }

  void _scheduleSearch(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
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
    final id = ++_requestId;
    try {
      final results = await context.read<MapsService>().autocomplete(q);
      if (!mounted || id != _requestId) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      if (_focus.hasFocus) {
        _showOverlay();
      }
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
        onTap: () => _scheduleSearch(widget.controller.text),
      ),
    );
  }
}
