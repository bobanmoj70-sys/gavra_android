import 'package:flutter/material.dart';

import '../services/v3_theme_manager.dart';
import '../theme.dart';

class V3BottomNavBarZimski extends StatefulWidget {
  const V3BottomNavBarZimski({
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
    this.showVozacBoja = false,
    this.getVozacColor,
  });
  final List<String> sviPolasci;
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String grad, String vreme) onPolazakChanged;
  final int Function(String grad, String vreme) getPutnikCount;
  final int? Function(String grad, String vreme)? getKapacitet;
  final bool Function(String grad, String vreme)? isSlotLoading;
  final List<String>? bcVremena;
  final List<String>? vsVremena;
  final bool showVozacBoja;
  final Color? Function(String grad, String vreme)? getVozacColor;

  @override
  State<V3BottomNavBarZimski> createState() => _BottomNavBarZimskiState();
}

class _BottomNavBarZimskiState extends State<V3BottomNavBarZimski> {
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
  void didUpdateWidget(V3BottomNavBarZimski oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVreme != widget.selectedVreme ||
        oldWidget.selectedGrad != widget.selectedGrad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  void _scrollToSelected() {
    const double itemWidth = 60.0; // width + margin

    // Koristi prosleđena vremena ili fallback na Zimski raspored
    final bcVremena = widget.bcVremena ?? [];
    final vsVremena = widget.vsVremena ?? [];

    if (widget.selectedGrad == 'BC') {
      final index = bcVremena.indexOf(widget.selectedVreme);
      if (index != -1 && _bcScrollController.hasClients) {
        final targetOffset =
            (index * itemWidth) - (MediaQuery.of(context).size.width / 4);
        _bcScrollController.animateTo(
          targetOffset.clamp(0.0, _bcScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (widget.selectedGrad == 'VS') {
      final index = vsVremena.indexOf(widget.selectedVreme);
      if (index != -1 && _vsScrollController.hasClients) {
        final targetOffset =
            (index * itemWidth) - (MediaQuery.of(context).size.width / 4);
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
    // Koristi prosleđena vremena ili fallback na Zimski raspored
    final bcVremena = widget.bcVremena ?? [];
    final vsVremena = widget.vsVremena ?? [];
    final currentThemeId = V3ThemeManager().currentThemeId;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: Theme.of(context).glassBorder,
          width: 0.8,
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
                // top-right total removed (per user request)
                // BC Red
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PolazakRow(
                    label: 'BC',
                    grad: 'BC',
                    vremena: bcVremena,
                    selectedGrad: widget.selectedGrad,
                    selectedVreme: widget.selectedVreme,
                    onPolazakChanged: widget.onPolazakChanged,
                    getPutnikCount: widget.getPutnikCount,
                    getKapacitet: widget.getKapacitet,
                    isSlotLoading: widget.isSlotLoading,
                    scrollController: _bcScrollController,
                    currentThemeId: currentThemeId,
                    showVozacBoja: widget.showVozacBoja,
                    getVozacColor: widget.getVozacColor,
                  ),
                ),
                const Divider(height: 1),
                // VS Red
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
  final int? Function(String grad, String vreme)? getKapacitet;
  final bool Function(String grad, String vreme)? isSlotLoading;
  final ScrollController? scrollController;
  final String currentThemeId;
  final bool showVozacBoja;
  final Color? Function(String grad, String vreme)? getVozacColor;

  Color _selectedFillColor() {
    if (currentThemeId == 'dark_steel_grey')
      return const Color(0xFF4A4A4A).withOpacity(0.22);
    if (currentThemeId == 'passionate_rose')
      return const Color(0xFFDC143C).withOpacity(0.22);
    if (currentThemeId == 'dark_pink')
      return const Color(0xFFE91E8C).withOpacity(0.22);
    return Colors.blueAccent.withOpacity(0.22);
  }

  Color _selectedStrokeAndTextColor() {
    if (currentThemeId == 'dark_steel_grey') return const Color(0xFF4A4A4A);
    if (currentThemeId == 'passionate_rose') return const Color(0xFFDC143C);
    if (currentThemeId == 'dark_pink') return const Color(0xFFE91E8C);
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              child: Row(
                children: vremena.map((vreme) {
                  final bool selected =
                      selectedGrad == grad && selectedVreme == vreme;
                  final selectedFillColor = _selectedFillColor();
                  final selectedPrimaryColor = _selectedStrokeAndTextColor();
                  // Boja vozaca za termin (iz raspored cache-a)
                  final vozacBorderColor =
                      showVozacBoja ? getVozacColor?.call(grad, vreme) : null;
                  final hasVozac = vozacBorderColor != null;

                  return GestureDetector(
                    onTap: () => onPolazakChanged(grad, vreme),
                    child: Container(
                      width: 60.0,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? selectedFillColor
                            : hasVozac
                                ? vozacBorderColor.withOpacity(0.16)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasVozac
                              ? vozacBorderColor.withOpacity(0.75)
                              : selected
                                  ? selectedPrimaryColor.withOpacity(0.8)
                                  : Colors.grey[300]!,
                          width: hasVozac ? 1.5 : (selected ? 1.2 : 0.6),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            vreme,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected
                                  ? selectedPrimaryColor
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (ctx) {
                              final loading =
                                  isSlotLoading?.call(grad, vreme) ?? false;
                              if (loading) {
                                return const SizedBox(
                                  height: 12,
                                  width: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                );
                              }
                              final count = getPutnikCount(grad, vreme);
                              final kapacitet = getKapacitet?.call(grad, vreme);
                              final displayText = kapacitet != null
                                  ? '$count ($kapacitet)'
                                  : '$count';
                              final slobodna = kapacitet != null
                                  ? (kapacitet - count).clamp(0, kapacitet)
                                  : null;
                              final textColor = selected
                                  ? selectedPrimaryColor
                                  : slobodna == null
                                      ? Colors.white70
                                      : slobodna == 0
                                          ? Colors.red
                                          : slobodna <= 2
                                              ? Colors.orange
                                              : Colors.white70;
                              return Text(
                                displayText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
