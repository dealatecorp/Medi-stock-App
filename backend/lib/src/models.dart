/// The branches exposed by the original MediStock application.
const List<String> medistockBranches = <String>[
  'Main Branch',
  'City Branch',
  'North Branch',
  'South Branch',
];

/// A short alias that keeps branch selectors pleasant to use in the UI.
const List<String> branches = medistockBranches;

/// Converts a rupee value at an input boundary to its exact database unit.
int rupeesToPaise(num rupees) {
  if (!rupees.isFinite) {
    throw ArgumentError.value(rupees, 'rupees', 'Must be a finite number.');
  }
  return (rupees * 100).round();
}

double paiseToRupees(int paise) => paise / 100;

class Medicine {
  const Medicine({
    this.id,
    this.barcode = '',
    required this.name,
    this.genericName = '',
    this.brandName = '',
    this.composition = '',
    this.scheduleCategory = '',
    this.dosageForm = '',
    required this.sku,
    this.manufacturer = '',
    this.mfgDate,
    this.expiryDate,
    required this.branch,
    required this.stock,
    required this.reorderThreshold,
    required this.costPaise,
    required this.pricePaise,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String barcode;
  final String name;
  final String genericName;
  final String brandName;
  final String composition;
  final String scheduleCategory;
  final String dosageForm;
  final String sku;
  final String manufacturer;
  final DateTime? mfgDate;
  final DateTime? expiryDate;
  final String branch;
  final int stock;
  final int reorderThreshold;
  final int costPaise;
  final int pricePaise;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLowStock => stock <= reorderThreshold;
  bool get isOutOfStock => stock <= 0;
  int get stockValuePaise => stock * costPaise;

  // Familiar aliases for code ported from the web client.
  String get generic => genericName;
  String get brand => brandName;
  int get threshold => reorderThreshold;

  Medicine copyWith({
    int? id,
    String? barcode,
    String? name,
    String? genericName,
    String? brandName,
    String? composition,
    String? scheduleCategory,
    String? dosageForm,
    String? sku,
    String? manufacturer,
    DateTime? mfgDate,
    bool clearMfgDate = false,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    String? branch,
    int? stock,
    int? reorderThreshold,
    int? costPaise,
    int? pricePaise,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Medicine(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      genericName: genericName ?? this.genericName,
      brandName: brandName ?? this.brandName,
      composition: composition ?? this.composition,
      scheduleCategory: scheduleCategory ?? this.scheduleCategory,
      dosageForm: dosageForm ?? this.dosageForm,
      sku: sku ?? this.sku,
      manufacturer: manufacturer ?? this.manufacturer,
      mfgDate: clearMfgDate ? null : (mfgDate ?? this.mfgDate),
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      branch: branch ?? this.branch,
      stock: stock ?? this.stock,
      reorderThreshold: reorderThreshold ?? this.reorderThreshold,
      costPaise: costPaise ?? this.costPaise,
      pricePaise: pricePaise ?? this.pricePaise,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Medicine.fromMap(Map<String, Object?> map) {
    return Medicine(
      id: _nullableInt(map['id']),
      barcode: _string(map['barcode']),
      name: _string(map['name']),
      genericName: _string(map['generic_name']),
      brandName: _string(map['brand_name']),
      composition: _string(map['composition']),
      scheduleCategory: _string(map['schedule_category']),
      dosageForm: _string(map['dosage_form']),
      sku: _string(map['sku']),
      manufacturer: _string(map['manufacturer']),
      mfgDate: _nullableDateTime(map['mfg_date']),
      expiryDate: _nullableDateTime(map['expiry_date']),
      branch: _string(map['branch']),
      stock: _int(map['stock']),
      reorderThreshold: _int(map['threshold_qty']),
      costPaise: _int(map['cost_paise']),
      pricePaise: _int(map['price_paise']),
      createdAt: _nullableDateTime(map['created_at']),
      updatedAt: _nullableDateTime(map['updated_at']),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'barcode': barcode,
      'name': name,
      'generic_name': genericName,
      'brand_name': brandName,
      'composition': composition,
      'schedule_category': scheduleCategory,
      'dosage_form': dosageForm,
      'sku': sku,
      'manufacturer': manufacturer,
      'mfg_date': _dateOnly(mfgDate),
      'expiry_date': _dateOnly(expiryDate),
      'branch': branch,
      'stock': stock,
      'threshold_qty': reorderThreshold,
      'cost_paise': costPaise,
      'price_paise': pricePaise,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

class CartItem {
  const CartItem({
    required this.medicineId,
    required this.medicineName,
    required this.sku,
    required this.branch,
    required this.quantity,
    required this.unitPricePaise,
    this.discountPercent = 0,
  });

  factory CartItem.fromMedicine(Medicine medicine, {int quantity = 1}) {
    final id = medicine.id;
    if (id == null) {
      throw ArgumentError('A cart medicine must already be persisted.');
    }
    return CartItem(
      medicineId: id,
      medicineName: medicine.name,
      sku: medicine.sku,
      branch: medicine.branch,
      quantity: quantity,
      unitPricePaise: medicine.pricePaise,
      discountPercent: 0,
    );
  }

  final int medicineId;
  final String medicineName;
  final String sku;
  final String branch;
  final int quantity;
  final int unitPricePaise;
  final double discountPercent;

  String get name => medicineName;
  int get qty => quantity;
  int get lineGrossPaise => quantity * unitPricePaise;
  int get discountPaise => (lineGrossPaise * discountPercent / 100).round();
  int get lineTotalPaise => lineGrossPaise - discountPaise;

  CartItem copyWith({
    int? medicineId,
    String? medicineName,
    String? sku,
    String? branch,
    int? quantity,
    int? unitPricePaise,
    double? discountPercent,
  }) {
    return CartItem(
      medicineId: medicineId ?? this.medicineId,
      medicineName: medicineName ?? this.medicineName,
      sku: sku ?? this.sku,
      branch: branch ?? this.branch,
      quantity: quantity ?? this.quantity,
      unitPricePaise: unitPricePaise ?? this.unitPricePaise,
      discountPercent: discountPercent ?? this.discountPercent,
    );
  }
}

class InvoiceItem {
  const InvoiceItem({
    this.id,
    this.invoiceId,
    this.medicineId,
    required this.medicineName,
    required this.sku,
    required this.quantity,
    required this.unitPricePaise,
    required this.lineTotalPaise,
    this.discountPercent = 0,
    this.costPaise = 0,
  });

  final int? id;
  final int? invoiceId;
  final int? medicineId;
  final String medicineName;
  final String sku;
  final int quantity;
  final int unitPricePaise;
  final int lineTotalPaise;
  final double discountPercent;
  final int costPaise;

  String get name => medicineName;
  int get qty => quantity;
  int get pricePaise => unitPricePaise;
  int get totalPaise => lineTotalPaise;

  factory InvoiceItem.fromMap(Map<String, Object?> map) {
    return InvoiceItem(
      id: _nullableInt(map['id']),
      invoiceId: _nullableInt(map['invoice_id']),
      medicineId: _nullableInt(map['medicine_id']),
      medicineName: _string(map['medicine_name']),
      sku: _string(map['sku']),
      quantity: _int(map['qty']),
      unitPricePaise: _int(map['price_paise']),
      lineTotalPaise: _int(map['line_total_paise']),
      discountPercent: _double(map['discount_percent']),
      costPaise: _int(map['cost_paise']),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'invoice_id': invoiceId,
      'medicine_id': medicineId,
      'medicine_name': medicineName,
      'sku': sku,
      'qty': quantity,
      'price_paise': unitPricePaise,
      'line_total_paise': lineTotalPaise,
      'discount_percent': discountPercent,
      'cost_paise': costPaise,
    };
  }
}

class InvoiceRecord {
  const InvoiceRecord({
    this.id,
    required this.number,
    required this.customerName,
    required this.customerPhone,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.discountPaise,
    required this.totalPaise,
    required this.createdAt,
    this.doctorName = '',
    this.paymentMethod = 'Cash',
    this.nextRefillDate,
    this.items = const <InvoiceItem>[],
  });

  final int? id;
  final String number;
  final String customerName;
  final String customerPhone;
  final int subtotalPaise;
  final int taxPaise;
  final int discountPaise;
  final int totalPaise;
  final DateTime createdAt;
  final String doctorName;
  final String paymentMethod;
  final DateTime? nextRefillDate;
  final List<InvoiceItem> items;

  int get totalQuantity =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  factory InvoiceRecord.fromMap(
    Map<String, Object?> map, {
    List<InvoiceItem> items = const <InvoiceItem>[],
  }) {
    return InvoiceRecord(
      id: _nullableInt(map['id']),
      number: _string(map['invoice_number']),
      customerName: _string(map['customer_name']),
      customerPhone: _string(map['customer_phone']),
      subtotalPaise: _int(map['subtotal_paise']),
      taxPaise: _int(map['tax_paise']),
      discountPaise: _int(map['discount_paise']),
      totalPaise: _int(map['total_paise']),
      doctorName: _string(map['doctor_name']),
      paymentMethod: _string(map['payment_method']).isEmpty
          ? 'Cash'
          : _string(map['payment_method']),
      nextRefillDate: _nullableDateTime(map['next_refill_date']),
      createdAt:
          _nullableDateTime(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: List<InvoiceItem>.unmodifiable(items),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'invoice_number': number,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'subtotal_paise': subtotalPaise,
      'tax_paise': taxPaise,
      'discount_paise': discountPaise,
      'total_paise': totalPaise,
      'doctor_name': doctorName,
      'payment_method': paymentMethod,
      'next_refill_date': _dateOnly(nextRefillDate),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// A supplier or distributor used by offline purchase records.
class Supplier {
  const Supplier({
    this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.gstNumber = '',
    this.address = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String phone;
  final String email;
  final String gstNumber;
  final String address;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Supplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? gstNumber,
    String? address,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstNumber: gstNumber ?? this.gstNumber,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Supplier.fromMap(Map<String, Object?> map) {
    return Supplier(
      id: _nullableInt(map['id']),
      name: _string(map['name']),
      phone: _string(map['phone']),
      email: _string(map['email']),
      gstNumber: _string(map['gst_number']),
      address: _string(map['address']),
      isActive: _int(map['is_active']) == 1,
      createdAt: _nullableDateTime(map['created_at']),
      updatedAt: _nullableDateTime(map['updated_at']),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'gst_number': gstNumber,
      'address': address,
      'is_active': isActive ? 1 : 0,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

/// One supplier invoice line. Quantities and prices are stored as exact units.
class PurchaseLine {
  const PurchaseLine({
    this.id,
    this.purchaseId,
    this.medicineId,
    required this.productName,
    this.batchNumber = '',
    this.expiryDate,
    this.billedQuantity = 0,
    this.freeQuantity = 0,
    this.mrpPaise = 0,
    this.purchaseRatePaise = 0,
    this.gstPercent = 0,
    this.matchState = 'unmatched',
    this.matchScore = 0,
  });

  final int? id;
  final int? purchaseId;
  final int? medicineId;
  final String productName;
  final String batchNumber;
  final DateTime? expiryDate;
  final int billedQuantity;
  final int freeQuantity;
  final int mrpPaise;
  final int purchaseRatePaise;
  final double gstPercent;
  final String matchState;
  final double matchScore;

  int get receivedQuantity => billedQuantity + freeQuantity;
  int get lineSubtotalPaise => billedQuantity * purchaseRatePaise;
  int get gstPaise => (lineSubtotalPaise * gstPercent / 100).round();
  int get lineTotalPaise => lineSubtotalPaise + gstPaise;
  bool get isMapped => medicineId != null;

  PurchaseLine copyWith({
    int? id,
    int? purchaseId,
    int? medicineId,
    bool clearMedicineId = false,
    String? productName,
    String? batchNumber,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    int? billedQuantity,
    int? freeQuantity,
    int? mrpPaise,
    int? purchaseRatePaise,
    double? gstPercent,
    String? matchState,
    double? matchScore,
  }) {
    return PurchaseLine(
      id: id ?? this.id,
      purchaseId: purchaseId ?? this.purchaseId,
      medicineId: clearMedicineId ? null : (medicineId ?? this.medicineId),
      productName: productName ?? this.productName,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      billedQuantity: billedQuantity ?? this.billedQuantity,
      freeQuantity: freeQuantity ?? this.freeQuantity,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      purchaseRatePaise: purchaseRatePaise ?? this.purchaseRatePaise,
      gstPercent: gstPercent ?? this.gstPercent,
      matchState: matchState ?? this.matchState,
      matchScore: matchScore ?? this.matchScore,
    );
  }

  factory PurchaseLine.fromMap(Map<String, Object?> map) {
    return PurchaseLine(
      id: _nullableInt(map['id']),
      purchaseId: _nullableInt(map['purchase_id']),
      medicineId: _nullableInt(map['medicine_id']),
      productName: _string(map['product_name']),
      batchNumber: _string(map['batch_number']),
      expiryDate: _nullableDateTime(map['expiry_date']),
      billedQuantity: _int(map['billed_quantity']),
      freeQuantity: _int(map['free_quantity']),
      mrpPaise: _int(map['mrp_paise']),
      purchaseRatePaise: _int(map['purchase_rate_paise']),
      gstPercent: _double(map['gst_percent']),
      matchState: _string(map['match_state']),
      matchScore: _double(map['match_score']),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'purchase_id': purchaseId,
      'medicine_id': medicineId,
      'product_name': productName,
      'batch_number': batchNumber,
      'expiry_date': _dateOnly(expiryDate),
      'billed_quantity': billedQuantity,
      'free_quantity': freeQuantity,
      'mrp_paise': mrpPaise,
      'purchase_rate_paise': purchaseRatePaise,
      'gst_percent': gstPercent,
      'match_state': matchState,
      'match_score': matchScore,
    };
  }
}

class PurchaseRecord {
  const PurchaseRecord({
    this.id,
    required this.supplierId,
    this.supplierName = '',
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.branch,
    this.status = 'draft',
    this.lines = const <PurchaseLine>[],
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int supplierId;
  final String supplierName;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String branch;
  final String status;
  final List<PurchaseLine> lines;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get subtotalPaise =>
      lines.fold<int>(0, (sum, line) => sum + line.lineSubtotalPaise);
  int get gstPaise => lines.fold<int>(0, (sum, line) => sum + line.gstPaise);
  int get totalPaise => subtotalPaise + gstPaise;
  bool get isDraft => status == 'draft';
  bool get isCompleted => status == 'completed';

  PurchaseRecord copyWith({
    int? id,
    int? supplierId,
    String? supplierName,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? branch,
    String? status,
    List<PurchaseLine>? lines,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseRecord(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      branch: branch ?? this.branch,
      status: status ?? this.status,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PurchaseRecord.fromMap(
    Map<String, Object?> map, {
    List<PurchaseLine> lines = const <PurchaseLine>[],
  }) {
    return PurchaseRecord(
      id: _nullableInt(map['id']),
      supplierId: _int(map['supplier_id']),
      supplierName: _string(map['supplier_name']),
      invoiceNumber: _string(map['invoice_number']),
      invoiceDate:
          _nullableDateTime(map['invoice_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      branch: _string(map['branch']),
      status: _string(map['status']),
      lines: List<PurchaseLine>.unmodifiable(lines),
      createdAt: _nullableDateTime(map['created_at']),
      updatedAt: _nullableDateTime(map['updated_at']),
    );
  }
}

class MedicineMatch {
  const MedicineMatch({required this.medicine, required this.score});

  final Medicine medicine;
  final double score;
}

class LastPurchaseInfo {
  const LastPurchaseInfo({
    required this.purchaseRatePaise,
    required this.supplierName,
    required this.invoiceDate,
  });

  final int purchaseRatePaise;
  final String supplierName;
  final DateTime invoiceDate;
}

class BranchAvailability {
  const BranchAvailability({
    required this.medicineId,
    required this.medicineName,
    required this.sku,
    required this.branch,
    required this.stock,
    required this.isCurrent,
    this.distanceKm,
  });

  final int medicineId;
  final String medicineName;
  final String sku;
  final String branch;
  final int stock;
  final bool isCurrent;
  final int? distanceKm;

  String get distanceLabel => isCurrent ? 'Current' : '${distanceKm ?? 0} km';
}

class DashboardStats {
  const DashboardStats({
    required this.totalMedicines,
    required this.stockValuePaise,
    required this.lowStockCount,
    required this.totalSalesPaise,
  });

  const DashboardStats.empty()
    : totalMedicines = 0,
      stockValuePaise = 0,
      lowStockCount = 0,
      totalSalesPaise = 0;

  final int totalMedicines;
  final int stockValuePaise;
  final int lowStockCount;
  final int totalSalesPaise;
}

/// Read-only operational statistics for one MediStock branch.
///
/// Monetary values are represented in paise, matching the rest of the data
/// layer and avoiding floating-point rounding errors.
class BranchSummary {
  const BranchSummary({
    required this.name,
    required this.isActive,
    required this.medicineCount,
    required this.totalUnits,
    required this.lowStockCount,
    required this.stockValuePaise,
    required this.activeStaffCount,
    required this.todayCheckIns,
  });

  final String name;
  final bool isActive;
  final int medicineCount;
  final int totalUnits;
  final int lowStockCount;
  final int stockValuePaise;
  final int activeStaffCount;
  final int todayCheckIns;

  String get branch => name;
  bool get active => isActive;
  int get medicinesCount => medicineCount;
  int get medicineRows => medicineCount;
  int get inventoryValuePaise => stockValuePaise;
  int get activeStaff => activeStaffCount;

  factory BranchSummary.fromMap(Map<String, Object?> map) {
    return BranchSummary(
      name: _string(map['branch']),
      isActive: _int(map['is_active']) == 1,
      medicineCount: _int(map['medicine_count']),
      totalUnits: _int(map['total_units']),
      lowStockCount: _int(map['low_stock_count']),
      stockValuePaise: _int(map['stock_value_paise']),
      activeStaffCount: _int(map['active_staff_count']),
      todayCheckIns: _int(map['today_check_ins']),
    );
  }
}

/// Supported four-hour work shifts, beginning at 9:00 AM.
const staffShifts = <String>['A', 'B', 'C'];
const staffShiftHours = <String, String>{
  'A': '9:00 AM - 1:00 PM',
  'B': '1:00 PM - 5:00 PM',
  'C': '5:00 PM - 9:00 PM',
};

/// Public staff profile. Credential hashes and salts deliberately never leave
/// the database layer.
class StaffMember {
  const StaffMember({
    this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.branch,
    this.shift = 'A',
    this.isActive = true,
    this.lastLoginAt,
    this.todayLoginCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String email;
  final String role;
  final String branch;
  final String shift;
  final bool isActive;
  final DateTime? lastLoginAt;
  final int todayLoginCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get active => isActive;
  bool get checkedInToday => todayLoginCount > 0;

  StaffMember copyWith({
    int? id,
    String? name,
    String? email,
    String? role,
    String? branch,
    String? shift,
    bool? isActive,
    DateTime? lastLoginAt,
    bool clearLastLoginAt = false,
    int? todayLoginCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      branch: branch ?? this.branch,
      shift: shift ?? this.shift,
      isActive: isActive ?? this.isActive,
      lastLoginAt: clearLastLoginAt ? null : (lastLoginAt ?? this.lastLoginAt),
      todayLoginCount: todayLoginCount ?? this.todayLoginCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory StaffMember.fromMap(Map<String, Object?> map) {
    return StaffMember(
      id: _nullableInt(map['id']),
      name: _string(map['name']),
      email: _string(map['email']),
      role: _string(map['role']),
      branch: _string(map['branch']),
      shift: map['shift']?.toString() ?? 'A',
      isActive: _int(map['is_active']) == 1,
      lastLoginAt: _nullableDateTime(map['last_login_at']),
      todayLoginCount: _int(map['today_login_count']),
      createdAt: _nullableDateTime(map['created_at']),
      updatedAt: _nullableDateTime(map['updated_at']),
    );
  }
}

String? _dateOnly(DateTime? value) {
  if (value == null) return null;
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _string(Object? value) => value?.toString() ?? '';

int _int(Object? value) => _nullableInt(value) ?? 0;

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
