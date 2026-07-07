import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/team_shopping_models.dart';

class TeamShoppingService {
  SupabaseClient get _c => Supabase.instance.client;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static TeamShoppingOverview _overview(dynamic result) =>
      TeamShoppingOverview.fromJson(
          Map<String, dynamic>.from(result as Map));

  Future<TeamShoppingOverview> getShoppingList({
    required String sessionToken,
    required String teamId,
    DateTime? date,
  }) async {
    final params = <String, dynamic>{
      'p_session_token': sessionToken,
      'p_team_id': teamId,
    };
    if (date != null) {
      params['p_date'] = _date(date);
    }
    final res = await _c.rpc('get_team_shopping_list', params: params);
    return _overview(res);
  }

  Future<TeamShoppingOverview> addItem({
    required String sessionToken,
    required String teamId,
    required String name,
    String? quantityNote,
    bool isRequired = true,
    double? price,
    double? quantityValue,
    String? quantityUnit,
  }) async {
    final res = await _c.rpc('add_team_shopping_item', params: {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_name': name,
      'p_quantity_note': quantityNote,
      'p_is_required': isRequired,
      'p_price': price,
      'p_quantity_value': quantityValue,
      'p_quantity_unit': quantityUnit,
    });
    return _overview(res);
  }

  Future<TeamShoppingOverview> updateItem({
    required String sessionToken,
    required String teamId,
    required String itemId,
    required String name,
    String? quantityNote,
    bool isRequired = true,
    double? price,
    double? quantityValue,
    String? quantityUnit,
  }) async {
    final res = await _c.rpc('update_team_shopping_item', params: {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
      'p_name': name,
      'p_quantity_note': quantityNote,
      'p_is_required': isRequired,
      'p_price': price,
      'p_quantity_value': quantityValue,
      'p_quantity_unit': quantityUnit,
    });
    return _overview(res);
  }

  Future<TeamShoppingOverview> deactivateItem({
    required String sessionToken,
    required String teamId,
    required String itemId,
  }) async {
    final res = await _c.rpc('deactivate_team_shopping_item', params: {
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
    });
    return _overview(res);
  }

  Future<TeamShoppingOverview> markItemStatus({
    required String sessionToken,
    required String teamId,
    required String itemId,
    required bool bought,
    DateTime? date,
  }) async {
    final params = <String, dynamic>{
      'p_session_token': sessionToken,
      'p_team_id': teamId,
      'p_item_id': itemId,
      'p_bought': bought,
    };
    if (date != null) {
      params['p_date'] = _date(date);
    }
    final res = await _c.rpc('mark_shopping_item_status', params: params);
    return _overview(res);
  }
}
