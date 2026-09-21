import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required SharedPreferences preferences,
  }) : this._(database, preferences);

  AppController._(this._database, this._preferences);

  static const _sessionKey = 'medistock-authenticated';
  static const validEmail = 'admin@gmail.com';
  static const validPassword = '12345678';

  final AppDatabase _database;
  final SharedPreferences _preferences;

  bool _initialized = false;
  bool _authenticated = false;
  bool _busy = false;
  int _selectedIndex = 0;
  int _selectedSalesTab = 0;
  String? _errorMessage;
  List<Medicine> _medicines = const [];
  List<InvoiceRecord> _invoices = const [];
  List<Supplier> _suppliers = const [];
  List<PurchaseRecord> _purchases = const [];
  List<BranchOrder> _branchOrders = const [];
  List<BranchSummary> _branchSummaries = const [];
  List<StaffMember> _staffMembers = const [];
  List<CartItem> _cart = const [];
  DashboardStats _stats = const DashboardStats.empty();
  StaffMember? _currentStaff;

  bool get initialized => _initialized;
  bool get authenticated => _authenticated;
  bool get busy => _busy;
  int get selectedIndex => _selectedIndex;
  int get selectedSalesTab => _selectedSalesTab;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _authenticated && _currentStaff == null;
  StaffMember? get currentStaff => _currentStaff;
  String? get staffBranch => _currentStaff?.branch;
  String get currentUserName => _currentStaff?.name ?? 'Administrator';
  String get currentUserSubtitle => _currentStaff == null
      ? 'Offline workspace'
      : '${_currentStaff!.role} · ${_currentStaff!.branch}';
  UnmodifiableListView<Medicine> get medicines =>
      UnmodifiableListView(_medicines);
  UnmodifiableListView<InvoiceRecord> get invoices =>
      UnmodifiableListView(_invoices);
  UnmodifiableListView<Supplier> get suppliers =>
      UnmodifiableListView(_suppliers);
  UnmodifiableListView<PurchaseRecord> get purchases =>
      UnmodifiableListView(_purchases);
  UnmodifiableListView<BranchOrder> get branchOrders =>
      UnmodifiableListView(_branchOrders);
  UnmodifiableListView<BranchSummary> get branchSummaries =>
      UnmodifiableListView(_branchSummaries);
  UnmodifiableListView<StaffMember> get staffMembers =>
      UnmodifiableListView(_staffMembers);
  UnmodifiableListView<CartItem> get cart => UnmodifiableListView(_cart);
  DashboardStats get stats => _stats;

  List<Medicine> get inStockMedicines => _medicines
      .where((medicine) => medicine.stock > 0 && canEditMedicine(medicine))
      .toList(growable: false);

  List<Medicine> get lowStockMedicines => _medicines
      .where((medicine) => medicine.isLowStock && canEditMedicine(medicine))
      .take(5)
      .toList(growable: false);

  bool canEditMedicine(Medicine medicine) =>
      staffBranch == null ||
      medicine.branch.toLowerCase() == staffBranch!.toLowerCase();

  List<InvoiceRecord> get recentInvoices =>
      _invoices.take(5).toList(growable: false);

  int get cartSubtotalPaise =>
      _cart.fold<int>(0, (sum, item) => sum + item.lineGrossPaise);
  int get cartLineDiscountPaise =>
      _cart.fold<int>(0, (sum, item) => sum + item.discountPaise);
  int get cartNetSubtotalPaise => cartSubtotalPaise - cartLineDiscountPaise;

  Future<void> initialize() async {
    await _database.database;
    _authenticated = _preferences.getBool(_sessionKey) ?? false;
    _currentStaff = null;
    if (_authenticated) {
      await refresh();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    final valid =
        email.trim().toLowerCase() == validEmail && password == validPassword;
    if (!valid) return false;
    _authenticated = true;
    _currentStaff = null;
    await _preferences.setBool(_sessionKey, true);
    _selectedIndex = 0;
    _selectedSalesTab = 0;
    notifyListeners();
    await refresh();
    return true;
  }

  Future<bool> loginStaff(String email, String pin) async {
    final staff = await _database.authenticateStaff(email, pin);
    if (staff == null) return false;
    await _preferences.remove(_sessionKey);
    _authenticated = true;
    _currentStaff = staff;
    _selectedIndex = 0;
    _selectedSalesTab = 0;
    _medicines = const [];
    _invoices = const [];
    _suppliers = const [];
    _purchases = const [];
    _branchOrders = const [];
    _branchSummaries = const [];
    _staffMembers = const [];
    _cart = const [];
    _stats = const DashboardStats.empty();
    notifyListeners();
    await refresh();
    return true;
  }

  Future<void> logout() async {
    await _preferences.remove(_sessionKey);
    _authenticated = false;
    _currentStaff = null;
    _selectedIndex = 0;
    _selectedSalesTab = 0;
    _cart = const [];
    _medicines = const [];
    _invoices = const [];
    _stats = const DashboardStats.empty();
    _suppliers = const [];
    _purchases = const [];
    _branchOrders = const [];
    _branchSummaries = const [];
    _staffMembers = const [];
    notifyListeners();
  }

  void selectTab(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index.clamp(0, isAdmin ? 8 : 6).toInt();
    notifyListeners();
  }

  void selectSalesTab(int index) {
    final next = index.clamp(0, 1).toInt();
    if (next == _selectedSalesTab) return;
    _selectedSalesTab = next;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    _setBusy(true);
    try {
      final medicines = await _database.listMedicines();
      final invoices = await _database.listInvoices();
      final suppliers = await _database.listSuppliers();
      final purchases = await _database.listPurchases();
      final orders = await _database.listBranchOrders(branch: staffBranch);
      final stats = await _database.getDashboardStats(branch: staffBranch);
      final branches = isAdmin
          ? await _database.listBranchSummaries()
          : const <BranchSummary>[];
      final staff = isAdmin
          ? await _database.listStaff()
          : const <StaffMember>[];
      _medicines = medicines;
      _invoices = invoices;
      _suppliers = suppliers;
      _purchases = _visiblePurchases(purchases);
      _branchOrders = orders;
      _stats = stats;
      _branchSummaries = branches;
      _staffMembers = staff;
      _errorMessage = null;
      _reconcileCart();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<Medicine> saveMedicine(Medicine medicine) async {
    _setBusy(true);
    try {
      final saved = await _database.saveMedicine(medicine, branch: staffBranch);
      if (saved.isLowStock) {
        await NotificationService.showLowStock(saved);
      }
      await _reloadWithoutBusyToggle();
      return saved;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteMedicine(int medicineId) async {
    _setBusy(true);
    try {
      final deleted = await _database.deleteMedicine(
        medicineId,
        branch: staffBranch,
      );
      if (!deleted && staffBranch != null) {
        throw StateError('Medicine not found in your branch.');
      }
      _cart = _cart.where((item) => item.medicineId != medicineId).toList();
      await _reloadWithoutBusyToggle();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<Medicine?> lookupBarcode(String barcode) =>
      _database.lookupMedicineByBarcode(barcode, branch: staffBranch);

  Future<Supplier> saveSupplier(Supplier supplier) async {
    _setBusy(true);
    try {
      final saved = await _database.saveSupplier(supplier);
      await _reloadWithoutBusyToggle();
      return saved;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteSupplier(int supplierId) async {
    _setBusy(true);
    try {
      await _database.deleteSupplier(supplierId);
      await _reloadWithoutBusyToggle();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<PurchaseRecord> savePurchase(PurchaseRecord purchase) async {
    try {
      _requireOwnPurchaseBranch(purchase.branch);
      if (purchase.id != null) {
        final existing = await _database.getPurchase(purchase.id!);
        if (existing == null) throw StateError('Purchase no longer exists.');
        _requireOwnPurchaseBranch(existing.branch);
      }
      final saved = await _database.savePurchase(purchase);
      await _reloadWithoutBusyToggle();
      return saved;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    }
  }

  Future<void> deletePurchase(int purchaseId) async {
    _setBusy(true);
    try {
      final purchase = await _database.getPurchase(purchaseId);
      if (purchase == null) throw StateError('Purchase no longer exists.');
      _requireOwnPurchaseBranch(purchase.branch);
      await _database.deletePurchase(purchaseId);
      await _reloadWithoutBusyToggle();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<PurchaseRecord> completePurchase(int purchaseId) async {
    _setBusy(true);
    try {
      final purchase = await _database.getPurchase(purchaseId);
      if (purchase == null) throw StateError('Purchase no longer exists.');
      _requireOwnPurchaseBranch(purchase.branch);
      final completed = await _database.completePurchase(purchaseId);
      await _reloadWithoutBusyToggle();
      return completed;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<List<MedicineMatch>> findMedicineCandidates(
    String query, {
    int limit = 5,
  }) => _database.findMedicineCandidates(
    query,
    limit: limit,
    branch: staffBranch,
  );

  Future<LastPurchaseInfo?> getLastPurchaseInfo(int medicineId) =>
      _database.getLastPurchaseInfo(medicineId, branch: staffBranch);

  Future<List<BranchAvailability>> availabilityFor(int medicineId) =>
      _database.getBranchAvailability(medicineId);

  Future<BranchOrder> requestBranchOrder({
    required int sourceMedicineId,
    required String destinationBranch,
    required int quantity,
  }) async {
    _setBusy(true);
    try {
      final order = await _database.createBranchOrder(
        sourceMedicineId: sourceMedicineId,
        destinationBranch: destinationBranch,
        quantity: quantity,
        requestedBy: currentUserName,
        requestingBranch: staffBranch,
      );
      await _reloadWithoutBusyToggle();
      return order;
    } finally {
      _setBusy(false);
    }
  }

  Future<BranchOrder> dispatchBranchOrder(int id) async {
    _setBusy(true);
    try {
      final order = await _database.dispatchBranchOrder(
        id,
        actorBranch: staffBranch,
      );
      await _reloadWithoutBusyToggle();
      return order;
    } finally {
      _setBusy(false);
    }
  }

  Future<BranchOrder> receiveBranchOrder(int id) async {
    _setBusy(true);
    try {
      final order = await _database.receiveBranchOrder(
        id,
        actorBranch: staffBranch,
      );
      await _reloadWithoutBusyToggle();
      return order;
    } finally {
      _setBusy(false);
    }
  }

  Future<BranchOrder> cancelBranchOrder(int id) async {
    _setBusy(true);
    try {
      final order = await _database.cancelBranchOrder(
        id,
        actorBranch: staffBranch,
      );
      await _reloadWithoutBusyToggle();
      return order;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> setBranchActive(String branch, bool active) async {
    _requireAdmin();
    _setBusy(true);
    try {
      await _database.setBranchActive(branch, active);
      await _reloadWithoutBusyToggle();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<StaffMember> saveStaff(StaffMember staff, {String? pin}) async {
    _requireAdmin();
    _setBusy(true);
    try {
      final saved = await _database.saveStaff(staff, pin: pin);
      await _reloadWithoutBusyToggle();
      return saved;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteStaff(int staffId) async {
    _requireAdmin();
    _setBusy(true);
    try {
      await _database.deleteStaff(staffId);
      await _reloadWithoutBusyToggle();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void addToCart(Medicine medicine, int quantity) {
    if (staffBranch != null &&
        medicine.branch.toLowerCase() != staffBranch!.toLowerCase()) {
      throw StateError('Staff can only bill stock from their assigned branch.');
    }
    final persistedId = medicine.id;
    if (persistedId == null) {
      throw StateError('Save the medicine before billing it.');
    }
    if (staffBranch != null &&
        !_medicines.any((known) => known.id == persistedId)) {
      throw StateError('Medicine not found in your branch.');
    }
    if (quantity < 1) throw ArgumentError('Quantity must be at least 1.');
    final existingIndex = _cart.indexWhere(
      (item) => item.medicineId == persistedId,
    );
    final existingQuantity = existingIndex < 0
        ? 0
        : _cart[existingIndex].quantity;
    if (existingQuantity + quantity > medicine.stock) {
      throw StateError(
        '${medicine.name} has only ${medicine.stock} available.',
      );
    }

    final updated = [..._cart];
    if (existingIndex < 0) {
      updated.add(CartItem.fromMedicine(medicine, quantity: quantity));
    } else {
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: existingQuantity + quantity,
      );
    }
    _cart = updated;
    notifyListeners();
  }

  void removeFromCart(int medicineId) {
    _cart = _cart.where((item) => item.medicineId != medicineId).toList();
    notifyListeners();
  }

  void updateCartItemDiscount(int medicineId, double discountPercent) {
    if (!discountPercent.isFinite) {
      throw ArgumentError('Discount must be a valid number.');
    }
    final index = _cart.indexWhere((item) => item.medicineId == medicineId);
    if (index < 0) throw StateError('Bill item was not found.');
    final updated = [..._cart];
    updated[index] = updated[index].copyWith(
      discountPercent: discountPercent.clamp(0, 100).toDouble(),
    );
    _cart = updated;
    notifyListeners();
  }

  List<Medicine> substitutionSuggestions(
    Medicine medicine, {
    int quantity = 1,
  }) {
    final composition = _normalizedComposition(medicine.composition);
    if (composition.isEmpty) return const <Medicine>[];
    final suggestions = _medicines.where((candidate) {
      final alreadyInCart = _cart
          .where((item) => item.medicineId == candidate.id)
          .fold<int>(0, (sum, item) => sum + item.quantity);
      return candidate.id != medicine.id &&
          canEditMedicine(candidate) &&
          candidate.stock >= quantity + alreadyInCart &&
          _normalizedComposition(candidate.composition) == composition;
    }).toList();
    suggestions.sort((first, second) {
      final firstSameBranch = first.branch == medicine.branch ? 0 : 1;
      final secondSameBranch = second.branch == medicine.branch ? 0 : 1;
      final byBranch = firstSameBranch.compareTo(secondSameBranch);
      if (byBranch != 0) return byBranch;
      final byPrice = first.pricePaise.compareTo(second.pricePaise);
      if (byPrice != 0) return byPrice;
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return List<Medicine>.unmodifiable(suggestions);
  }

  void repeatInvoice(InvoiceRecord invoice) {
    if (invoice.items.isEmpty) {
      throw StateError('This invoice has no items to repeat.');
    }
    final byId = <int, Medicine>{
      for (final medicine in _medicines)
        if (medicine.id != null) medicine.id!: medicine,
    };
    final unavailable = <String>[];
    final repeated = <CartItem>[];
    for (final item in invoice.items) {
      final medicine = item.medicineId == null ? null : byId[item.medicineId];
      if (medicine == null || !canEditMedicine(medicine)) {
        unavailable.add('${item.medicineName} is no longer in stock catalog');
        continue;
      }
      if (medicine.stock < item.quantity) {
        unavailable.add(
          '${medicine.name}: needs ${item.quantity}, only ${medicine.stock} available',
        );
        continue;
      }
      repeated.add(
        CartItem.fromMedicine(
          medicine,
          quantity: item.quantity,
        ).copyWith(discountPercent: item.discountPercent),
      );
    }
    if (unavailable.isNotEmpty) {
      throw StateError('Cannot repeat sale. ${unavailable.join('; ')}.');
    }
    _cart = List<CartItem>.unmodifiable(repeated);
    notifyListeners();
  }

  void clearCart() {
    if (_cart.isEmpty) return;
    _cart = const [];
    notifyListeners();
  }

  InvoiceRecord buildDraftInvoice({
    required String customerName,
    required String customerPhone,
    required double taxPercent,
    required double discountPercent,
    String doctorName = '',
    String paymentMethod = 'Cash',
    DateTime? nextRefillDate,
  }) {
    final subtotal = cartSubtotalPaise;
    final tax = (subtotal * taxPercent.clamp(0, double.infinity) / 100).round();
    final globalDiscount = (subtotal * discountPercent.clamp(0, 100) / 100)
        .round();
    final discount = cartLineDiscountPaise + globalDiscount;
    final total = (subtotal + tax - discount).clamp(0, 1 << 62).toInt();
    final items = _cart
        .map(
          (item) => InvoiceItem(
            medicineId: item.medicineId,
            medicineName: item.medicineName,
            sku: item.sku,
            quantity: item.quantity,
            unitPricePaise: item.unitPricePaise,
            lineTotalPaise: item.lineTotalPaise,
            discountPercent: item.discountPercent,
            costPaise:
                _medicines
                    .where((medicine) => medicine.id == item.medicineId)
                    .map((medicine) => medicine.costPaise)
                    .firstOrNull ??
                0,
          ),
        )
        .toList(growable: false);

    return InvoiceRecord(
      number: 'DRAFT',
      customerName: customerName.trim().isEmpty
          ? 'Walk-in patient'
          : customerName.trim(),
      customerPhone: customerPhone.trim(),
      subtotalPaise: subtotal,
      taxPaise: tax,
      discountPaise: discount,
      totalPaise: total,
      createdAt: DateTime.now(),
      doctorName: doctorName.trim(),
      paymentMethod: paymentMethod.trim().isEmpty
          ? 'Cash'
          : paymentMethod.trim(),
      nextRefillDate: nextRefillDate,
      items: items,
    );
  }

  Future<InvoiceRecord> createInvoice({
    required String customerName,
    required String customerPhone,
    required double taxPercent,
    required double discountPercent,
    String doctorName = '',
    String paymentMethod = 'Cash',
    DateTime? nextRefillDate,
  }) async {
    if (_cart.isEmpty) throw StateError('Add at least one bill item.');
    if (customerPhone.trim().isEmpty) {
      throw StateError('Enter patient phone number for the invoice.');
    }

    final billedIds = _cart.map((item) => item.medicineId).toSet();
    _setBusy(true);
    try {
      final invoice = await _database.createInvoice(
        cartItems: _cart,
        branch: staffBranch,
        customerName: customerName,
        customerPhone: customerPhone,
        taxPercent: taxPercent,
        discountPercent: discountPercent,
        doctorName: doctorName,
        paymentMethod: paymentMethod,
        nextRefillDate: nextRefillDate,
      );
      _cart = const [];
      await _reloadWithoutBusyToggle();
      for (final medicine in _medicines) {
        if (billedIds.contains(medicine.id) && medicine.isLowStock) {
          await NotificationService.showLowStock(medicine);
        }
      }
      return invoice;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<int> seedSampleData() async {
    _setBusy(true);
    try {
      final count = await _database.seedSampleData();
      await _reloadWithoutBusyToggle();
      return count;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> clearAllData() async {
    _setBusy(true);
    try {
      await _database.clearAllData();
      _cart = const [];
      await _reloadWithoutBusyToggle();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _reloadWithoutBusyToggle() async {
    _medicines = await _database.listMedicines();
    _invoices = await _database.listInvoices();
    _suppliers = await _database.listSuppliers();
    _purchases = _visiblePurchases(await _database.listPurchases());
    _branchOrders = await _database.listBranchOrders(branch: staffBranch);
    _stats = await _database.getDashboardStats(branch: staffBranch);
    _branchSummaries = isAdmin
        ? await _database.listBranchSummaries()
        : const <BranchSummary>[];
    _staffMembers = isAdmin
        ? await _database.listStaff()
        : const <StaffMember>[];
    _errorMessage = null;
    _reconcileCart();
    notifyListeners();
  }

  List<PurchaseRecord> _visiblePurchases(List<PurchaseRecord> purchases) {
    final branch = _currentStaff?.branch;
    if (branch == null) return purchases;
    return purchases
        .where((purchase) => purchase.branch == branch)
        .toList(growable: false);
  }

  void _requireOwnPurchaseBranch(String branch) {
    final staffBranch = _currentStaff?.branch;
    if (staffBranch != null && branch != staffBranch) {
      throw StateError('Staff can only manage purchases for their own branch.');
    }
  }

  void _reconcileCart() {
    final byId = <int, Medicine>{
      for (final medicine in _medicines)
        if (medicine.id != null) medicine.id!: medicine,
    };
    _cart = _cart
        .where(
          (item) =>
              byId.containsKey(item.medicineId) &&
              canEditMedicine(byId[item.medicineId]!) &&
              byId[item.medicineId]!.stock > 0,
        )
        .map((item) {
          final medicine = byId[item.medicineId]!;
          final quantity = math.min(item.quantity, medicine.stock);
          return CartItem.fromMedicine(
            medicine,
            quantity: quantity,
          ).copyWith(discountPercent: item.discountPercent);
        })
        .where((item) => item.quantity > 0)
        .toList();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  void _requireAdmin() {
    if (!isAdmin) {
      throw StateError('Administrator access is required.');
    }
  }

  static String _normalizedComposition(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
}
