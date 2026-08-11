import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/maps_service.dart';
import '../theme.dart';
import 'place_autocomplete_field.dart';

class StopCategory {
  const StopCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.kind,
    this.isSearch = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final String kind;
  final bool isSearch;
}

const kStopCategories = <StopCategory>[
  StopCategory(id: 'search', label: 'Search', icon: Icons.search, kind: 'other', isSearch: true),
  StopCategory(id: 'gas', label: 'Gas', icon: Icons.local_gas_station, kind: 'gas'),
  StopCategory(id: 'coffee', label: 'Coffee', icon: Icons.coffee, kind: 'coffee'),
  StopCategory(id: 'views', label: 'Views', icon: Icons.landscape, kind: 'viewpoint'),
  StopCategory(id: 'food', label: 'Food', icon: Icons.restaurant, kind: 'food'),
  StopCategory(id: 'parking', label: 'Parking', icon: Icons.local_parking, kind: 'parking'),
];

/// Search + category tabs for motorcycle-friendly stop suggestions.
class StopPickerSection extends StatefulWidget {
  const StopPickerSection({
    super.key,
    required this.enabled,
    required this.biasLat,
    required this.biasLng,
    required this.onStopPicked,
  });

  final bool enabled;
  final double? biasLat;
  final double? biasLng;
  final void Function(GeocodedPlace place, String kind) onStopPicked;

  @override
  State<StopPickerSection> createState() => _StopPickerSectionState();
}

class _StopPickerSectionState extends State<StopPickerSection> {
  final _search = TextEditingController();
  var _tabIndex = 0;
  bool _loading = false;
  String? _error;
  List<PlaceSuggestion> _suggestions = const [];

  StopCategory get _category => kStopCategories[_tabIndex];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StopPickerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) return;
    if (oldWidget.biasLat != widget.biasLat || oldWidget.biasLng != widget.biasLng) {
      if (!_category.isSearch) _loadCategory();
    }
  }

  Future<void> _selectTab(int index) async {
    setState(() {
      _tabIndex = index;
      _error = null;
      _suggestions = const [];
    });
    if (!kStopCategories[index].isSearch) {
      await _loadCategory();
    }
  }

  Future<void> _loadCategory() async {
    final lat = widget.biasLat;
    final lng = widget.biasLng;
    if (lat == null || lng == null) {
      setState(() => _error = 'Waiting for location or route…');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await context.read<MapsService>().nearby(
            lat: lat,
            lng: lng,
            kind: _category.kind,
          );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
        if (results.isEmpty) {
          _error = 'No ${_category.label.toLowerCase()} nearby — try Search.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load ${_category.label.toLowerCase()}: $e';
      });
    }
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    final maps = context.read<MapsService>();
    final place = await maps.placeDetails(suggestion.placeId) ??
        await maps.geocode(suggestion.description);
    if (place == null || !mounted) return;
    widget.onStopPicked(place, _category.kind == 'other' ? 'other' : _category.kind);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < kStopCategories.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                ChoiceChip(
                  selected: _tabIndex == i,
                  onSelected: !widget.enabled
                      ? null
                      : (_) => _selectTab(i),
                  avatar: Icon(kStopCategories[i].icon, size: 16),
                  label: Text(kStopCategories[i].label),
                  selectedColor: AppTheme.signal.withValues(alpha: 0.35),
                  labelStyle: TextStyle(
                    color: _tabIndex == i ? AppTheme.mist : AppTheme.steel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_category.isSearch)
          PlaceAutocompleteField(
            controller: _search,
            label: 'Search for a stop',
            enabled: widget.enabled,
            biasLat: widget.biasLat,
            biasLng: widget.biasLng,
            onPlaceSelected: (place) {
              widget.onStopPicked(place, 'other');
              _search.clear();
            },
          )
        else ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_error != null && !_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppTheme.steel, fontSize: 13)),
            ),
          if (!_loading)
            ..._suggestions.map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.asphaltLight,
                  child: Icon(_category.icon, color: AppTheme.signalSoft, size: 18),
                ),
                title: Text(
                  s.mainText ?? s.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: s.secondaryText == null
                    ? null
                    : Text(s.secondaryText!, style: const TextStyle(color: AppTheme.steel, fontSize: 12)),
                trailing: const Icon(Icons.add_circle_outline, color: AppTheme.signal),
                onTap: () => _pickSuggestion(s),
              ),
            ),
        ],
      ],
    );
  }
}
