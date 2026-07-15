import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/route_observer.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/ltr_fragment.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_bottom_nav.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_messaging_badge_scope.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../../messaging/data/team_messaging_service.dart';
import '../../messaging/domain/team_messaging_models.dart';
import '../../messaging/presentation/message_team_leader_dialog.dart';
import '../data/team_service.dart';
import '../data/team_shopping_service.dart';
import '../data/team_turn_service.dart';
import '../domain/team_models.dart';
import '../domain/team_shopping_models.dart';
import '../domain/team_turn_models.dart';

// Stitch team_detail accents (screen-local, not shared tokens):
// surface-container-highest border and primary-fixed avatar fill.
const _warmBorder = Color(0xFFF2E0CC);
const _paleGreen = Color(0xFFB1F1C8);

String _formatShoppingPrice(double price) {
  final isWhole = price == price.roundToDouble();
  final value = isWhole ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  return '$value MRU';
}

String _formatShoppingMoney(double amount) => _formatShoppingPrice(amount);

// Hassaniya labels for structured shopping quantity units. mru_value means
// "buy this many MRU worth of the item" (a requested amount), not a
// currency total — kept visually separate from price via the السعر/الكمية
// prefixes below so the two never read as the same number.
const _kShoppingQuantityUnits = <MapEntry<String, String>>[
  MapEntry('kg', 'كغ'),
  MapEntry('packet', 'بكط'),
  MapEntry('can', 'بطة'),
  MapEntry('piece', 'وحدة'),
  MapEntry('mru_value', 'MRU'),
  MapEntry('other', 'أخرى'),
];

String _quantityUnitLabel(String unit) => _kShoppingQuantityUnits
    .firstWhere((e) => e.key == unit, orElse: () => MapEntry(unit, unit))
    .value;

String _formatShoppingQuantityValue(double value) {
  final isWhole = value == value.roundToDouble();
  return isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

class TeamDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  final TeamService? teamService;
  final TeamTurnService? turnService;
  final TeamShoppingService? shoppingService;
  final TeamMessagingService? messagingService;
  const TeamDetailScreen({
    super.key,
    required this.authService,
    required this.teamId,
    this.teamService,
    this.turnService,
    this.shoppingService,
    this.messagingService,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> with RouteAware {
  late final TeamService _svc;
  late final TeamTurnService _turnSvc;
  late final TeamShoppingService _shoppingSvc;
  late final TeamMessagingService _messagingSvc;
  TeamDetail? _detail;
  TeamTurnState? _turnState;
  TeamShoppingOverview? _shoppingOverview;
  bool _loading = true;
  bool _refreshing = false;
  bool _turnLoading = false;
  bool _shoppingLoading = false;
  bool _routeSubscribed = false;
  String? _reviewingStatus;
  String? _error;
  String? _shoppingError;
  final Set<String> _busyMembers = {};
  final Set<String> _markingItems = {};
  final Set<String> _removingItems = {};

  @override
  void initState() {
    super.initState();
    _svc = widget.teamService ?? TeamService(widget.authService);
    _turnSvc = widget.turnService ?? TeamTurnService(widget.authService);
    _shoppingSvc = widget.shoppingService ?? TeamShoppingService();
    _messagingSvc =
        widget.messagingService ?? TeamMessagingService(widget.authService);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    _load();
  }

  @override
  void dispose() {
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // Cold start (no _detail yet) shows the full-page spinner/error via
  // _loading/_error. Once data exists, later calls (didPopNext,
  // pull-to-refresh) run as a silent background refresh via _refreshing
  // instead, so returning to this screen never tears down and re-animates
  // content the user can already see.
  Future<void> _load() async {
    final isInitialLoad = _detail == null;
    setState(() {
      if (isInitialLoad) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      _detail = await _svc.getTeamDetail(widget.teamId);
    } catch (e) {
      if (mounted) {
        if (isInitialLoad) {
          setState(() {
            _error = userErrorText(e);
            _loading = false;
          });
        } else {
          setState(() => _refreshing = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
        }
      }
      return;
    }
    try {
      _turnState = await _turnSvc.getTurnState(widget.teamId);
    } catch (_) {} // turn state is non-fatal; card shows empty
    await _loadShopping();
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _refreshTurnState() async {
    try {
      final turnState = await _turnSvc.getTurnState(widget.teamId);
      if (mounted) setState(() => _turnState = turnState);
    } catch (_) {}
  }

  Future<void> _loadShopping() async {
    final token = widget.authService.currentToken;
    if (token == null) return;
    // Same cold-start-vs-refresh split as _load(): only clear a prior error
    // (and let _shoppingCard show its spinner-only state) when there's no
    // list on screen yet; a refresh of an already-visible list keeps
    // showing the old items until fresh data arrives.
    final isInitialShoppingLoad = _shoppingOverview == null;
    setState(() {
      _shoppingLoading = true;
      if (isInitialShoppingLoad) _shoppingError = null;
    });
    try {
      final overview = await _shoppingSvc.getShoppingList(
        sessionToken: token,
        teamId: widget.teamId,
      );
      if (mounted) {
        setState(() {
          _shoppingOverview = overview;
          _shoppingError = null;
          _shoppingLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (isInitialShoppingLoad) {
          setState(() {
            _shoppingError = userErrorText(e);
            _shoppingLoading = false;
          });
        } else {
          setState(() => _shoppingLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
        }
      }
    }
  }

  List<Widget> _shoppingCard() {
    final o = _shoppingOverview;
    Widget shell(List<Widget> children) => ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: double.infinity,
            child: ZadSectionHeader('تسوق اليوم'),
          ),
          ...children,
        ],
      ),
    );

    if (_shoppingLoading && o == null) {
      return [
        shell(const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(ZadTokens.s4),
              child: CircularProgressIndicator(),
            ),
          ),
        ]),
      ];
    }
    if (_shoppingError != null && o == null) {
      return [
        shell([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZadTokens.s2),
            child: ZadInfoBanner(_shoppingError!, kind: ZadBannerKind.warning),
          ),
        ]),
      ];
    }
    if (o == null) {
      return [
        shell(const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: ZadTokens.s2),
            child: Text(
              'لم تتوفر قائمة المشتريات حالياً',
              style: TextStyle(color: ZadTokens.textMuted),
            ),
          ),
        ]),
      ];
    }

    final submitHint = _shoppingSubmitDisabledReason(o);
    final canMark = o.canEditMarks;
    return [
      shell([
        if (canMark)
          const Padding(
            padding: EdgeInsets.only(bottom: ZadTokens.s2),
            child: ZadInfoBanner('أنت مسؤول تسوق اليوم'),
          ),
        if (o.report.completionBlockingReason != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ZadTokens.s2),
            child: ZadInfoBanner(
              o.report.completionBlockingReason!,
              kind: ZadBannerKind.warning,
            ),
          ),
        _shoppingReportStatus(o),
        _shoppingFinancialSummary(o),
        if (o.canEditList)
          Padding(
            padding: const EdgeInsets.only(bottom: ZadTokens.s2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'تعديل القائمة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: ZadTokens.goldDark,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openShoppingItemSheet(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة عنصر'),
                ),
              ],
            ),
          ),
        if (o.responsibleMember != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ZadTokens.s3),
            child: Text(
              'المسؤول اليوم: ${o.responsibleMember!.displayName}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        if (o.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: ZadTokens.s4),
            child: Center(
              child: Text(
                'لم تتم إضافة عناصر بعد',
                style: TextStyle(color: ZadTokens.textMuted),
              ),
            ),
          )
        else
          ...o.items.map((item) => _shoppingItemRow(item, canMark)),
        if (o.canSubmit) ...[
          const SizedBox(height: ZadTokens.s3),
          FilledButton(
            onPressed: submitHint == null ? _submitShoppingReport : null,
            child: const Text('إرسال القائمة للقائد'),
          ),
          if (submitHint != null)
            Padding(
              padding: const EdgeInsets.only(top: ZadTokens.s1),
              child: Text(
                submitHint,
                style: const TextStyle(
                  fontSize: 12,
                  color: ZadTokens.textMuted,
                ),
              ),
            ),
        ],
        if (o.canReview && o.reportIsPending) ...[
          const SizedBox(height: ZadTokens.s3),
          Wrap(
            spacing: ZadTokens.s2,
            runSpacing: ZadTokens.s1,
            children: [
              FilledButton(
                onPressed: _reviewingStatus != null
                    ? null
                    : () => _reviewShoppingReport('accepted'),
                child: _reviewingStatus == 'accepted'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('قبول'),
              ),
              OutlinedButton(
                onPressed: _reviewingStatus != null
                    ? null
                    : () => _reviewShoppingReport('rejected'),
                child: _reviewingStatus == 'rejected'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('رفض'),
              ),
            ],
          ),
        ],
      ]),
    ];
  }

  Widget _shoppingReportStatus(TeamShoppingOverview o) {
    final label = o.report.submittedAt == null
        ? 'لم يتم الإرسال بعد'
        : o.reportAccepted
        ? 'تم القبول'
        : o.reportRejected
        ? 'تم الرفض'
        : 'في انتظار المراجعة';
    return Padding(
      padding: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'حالة التقرير:',
            style: TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (o.report.leaderNote != null &&
              o.report.leaderNote!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ملاحظة القائد: ${o.report.leaderNote}',
                style: const TextStyle(
                  fontSize: 12,
                  color: ZadTokens.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shoppingFinancialSummary(TeamShoppingOverview o) {
    final report = o.report;
    if (!report.isAccepted) return const SizedBox.shrink();

    final isResponsible =
        widget.authService.profile?.id != null &&
        o.responsibleMember?.id == widget.authService.profile!.id;

    if (!report.hasFinancialSummary) {
      return const Padding(
        padding: EdgeInsets.only(bottom: ZadTokens.s2),
        child: _ShoppingFinancialBox(
          status: 'تقرير قديم بدون حسبة مالية',
          children: [
            Text(
              'لم تُطبَّق الحسبة المالية على هذا التقرير القديم',
              style: TextStyle(fontSize: 12, color: ZadTokens.textMuted),
            ),
          ],
        ),
      );
    }

    final expected = report.expectedTotal!;
    final actual = report.actualTotal!;
    final deducted = report.deductionAmount ?? actual;
    final applied = report.financialApplied;
    final status = applied ? 'تم تطبيق الخصم' : 'لم يتم تطبيق الخصم بعد';
    final responsibleMessage = isResponsible
        ? (deducted == 0
              ? 'لم يتم خصم أي مبلغ من ميزانيتك'
              : 'تم خصم ${ltrFragment(_formatShoppingMoney(deducted))} من ميزانيتك')
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: _ShoppingFinancialBox(
        status: status,
        children: [
          _ShoppingFinancialRow(
            label: 'التكلفة المتوقعة',
            value: ltrFragment(_formatShoppingMoney(expected)),
          ),
          _ShoppingFinancialRow(
            label: 'التكلفة الفعلية',
            value: ltrFragment(_formatShoppingMoney(actual)),
          ),
          _ShoppingFinancialRow(
            label: 'المخصوم من الميزانية',
            value: ltrFragment(_formatShoppingMoney(deducted)),
          ),
          if (responsibleMessage != null) ...[
            const SizedBox(height: ZadTokens.s1),
            Text(
              'تم قبول التقرير',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              responsibleMessage,
              style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
            ),
          ] else if (deducted == 0) ...[
            const SizedBox(height: ZadTokens.s1),
            const Text(
              'لم يتم خصم أي مبلغ من الميزانية',
              style: TextStyle(fontSize: 12, color: ZadTokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shoppingItemRow(TeamShoppingItem item, bool canMark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: ZadTokens.s1),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warmBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZadTokens.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canMark)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: ZadTokens.s2 - 2,
                    ),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: item.isBought,
                        onChanged: _markingItems.contains(item.id)
                            ? null
                            : (v) => _markItem(item.id, v ?? false),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      decoration: item.isBought
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.isBought ? ZadTokens.textMuted : null,
                    ),
                  ),
                ),
                if (_markingItems.contains(item.id))
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_shoppingOverview?.canEditList ?? false) ...[
                  IconButton(
                    tooltip: 'تعديل',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: _removingItems.contains(item.id)
                        ? null
                        : () => _openShoppingItemSheet(existing: item),
                  ),
                  IconButton(
                    tooltip: 'إزالة',
                    visualDensity: VisualDensity.compact,
                    icon: _removingItems.contains(item.id)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: ZadTokens.danger,
                          ),
                    onPressed: _removingItems.contains(item.id)
                        ? null
                        : () => _removeShoppingItem(item),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.isRequired) const _Badge('أساسي', gold: true),
                if (!item.isRequired) const _Badge('اختياري'),
                _Badge(_shoppingItemStatusLabel(item)),
                if (item.quantityValue != null && item.quantityUnit != null)
                  Text(
                    'الكمية: ${ltrFragment('${_formatShoppingQuantityValue(item.quantityValue!)} ${_quantityUnitLabel(item.quantityUnit!)}')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZadTokens.textMuted,
                    ),
                  )
                else if (item.quantityNote != null)
                  Text(
                    item.quantityNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZadTokens.textMuted,
                    ),
                  ),
                if (item.price != null)
                  Text(
                    'السعر: ${ltrFragment(_formatShoppingPrice(item.price!))}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZadTokens.textMuted,
                    ),
                  ),
              ],
            ),
            if (item.isNotBought && item.reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'السبب: ${item.reason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZadTokens.textMuted,
                  ),
                ),
              ),
            if (canMark) ...[
              const SizedBox(height: ZadTokens.s1),
              Wrap(
                spacing: ZadTokens.s2,
                runSpacing: ZadTokens.s1,
                children: [
                  OutlinedButton(
                    onPressed: _markingItems.contains(item.id)
                        ? null
                        : () => _markItem(item.id, true),
                    child: const Text('اشتريت'),
                  ),
                  OutlinedButton(
                    onPressed: _markingItems.contains(item.id)
                        ? null
                        : () => _askNotBoughtReason(item),
                    child: const Text('لم أشترِ'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );

  String _shoppingItemStatusLabel(TeamShoppingItem item) {
    if (item.isBought) return 'تم الشراء';
    if (item.isNotBought) return 'لم يتم الشراء';
    return 'لم يحدد بعد';
  }

  String? _shoppingSubmitDisabledReason(TeamShoppingOverview o) {
    for (final item in o.items) {
      if (item.isRequired && !item.isBought) {
        return 'يجب شراء كل العناصر الأساسية قبل الإرسال';
      }
      if (!item.isRequired && item.isUntouched) {
        return 'يجب تحديد حالة كل العناصر الاختيارية';
      }
      if (item.isNotBought &&
          (item.reason == null || item.reason!.trim().isEmpty)) {
        return 'اكتب سبب كل عنصر لم يتم شراؤه';
      }
    }
    return null;
  }

  Future<void> _markItem(String itemId, bool bought, {String? reason}) async {
    final token = widget.authService.currentToken;
    if (token == null) return;
    setState(() => _markingItems.add(itemId));
    try {
      final overview = await _shoppingSvc.markItemStatus(
        sessionToken: token,
        teamId: widget.teamId,
        itemId: itemId,
        bought: bought,
        reason: reason,
      );
      if (mounted) {
        setState(() {
          _shoppingOverview = overview;
          _markingItems.remove(itemId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _markingItems.remove(itemId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _askNotBoughtReason(TeamShoppingItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ShoppingReasonDialog(initialReason: item.reason),
    );
    if (reason == null) return;
    await _markItem(item.id, false, reason: reason);
  }

  Future<void> _submitShoppingReport() async {
    final token = widget.authService.currentToken;
    if (token == null) return;
    try {
      final overview = await _shoppingSvc.submitShoppingReport(
        sessionToken: token,
        teamId: widget.teamId,
      );
      if (mounted) {
        setState(() => _shoppingOverview = overview);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال القائمة للقائد')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _reviewShoppingReport(String status) async {
    if (_reviewingStatus != null) return;
    String? note;
    if (status == 'rejected') {
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => const _ShoppingReasonDialog(
          title: 'سبب الرفض',
          label: 'سبب الرفض',
          maxLength: 300,
        ),
      );
      if (note == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => const _ConfirmRejectReportDialog(),
      );
      if (confirmed != true || !mounted) return;
    }
    final token = widget.authService.currentToken;
    if (token == null) return;
    setState(() => _reviewingStatus = status);
    try {
      final overview = await _shoppingSvc.reviewShoppingReport(
        sessionToken: token,
        teamId: widget.teamId,
        status: status,
        date: _shoppingOverview?.turnDate,
        note: note,
      );
      if (mounted) {
        setState(() {
          _shoppingOverview = overview;
          _reviewingStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'accepted' ? 'تم قبول التقرير' : 'تم رفض التقرير',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _reviewingStatus = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _openShoppingItemSheet({TeamShoppingItem? existing}) async {
    final token = widget.authService.currentToken;
    if (token == null) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ShoppingItemSheet(
          existing: existing,
          onSubmit:
              (
                name,
                quantityNote,
                isRequired,
                price,
                quantityValue,
                quantityUnit,
              ) async {
                final overview = existing == null
                    ? await _shoppingSvc.addItem(
                        sessionToken: token,
                        teamId: widget.teamId,
                        name: name,
                        quantityNote: quantityNote,
                        isRequired: isRequired,
                        price: price,
                        quantityValue: quantityValue,
                        quantityUnit: quantityUnit,
                      )
                    : await _shoppingSvc.updateItem(
                        sessionToken: token,
                        teamId: widget.teamId,
                        itemId: existing.id,
                        name: name,
                        quantityNote: quantityNote,
                        isRequired: isRequired,
                        price: price,
                        quantityValue: quantityValue,
                        quantityUnit: quantityUnit,
                      );
                if (mounted) setState(() => _shoppingOverview = overview);
              },
        ),
      ),
    );
  }

  Future<void> _removeShoppingItem(TeamShoppingItem item) async {
    final token = widget.authService.currentToken;
    if (token == null) return;
    final ok = await zadConfirm(
      context,
      title: 'إزالة العنصر',
      body: 'سيتم إزالة "${item.name}" من قائمة المشتريات.',
      confirmLabel: 'إزالة',
    );
    if (!ok) return;
    setState(() => _removingItems.add(item.id));
    try {
      final overview = await _shoppingSvc.deactivateItem(
        sessionToken: token,
        teamId: widget.teamId,
        itemId: item.id,
      );
      if (mounted) {
        setState(() {
          _shoppingOverview = overview;
          _removingItems.remove(item.id);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _removingItems.remove(item.id));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  void _setMemberBusy(String memberId, bool busy) {
    setState(() {
      if (busy) {
        _busyMembers.add(memberId);
      } else {
        _busyMembers.remove(memberId);
      }
    });
  }

  Future<void> _applyMemberUpdate(
    TeamMember member,
    Future<TeamDetail> Function() action,
  ) async {
    _setMemberBusy(member.memberId, true);
    try {
      final detail = await action();
      if (mounted) {
        setState(() {
          _detail = detail;
          _busyMembers.remove(member.memberId);
        });
        await _refreshTurnState();
      }
    } catch (e) {
      if (mounted) {
        _setMemberBusy(member.memberId, false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _deactivate(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'تعطيل العضو',
      body:
          'سيبقى العضو ظاهراً في الفريق كغير نشط، ولن يدخل في الأدوار القادمة.',
      confirmLabel: 'تعطيل',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.deactivateTeamMember(
        teamId: widget.teamId,
        memberId: m.memberId,
      ),
    );
  }

  Future<void> _remove(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'إزالة العضو',
      body: 'سيختفي العضو من قائمة الفريق، مع بقاء السجل القديم محفوظاً.',
      confirmLabel: 'إزالة',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.removeTeamMember(teamId: widget.teamId, memberId: m.memberId),
    );
  }

  Future<void> _reactivate(TeamMember m) async {
    final ok = await zadConfirm(
      context,
      title: 'تفعيل العضو',
      body: 'سيعود العضو إلى الأدوار القادمة في الفريق.',
      confirmLabel: 'تفعيل',
    );
    if (!ok) return;
    await _applyMemberUpdate(
      m,
      () => _svc.reactivateTeamMember(
        teamId: widget.teamId,
        memberId: m.memberId,
      ),
    );
  }

  Future<void> _openMessageLeaderComposer() async {
    final result = await showDialog<SentTeamMessage>(
      context: context,
      builder: (_) => MessageTeamLeaderDialog(
        service: _messagingSvc,
        teamId: widget.teamId,
      ),
    );
    if (result == null || !mounted) return;
    ZadMessagingBadgeScope.maybeOf(context)?.refresh();
    context.push(
      '/messages/conversation/${result.conversation.id}',
      extra: {
        'teamId': result.conversation.teamId,
        'teamName': _detail?.team.name,
        'currentUserRole': 'member',
      },
    );
  }

  Future<void> _startTurn() async {
    setState(() => _turnLoading = true);
    try {
      final ts = await _turnSvc.ensureTodayTurn(widget.teamId);
      if (mounted) {
        setState(() {
          _turnState = ts;
          _turnLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _turnLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _completeTurn(String turnId) async {
    setState(() => _turnLoading = true);
    try {
      final ts = await _turnSvc.completeTurn(turnId);
      if (mounted) {
        setState(() {
          _turnState = ts;
          _turnLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _turnLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  Future<void> _skipMissedTurn(String turnId, String? reason) async {
    setState(() => _turnLoading = true);
    try {
      final ts = await _turnSvc.skipMissedTurn(
        widget.teamId,
        turnId,
        reason: reason,
      );
      if (mounted) {
        setState(() {
          _turnState = ts;
          _turnLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تخطّي الدور السابق')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _turnLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only a true cold start (no _detail yet) gets the full-page
    // spinner/error takeover. Once data exists, _load() runs as a silent
    // background refresh (_refreshing) and this branch is skipped entirely,
    // so existing content, scroll position, and entry animations survive.
    if (_loading && _detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الفريق')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZadTokens.s4),
            child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          ),
        ),
      );
    }
    final d = _detail!;
    final team = d.team;
    return Scaffold(
      appBar: AppBar(
        title: Text(team.name),
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      // Stitch team_detail keeps the bottom nav with الفرق active; the FAB
      // floats above it automatically. Back arrow stays (detail page).
      bottomNavigationBar: const ZadBottomNav(current: ZadTab.teams),
      // Gold add-member FAB (Stitch team_detail); same route push as before.
      floatingActionButton: d.canEdit
          ? FloatingActionButton(
              backgroundColor: ZadTokens.gold,
              foregroundColor: ZadTokens.primaryDark,
              tooltip: 'إضافة عضو',
              onPressed: () =>
                  context.push('/teams/${widget.teamId}/add-member'),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side =
                ((constraints.maxWidth - ZadTokens.contentMaxWidth) / 2).clamp(
                  ZadTokens.s4,
                  double.infinity,
                );
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                // Extra bottom inset keeps the last row clear of the FAB.
                padding: EdgeInsets.fromLTRB(side, ZadTokens.s4, side, 96),
                children: [
                  // Green hero card (Stitch team_detail): type/privacy pills
                  // + name at start, leader block at end, stats footer, and
                  // a faded decorative mark — same data, new dress.
                  ZadAnimatedEntry(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: ZadTokens.heroGradient,
                        borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
                        boxShadow: ZadTokens.cardShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
                        child: Stack(
                          children: [
                            PositionedDirectional(
                              top: -16,
                              end: -16,
                              child: Icon(
                                Icons.mosque_outlined,
                                size: 110,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(ZadTokens.s4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: ZadTokens.s2,
                                              runSpacing: ZadTokens.s1,
                                              children: [
                                                _HeroBadge(
                                                  teamTypeLabels[team
                                                          .teamType] ??
                                                      team.teamType,
                                                  gold: true,
                                                ),
                                                _HeroBadge(
                                                  team.isPublic ? 'عام' : 'خاص',
                                                ),
                                              ],
                                            ),
                                            const SizedBox(
                                              height: ZadTokens.s2,
                                            ),
                                            Text(
                                              team.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: ZadTokens.s3),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'القائد',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              team.leaderName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: ZadTokens.s4),
                                  const Divider(
                                    height: 1,
                                    color: Colors.white24,
                                  ),
                                  const SizedBox(height: ZadTokens.s3),
                                  Wrap(
                                    spacing: ZadTokens.s4,
                                    runSpacing: ZadTokens.s1,
                                    children: [
                                      _HeroStat(
                                        Icons.groups_outlined,
                                        '${ltrFragment('${team.memberCount}')} عضو '
                                        '(نشط ${ltrFragment('${team.activeMemberCount}')} · '
                                        'غير نشط ${ltrFragment('${team.inactiveMemberCount}')})',
                                      ),
                                      _HeroStat(
                                        Icons.verified_user_outlined,
                                        teamStatusLabels[team.status] ??
                                            team.status,
                                      ),
                                    ],
                                  ),
                                  if (team.note != null) ...[
                                    const SizedBox(height: ZadTokens.s2),
                                    Text(
                                      'ملاحظة: ${team.note!}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
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
                  ),
                  const SizedBox(height: ZadTokens.s4),
                  // Add-member moved to the gold FAB (Stitch); edit stays.
                  if (d.canEdit)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('تعديل الفريق'),
                            onPressed: () => context.push(
                              '/teams/${widget.teamId}/edit',
                              extra: team,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZadTokens.s2),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.campaign_outlined),
                            label: const Text('الإعلانات'),
                            onPressed: () => context.push(
                              '/teams/${widget.teamId}/announcements',
                              extra: {'teamName': team.name, 'isLeader': true},
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (d.isMember) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('الإعلانات'),
                      onPressed: () => context.push(
                        '/teams/${widget.teamId}/announcements',
                        extra: {'teamName': team.name, 'isLeader': false},
                      ),
                    ),
                    const SizedBox(height: ZadTokens.s2),
                  ],
                  if (d.isMember && !d.canEdit)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('مراسلة قائد الفريق'),
                      onPressed: _openMessageLeaderComposer,
                    ),
                  const SizedBox(height: ZadTokens.s4),
                  ..._shoppingCard(),
                  ZadAnimatedEntry(
                    delay: const Duration(milliseconds: 60),
                    child: _TurnCard(
                      state: _turnState,
                      loading: _turnLoading,
                      isMember: d.isMember,
                      onStart: _startTurn,
                      onComplete: _completeTurn,
                      onSkipMissedTurn: _skipMissedTurn,
                    ),
                  ),
                  if (d.isMember && d.members.isNotEmpty) ...[
                    // Stitch member header: title + real total count.
                    Padding(
                      padding: const EdgeInsets.only(
                        top: ZadTokens.s2,
                        bottom: ZadTokens.s3,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'أعضاء الفريق',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            'العدد الكلي: ${ltrFragment('${d.members.length}')}',
                            style: const TextStyle(
                              color: ZadTokens.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Stitch member list: one white card, warm dividers.
                    // Row-level busy state lives inside _MemberTile.
                    ZadAnimatedEntry(
                      delay: const Duration(milliseconds: 90),
                      child: Container(
                        decoration: BoxDecoration(
                          color: ZadTokens.surface,
                          borderRadius: BorderRadius.circular(
                            ZadTokens.radiusMd,
                          ),
                          boxShadow: ZadTokens.cardShadow,
                          border: Border.all(color: _warmBorder),
                        ),
                        child: Column(
                          children: [
                            for (final entry in d.members.asMap().entries) ...[
                              if (entry.key > 0)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _warmBorder,
                                ),
                              _MemberTile(
                                displayPosition: entry.key + 1,
                                member: entry.value,
                                canManage: d.canEdit,
                                busy: _busyMembers.contains(
                                  entry.value.memberId,
                                ),
                                onDeactivate: () => _deactivate(entry.value),
                                onReactivate: () => _reactivate(entry.value),
                                onRemove: () => _remove(entry.value),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else if (!d.isMember)
                    const Padding(
                      padding: EdgeInsets.only(top: ZadTokens.s2),
                      child: Text(
                        'انضم للفريق لرؤية الأعضاء',
                        style: TextStyle(color: ZadTokens.textMuted),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TurnCard extends StatelessWidget {
  final TeamTurnState? state;
  final bool loading;
  final bool isMember;
  final VoidCallback onStart;
  final void Function(String) onComplete;
  final void Function(String, String?) onSkipMissedTurn;

  const _TurnCard({
    required this.state,
    required this.loading,
    required this.isMember,
    required this.onStart,
    required this.onComplete,
    required this.onSkipMissedTurn,
  });

  @override
  Widget build(BuildContext context) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stitch turn-system header: gold icon + title.
          Row(
            children: [
              const Icon(
                Icons.event_repeat,
                size: 18,
                color: ZadTokens.goldDark,
              ),
              const SizedBox(width: ZadTokens.s2),
              Flexible(
                child: Text(
                  'نظام النوبات اليومي',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: ZadTokens.goldDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s1),
          const Text(
            'هنا تعرف من عليه الدور اليوم ومن بعده.',
            style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
          ),
          const Divider(height: 20),
          if (!isMember)
            const Text(
              'تفاصيل الأدوار تظهر لأعضاء الفريق فقط.',
              style: TextStyle(color: ZadTokens.textMuted),
            )
          else if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(ZadTokens.s2),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state == null)
            const Text(
              'لم تتوفر بيانات الأدوار حالياً',
              style: TextStyle(color: ZadTokens.textMuted),
            )
          else
            _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = state!;
    final today = s.todayTurn;
    final isBlocked = s.blockingPreviousTurn;
    final canSkipBlockedTurn =
        isBlocked &&
        s.canSkipPreviousTurn &&
        s.previousTurnId != null &&
        s.canManageTurns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBlocked) ...[
          _PreviousTurnBlockPanel(
            state: s,
            canSkip: canSkipBlockedTurn,
            onSkip: canSkipBlockedTurn
                ? () => _askSkipReason(context, s.previousTurnId!)
                : null,
          ),
          const SizedBox(height: ZadTokens.s2),
        ],
        if (today == null) ...[
          const Text(
            'لا يوجد دور لهذا اليوم.',
            style: TextStyle(color: ZadTokens.textMuted),
          ),
          if (s.canManageTurns && !isBlocked) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onStart,
                child: const Text('بدء دور اليوم'),
              ),
            ),
          ],
        ] else ...[
          // Today's responsible (Stitch): cream row, thick green side
          // border, pale-green initial avatar at the end.
          ClipRRect(
            borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
            child: Container(
              padding: const EdgeInsets.all(ZadTokens.s3),
              decoration: const BoxDecoration(
                color: ZadTokens.surfaceContainer,
                border: BorderDirectional(
                  start: BorderSide(color: ZadTokens.primary, width: 4),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المسؤول اليوم:',
                          style: TextStyle(
                            fontSize: 12,
                            color: ZadTokens.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          today.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: ZadTokens.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ZadTokens.s3),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _paleGreen,
                    child: Text(
                      today.displayName.isEmpty
                          ? '؟'
                          : today.displayName.characters.first,
                      style: const TextStyle(
                        color: ZadTokens.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (today.status == 'pending' && s.canManageTurns) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => onComplete(today.id),
                child: const Text('تم إنجاز الدور'),
              ),
            ),
          ],
        ],
        if (s.nextMember != null &&
            (today == null ||
                today.status == 'completed' ||
                today.memberId != s.nextMember!.memberId)) ...[
          const SizedBox(height: ZadTokens.s2),
          // Next member (Stitch): its own bordered row with a chevron.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s3,
              vertical: ZadTokens.s2 + 2,
            ),
            decoration: BoxDecoration(
              color: ZadTokens.background,
              borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
              border: Border.all(color: _warmBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'التالي:',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZadTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.nextMember!.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_back_ios_new,
                  size: 14,
                  color: ZadTokens.textMuted,
                ),
              ],
            ),
          ),
        ] else if (s.nextMember == null) ...[
          const SizedBox(height: ZadTokens.s2),
          const Text(
            'لا يوجد أعضاء نشطون للأدوار حالياً',
            style: TextStyle(color: ZadTokens.textMuted),
          ),
        ],
        if (s.lastCompletedTurn != null) ...[
          const SizedBox(height: ZadTokens.s3),
          // Last completed (Stitch): history icon + caption; real date,
          // no hardcoded "أمس".
          Row(
            children: [
              const Icon(Icons.history, size: 14, color: ZadTokens.textMuted),
              const SizedBox(width: ZadTokens.s1 + 2),
              Expanded(
                child: Text(
                  'آخر دور مكتمل: ${s.lastCompletedTurn!.displayName} '
                  '(${ltrFragment(s.lastCompletedTurn!.turnDate)})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZadTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (s.history.isNotEmpty) ...[
          const SizedBox(height: ZadTokens.s3),
          const Text(
            'آخر الأدوار',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: ZadTokens.s1),
          ...s.history
              .take(5)
              .map(
                (h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        h.turnDate,
                        style: const TextStyle(
                          color: ZadTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: ZadTokens.s2),
                      Expanded(
                        child: Text(
                          h.displayName,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _turnStatusLabel(h.status),
                              style: TextStyle(
                                color: h.status == 'completed'
                                    ? ZadTokens.primary
                                    : h.status == 'skipped'
                                    ? ZadTokens.textMuted
                                    : ZadTokens.warning,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (h.status == 'skipped' &&
                                h.skipReason != null &&
                                h.skipReason!.trim().isNotEmpty)
                              Text(
                                'سبب التخطي: ${h.skipReason!}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: ZadTokens.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }

  Future<void> _askSkipReason(BuildContext context, String turnId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ShoppingReasonDialog(
        title: 'تخطّي الدور السابق',
        label: 'سبب التخطي',
        maxLength: 300,
        requireReason: false,
      ),
    );
    if (reason == null) return;
    onSkipMissedTurn(turnId, reason);
  }
}

String _turnStatusLabel(String status) {
  if (status == 'completed') return '✓';
  // Alternative accepted wording for skipped turns: دور متخطّى.
  if (status == 'skipped') return 'تم التخطي';
  return '…';
}

class _PreviousTurnBlockPanel extends StatelessWidget {
  final TeamTurnState state;
  final bool canSkip;
  final VoidCallback? onSkip;

  const _PreviousTurnBlockPanel({
    required this.state,
    required this.canSkip,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final memberName = state.previousTurnMemberName;
    final date = state.previousTurnDate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZadTokens.s3),
      decoration: BoxDecoration(
        color: ZadTokens.goldSoft,
        borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
        border: Border.all(color: ZadTokens.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'أكمل الدور السابق أولاً',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (canSkip) ...[
            const SizedBox(height: 4),
            const Text(
              'يوجد دور سابق لم يبدأ بعد',
              style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
            ),
            if (memberName != null && memberName.isNotEmpty)
              Text('العضو: $memberName', style: const TextStyle(fontSize: 13)),
            if (date != null && date.isNotEmpty)
              Text(
                'التاريخ: ${ltrFragment(date)}',
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: ZadTokens.s2),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next_outlined),
                label: const Text('تخطّي الدور السابق'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShoppingFinancialBox extends StatelessWidget {
  final String status;
  final List<Widget> children;

  const _ShoppingFinancialBox({required this.status, required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warmBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZadTokens.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Badge(status, gold: true),
            ),
            const SizedBox(height: ZadTokens.s2),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ShoppingFinancialRow extends StatelessWidget {
  final String label;
  final String value;

  const _ShoppingFinancialRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool gold;
  const _Badge(this.label, {this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: gold ? ZadTokens.goldSoft : ZadTokens.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: gold ? ZadTokens.primaryDark : ZadTokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final int displayPosition;
  final TeamMember member;
  final bool canManage;
  final bool busy;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  final VoidCallback onRemove;
  const _MemberTile({
    required this.displayPosition,
    required this.member,
    required this.canManage,
    required this.busy,
    required this.onDeactivate,
    required this.onReactivate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isLeader = member.role == 'leader';
    final showActions = canManage && !isLeader;
    final caption = [
      if (!member.hasAccount) 'بدون حساب',
      if (member.phoneMasked != null) ltrFragment(member.phoneMasked!),
    ].join(' · ');

    // Info part fades for inactive members (Stitch); action buttons stay
    // at full opacity so reactivate remains obvious and tappable.
    final info = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: member.isActive
                ? ZadTokens.surfaceContainer
                : ZadTokens.textMuted.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
          ),
          child: Text(
            '$displayPosition',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: member.isActive ? ZadTokens.primary : ZadTokens.textMuted,
            ),
          ),
        ),
        const SizedBox(width: ZadTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isLeader
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isLeader) ...[
                    const SizedBox(width: ZadTokens.s2),
                    const _MemberChip('القائد', gold: true),
                  ],
                  if (!member.isActive) ...[
                    const SizedBox(width: ZadTokens.s2),
                    const _MemberChip('غير نشط'),
                  ],
                ],
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZadTokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZadTokens.s3,
        vertical: ZadTokens.s2 + 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: member.isActive ? info : Opacity(opacity: 0.55, child: info),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(ZadTokens.s2),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (showActions) ...[
            if (member.isActive)
              IconButton(
                tooltip: 'تعطيل',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.person_off_outlined,
                  color: ZadTokens.textMuted,
                ),
                onPressed: onDeactivate,
              )
            else
              IconButton(
                tooltip: 'تفعيل',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.how_to_reg, color: ZadTokens.primary),
                onPressed: onReactivate,
              ),
            IconButton(
              tooltip: 'إزالة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.person_remove_outlined,
                color: ZadTokens.danger,
              ),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small role/state chip on member rows (Stitch: القائد / غير نشط).
class _MemberChip extends StatelessWidget {
  final String label;
  final bool gold;
  const _MemberChip(this.label, {this.gold = false});

  @override
  Widget build(BuildContext context) {
    final color = gold ? ZadTokens.goldDark : ZadTokens.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Icon + text stat in the hero footer (Stitch: groups / verified_user).
class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroStat(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ZadTokens.gold),
        const SizedBox(width: ZadTokens.s1 + 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Pill badge for the green hero: white-tinted, or solid gold for accent.
class _HeroBadge extends StatelessWidget {
  final String label;
  final bool gold;
  const _HeroBadge(this.label, {this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZadTokens.s2 + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: gold ? ZadTokens.gold : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: gold ? ZadTokens.primaryDark : Colors.white,
        ),
      ),
    );
  }
}

class _ShoppingReasonDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialReason;
  final int maxLength;
  final bool requireReason;

  const _ShoppingReasonDialog({
    this.title = 'سبب عدم الشراء',
    this.label = 'السبب',
    this.initialReason,
    this.maxLength = 200,
    this.requireReason = true,
  });

  @override
  State<_ShoppingReasonDialog> createState() => _ShoppingReasonDialogState();
}

class _ShoppingReasonDialogState extends State<_ShoppingReasonDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialReason,
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _ctrl.text.trim();
    if (widget.requireReason && value.isEmpty) {
      setState(() => _error = 'السبب مطلوب');
      return;
    }
    if (value.length > widget.maxLength) {
      setState(() => _error = 'النص طويل جداً');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _submit, child: const Text('حفظ')),
    ],
  );
}

/// Final confirmation before a leader rejection actually submits — shown
/// after the reason dialog, before the RPC fires. Guards its own confirm
/// tap (`_confirmed`) so a rapid double-tap on تأكيد الرفض can never pop
/// the dialog's route twice (which would otherwise pop whatever route is
/// underneath once the dialog itself is already gone).
class _ConfirmRejectReportDialog extends StatefulWidget {
  const _ConfirmRejectReportDialog();

  @override
  State<_ConfirmRejectReportDialog> createState() =>
      _ConfirmRejectReportDialogState();
}

class _ConfirmRejectReportDialogState
    extends State<_ConfirmRejectReportDialog> {
  bool _confirmed = false;

  void _confirm() {
    if (_confirmed) return;
    setState(() => _confirmed = true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تأكيد رفض التقرير'),
    content: const Text('هل أنت متأكد من رفض تقرير التسوق؟'),
    actions: [
      TextButton(
        onPressed: _confirmed ? null : () => Navigator.of(context).pop(false),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: _confirmed ? null : _confirm,
        child: _confirmed
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('تأكيد الرفض'),
      ),
    ],
  );
}

/// Leader-only add/edit sheet for a single shopping list item.
class _ShoppingItemSheet extends StatefulWidget {
  final TeamShoppingItem? existing;
  final Future<void> Function(
    String name,
    String? quantityNote,
    bool isRequired,
    double? price,
    double? quantityValue,
    String? quantityUnit,
  )
  onSubmit;

  const _ShoppingItemSheet({this.existing, required this.onSubmit});

  @override
  State<_ShoppingItemSheet> createState() => _ShoppingItemSheetState();
}

class _ShoppingItemSheetState extends State<_ShoppingItemSheet> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _noteCtrl = TextEditingController(
    text: widget.existing?.quantityNote,
  );
  late final _priceCtrl = TextEditingController(
    text: _initialPriceText(widget.existing?.price),
  );
  late final _quantityValueCtrl = TextEditingController(
    text: _initialPriceText(widget.existing?.quantityValue),
  );
  late String? _quantityUnit = widget.existing?.quantityUnit;
  late bool _isRequired = widget.existing?.isRequired ?? true;
  bool _saving = false;
  String? _error;

  static String? _initialPriceText(double? value) {
    if (value == null) return null;
    final isWhole = value == value.roundToDouble();
    return isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _priceCtrl.dispose();
    _quantityValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم العنصر مطلوب');
      return;
    }
    final priceText = _priceCtrl.text.trim();
    double? price;
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText);
      if (price == null || price < 0) {
        setState(() => _error = 'أدخل سعرًا صحيحًا');
        return;
      }
    }
    final quantityText = _quantityValueCtrl.text.trim();
    double? quantityValue;
    String? quantityUnit = _quantityUnit;
    if (quantityText.isEmpty && quantityUnit == null) {
      // both empty: no structured quantity, submit null/null.
    } else if (quantityText.isEmpty) {
      setState(() => _error = 'أدخل رقم الكمية');
      return;
    } else if (quantityUnit == null) {
      setState(() => _error = 'اختر نوع الكمية');
      return;
    } else {
      quantityValue = double.tryParse(quantityText);
      if (quantityValue == null || quantityValue < 0) {
        setState(() => _error = 'أدخل كمية صحيحة');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        name,
        _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        _isRequired,
        price,
        quantityValue,
        quantityUnit,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorText(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ZadTokens.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: ZadTokens.s2),
              child: ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
            ),
          TextField(
            controller: _nameCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'اسم العنصر'),
          ),
          const SizedBox(height: ZadTokens.s3),
          TextField(
            controller: _quantityValueCtrl,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الكمية'),
          ),
          const SizedBox(height: ZadTokens.s2),
          Wrap(
            spacing: ZadTokens.s2,
            runSpacing: ZadTokens.s1,
            children: [
              for (final unit in _kShoppingQuantityUnits)
                ChoiceChip(
                  label: Text(unit.value),
                  selected: _quantityUnit == unit.key,
                  onSelected: _saving
                      ? null
                      : (_) => setState(
                          () => _quantityUnit = _quantityUnit == unit.key
                              ? null
                              : unit.key,
                        ),
                ),
            ],
          ),
          const SizedBox(height: ZadTokens.s3),
          TextField(
            controller: _noteCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'ملاحظة الكمية'),
          ),
          const SizedBox(height: ZadTokens.s3),
          TextField(
            controller: _priceCtrl,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'السعر',
              suffixText: 'MRU',
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('أساسي'),
                  selected: _isRequired,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _isRequired = true),
                ),
              ),
              const SizedBox(width: ZadTokens.s2),
              Expanded(
                child: ChoiceChip(
                  label: const Text('اختياري'),
                  selected: !_isRequired,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _isRequired = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s4),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: ZadTokens.s2),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
