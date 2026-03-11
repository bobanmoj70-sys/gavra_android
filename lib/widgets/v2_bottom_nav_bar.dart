import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../services/v2_theme_manager.dart';
import '../theme.dart';

/// Jedinstveni bottom navigation bar koji zamjenjuje
/// V2BottomNavBarLetnji, V2BottomNavBarZimski i V2BottomNavBarPraznici.
/// navType se prosleđuje iz V2RouteConfig (npr. 'letnji', 'zimski', 'praznici').
class V2BottomNavBar extends StatefulWidget {
  const V2BottomNavBar({
    super.key,
    required this.sviPolasci,
    required this.selectedGrad,
    required this.selectedVreme,
    required this.onPolazakChanged,
    required this.getPutnikCount,
    this.getKapacitet,
    this.isSlotLoading,
    this.bcVremena,
    this.vsVremena,
    this.selectedDan,
    this.showVozacBoja = false,
    this.getVozacColor,
  });

  // ignore: unused_field — zadržano za API paritet
  final List<String> sviPolasci;
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String grad, String vreme) onPolazakChanged;
  final int Function(String grad, String vreme) getPutnikCount;
  final int Function(String grad, String vreme)? getKapacitet;
  final bool Function(String grad, String vreme)? isSlotLoading;
  final List<String>? bcVremena;
  final List<String>? vsVremena;
  final String? selectedDan;
  final bool showVozacBoja;
  final Color? Function(String grad, String vreme)? getVozacColor;

  @override
  State<V2BottomNavBar> createState() => _V2BottomNavBarState();
}

class _V2BottomNavBarState extends State<V2BottomNavBar> {
  final ScrollController _bcScrollController = ScrollController();
  final ScrollController _vsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
    });
  }

  @override
  void didUpdateWidget(V2BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVreme != widget.selectedVreme || oldWidget.selectedGrad != widget.selectedGrad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  void _scrollToSelected() {
    const double itemWidth = 60.0;

    final bcVremena = widget.bcVremena ?? V2RouteConfig.getVremenaByNavType('BC');
    final vsVremena = widget.vsVremena ?? V2RouteConfig.getVremenaByNavType('VS');

    if (widget.selectedGrad == 'BC') {
      final index = bcVremena.indexOf(widget.selectedVreme);
      if (index != -1 && _bcScrollController.hasClients) {
        final targetOffset = (index * itemWidth) - (MediaQuery.of(context).size.width / 4);
        _bcScrollController.animateTo(
          targetOffset.clamp(0.0, _bcScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (widget.selectedGrad == 'VS') {
      final index = vsVremena.indexOf(widget.selectedVreme);
      if (index != -1 && _vsScrollController.hasClients) {
        final targetOffset = (index * itemWidth) - (MediaQuery.of(context).size.width / 4);
        _vsScrollController.animateTo(
          targetOffset.clamp(0.0, _vsScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _bcScrollController.dispose();
    _vsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentThemeId = V2ThemeManager().currentThemeId;
    final bcVremena = widget.bcVremena ?? V2RouteConfig.getVremenaByNavType('BC');
    final vsVremena = widget.vsVremena ?? V2RouteConfig.getVremenaByNavType('VS');

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: Theme.of(context).glassBorder,
          width: 1.5,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, -8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PolazakRow(
                  label: 'BC',
                  vremena: bcVremena,
                  selectedGrad: widget.selectedGrad,
                  selectedVreme: widget.selectedVreme,
                  grad: 'BC',
                  onPolazakChanged: widget.onPolazakChanged,
                  getPutnikCount: widget.getPutnikCount,
                  getKapacitet: widget.getKapacitet,
                  isSlotLoading: widget.isSlotLoading,
                  scrollController: _bcScrollController,
                  currentThemeId: currentThemeId,
                  selectedDan: widget.selectedDan,
                  showVozacBoja: widget.showVozacBoja,
                  getVozacColor: widget.getVozacColor,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PolazakRow(
                    label: 'VS',
                    grad: 'VS',
                    vremena: vsVremena,
                    selectedGrad: widget.selectedGrad,
                    selectedVreme: widget.selectedVreme,
                    onPolazakChanged: widget.onPolazakChanged,
                    getPutnikCount: widget.getPutnikCount,
                    getKapacitet: widget.getKapacitet,
                    isSlotLoading: widget.isSlotLoading,
                    scrollController: _vsScrollController,
                    currentThemeId: currentThemeId,
                    selectedDan: widget.selectedDan,
                    showVozacBoja: widget.showVozacBoja,
                    getVozacColor: widget.getVozacColor,
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

class _PolazakRow extends StatelessWidget {
  const _PolazakRow({
    required this.label,
    required this.vremena,
    required this.selectedGrad,
    required this.selectedVreme,
    required this.grad,
    required this.onPolazakChanged,
    required this.getPutnikCount,
    required this.currentThemeId,
    this.getKapacitet,
    this.isSlotLoading,
    this.scrollController,
    this.selectedDan,
    this.showVozacBoja = false,
    this.getVozacColor,
  });

  final String label;
  final List<String> vremena;
  final String selectedGrad;
  final String selectedVreme;
  final String grad;
  final void Function(String grad, String vreme) onPolazakChanged;
  final int Function(String grad, String vreme) getPutnikCount;
  final int Function(String grad, String vreme)? getKapacitet;
  final bool Function(String grad, String vreme)? isSlotLoading;
  final ScrollController? scrollController;
  final String currentThemeId;
  final String? selectedDan;
  final bool showVozacBoja;
  final Color? Function(String grad, String vreme)? getVozacColor;

  static Color _colorForTheme(String themeId) {
    switch (themeId) {
      case 'dark_steel_grey':
        return const Color(0xFF4A4A4A);
      case 'passionate_rose':
        return const Color(0xFFDC143C);
      case 'dark_pink':
        return const Color(0xFFE91E8C);
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _colorForTheme(currentThemeId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              child: Row(
                children: vremena.map((vreme) {
                  final bool selected = selectedGrad == grad && selectedVreme == vreme;
                  final vozacBorderColor = showVozacBoja ? getVozacColor?.call(grad, vreme) : null;
                  final hasVozac = vozacBorderColor != null;

                  return GestureDetector(
                    onTap: () => onPolazakChanged(grad, vreme),
                    child: Container(
                      width: 60.0,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? accentColor.withOpacity(0.3)
                            : hasVozac
                                ? vozacBorderColor.withOpacity(0.25)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasVozac
                              ? vozacBorderColor
                              : selected
                                  ? accentColor
                                  : Colors.grey[300]!,
                          width: hasVozac ? 3 : (selected ? 2.5 : 1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            vreme,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? accentColor : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (isSlotLoading?.call(grad, vreme) ?? false)
                            const SizedBox(
                              height: 12,
                              width: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Text(
                              () {
                                final count = getPutnikCount(grad, vreme);
                                final kapacitet = getKapacitet?.call(grad, vreme);
                                return kapacitet != null ? '$count ($kapacitet)' : '$count';
                              }(),
                              style: TextStyle(
                                fontSize: 12,
                                color: selected ? accentColor : Colors.white70,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
