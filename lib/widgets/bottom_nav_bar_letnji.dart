import 'package:flutter/material.dart';

import '../config/route_config.dart';
import '../services/theme_manager.dart';
import '../theme.dart';

class BottomNavBarLetnji extends StatefulWidget {
  const BottomNavBarLetnji({
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
    this.selectedDan, // 🆕
    this.showVozacBoja = false, // 🆕 Default je false (samo za Dodeli ekran)
  });
  final List<String> sviPolasci;
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String grad, String vreme) onPolazakChanged;
  final int Function(String grad, String vreme) getPutnikCount;
  final int Function(String grad, String vreme)? getKapacitet;
  final bool Function(String grad, String vreme)? isSlotLoading;
  final List<String>? bcVremena;
  final List<String>? vsVremena;
  final String? selectedDan; // 🆕
  final bool showVozacBoja; // 🆕

  @override
  State<BottomNavBarLetnji> createState() => _BottomNavBarLetnjiState();
}

class _BottomNavBarLetnjiState extends State<BottomNavBarLetnji> {
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
  void didUpdateWidget(BottomNavBarLetnji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVreme != widget.selectedVreme || oldWidget.selectedGrad != widget.selectedGrad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  void _scrollToSelected() {
    const double itemWidth = 60.0; // width + margin

    // Koristi prosleđena vremena ili fallback na RouteConfig
    final bcVremena = widget.bcVremena ?? RouteConfig.bcVremenaLetnji;
    final vsVremena = widget.vsVremena ?? RouteConfig.vsVremenaLetnji;

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
    final currentThemeId = ThemeManager().currentThemeId;
    // Koristi prosleđena vremena ili fallback na RouteConfig
    final bcVremena = widget.bcVremena ?? RouteConfig.bcVremenaLetnji;
    final vsVremena = widget.vsVremena ?? RouteConfig.vsVremenaLetnji;

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
                // top-right total removed (per user request)
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
                    selectedDan: widget.selectedDan,
                    showVozacBoja: widget.showVozacBoja,
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
    this.selectedDan, // 🆕
    this.showVozacBoja = false,
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
  final String? selectedDan; // 🆕
  final bool showVozacBoja;

  /// 🆕 Dobij boju bordera za vreme - uvek null (vreme_vozac tabela uklonjena)
  Color? _getVozacBorderColor(String vreme) => null;

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
                  final bool selected = selectedGrad == grad && selectedVreme == vreme;
                  // 🆕 Proveri da li je dodeljen vozač za ovo vreme - samo ako showVozacBoja je true
                  final vozacBorderColor = showVozacBoja ? _getVozacBorderColor(vreme) : null;
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
                            ? (currentThemeId == 'dark_steel_grey'
                                ? const Color(0xFF4A4A4A).withOpacity(0.3)
                                : currentThemeId == 'passionate_rose'
                                    ? const Color(0xFFDC143C).withOpacity(0.3)
                                    : currentThemeId == 'dark_pink'
                                        ? const Color(0xFFE91E8C).withOpacity(0.3)
                                        : Colors.blueAccent.withOpacity(0.3))
                            : hasVozac
                                ? vozacBorderColor.withOpacity(0.25)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          // 🆕 Ako ima dodeljen vozač, koristi njegovu boju za border
                          color: hasVozac
                              ? vozacBorderColor
                              : selected
                                  ? (currentThemeId == 'dark_steel_grey'
                                      ? const Color(0xFF4A4A4A)
                                      : currentThemeId == 'passionate_rose'
                                          ? const Color(0xFFDC143C)
                                          : currentThemeId == 'dark_pink'
                                              ? const Color(0xFFE91E8C)
                                              : Colors.blue)
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
                              color: selected
                                  ? (currentThemeId == 'dark_steel_grey'
                                      ? const Color(0xFF4A4A4A) // Crna tema
                                      : currentThemeId == 'passionate_rose'
                                          ? const Color(0xFFDC143C) // Crvena tema
                                          : currentThemeId == 'dark_pink'
                                              ? const Color(0xFFE91E8C) // Dark Pink tema
                                              : Colors.blue) // Plava tema
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (ctx) {
                              final loading = isSlotLoading?.call(grad, vreme) ?? false;
                              if (loading) {
                                return const SizedBox(
                                  height: 12,
                                  width: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                );
                              }
                              final count = getPutnikCount(grad, vreme);
                              final kapacitet = getKapacitet?.call(grad, vreme);
                              final displayText = kapacitet != null ? '$count ($kapacitet)' : '$count';
                              return Text(
                                displayText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected
                                      ? (currentThemeId == 'dark_steel_grey'
                                          ? const Color(0xFF4A4A4A) // Crna tema
                                          : currentThemeId == 'passionate_rose'
                                              ? const Color(0xFFDC143C) // Crvena tema
                                              : currentThemeId == 'dark_pink'
                                                  ? const Color(0xFFE91E8C) // Dark Pink tema
                                                  : Colors.blue) // Plava tema
                                      : Colors.white70,
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
