const VALID_EMAIL = "admin@gmail.com";
const VALID_PASSWORD = "12345678";
const SESSION_KEY = "medistock-authenticated";
const branches = ["Main Branch", "City Branch", "North Branch", "South Branch"];

let medicines = [];
let invoices = [];
let billItems = [];
let lastSavedInvoice = null;
let barcodeScannerStream = null;
let barcodeScanTimer = null;
let barcodeDetector = null;
let isBarcodeScanBusy = false;

const $ = (id) => document.getElementById(id);

const els = {
  loginPage: $("loginPage"),
  loginForm: $("loginForm"),
  loginEmail: $("loginEmail"),
  loginPassword: $("loginPassword"),
  loginError: $("loginError"),
  logoutButton: $("logoutButton"),
  pageTitle: $("pageTitle"),
  saveStatus: $("saveStatus"),
  toast: $("toast"),
  productFormOverlay: $("productFormOverlay"),
  productForm: $("productForm"),
  productId: $("productId"),
  productBarcode: $("productBarcode"),
  productName: $("productName"),
  productGeneric: $("productGeneric"),
  productBrand: $("productBrand"),
  productComposition: $("productComposition"),
  productSku: $("productSku"),
  productManufacturer: $("productManufacturer"),
  productMfgDate: $("productMfgDate"),
  productExpiryDate: $("productExpiryDate"),
  productBranch: $("productBranch"),
  productStock: $("productStock"),
  productThreshold: $("productThreshold"),
  productCost: $("productCost"),
  productPrice: $("productPrice"),
  inventoryTable: $("inventoryTable"),
  inventorySearch: $("inventorySearch"),
  billProduct: $("billProduct"),
  billQty: $("billQty"),
  billTable: $("billTable"),
  customerName: $("customerName"),
  customerPhone: $("customerPhone"),
  taxRate: $("taxRate"),
  discountAmount: $("discountAmount"),
  billSubtotal: $("billSubtotal"),
  billTax: $("billTax"),
  billDiscount: $("billDiscount"),
  billTotal: $("billTotal"),
  invoiceTable: $("invoiceTable"),
  invoiceSearch: $("invoiceSearch"),
  availabilityOverlay: $("availabilityOverlay"),
  availabilityTitle: $("availabilityTitle"),
  availabilitySku: $("availabilitySku"),
  availabilityTable: $("availabilityTable"),
  barcodeScannerOverlay: $("barcodeScannerOverlay"),
  barcodeScannerStatus: $("barcodeScannerStatus"),
  barcodeVideo: $("barcodeVideo"),
  manualBarcode: $("manualBarcode"),
  lowStockList: $("lowStockList"),
  recentInvoices: $("recentInvoices"),
  totalProducts: $("totalProducts"),
  stockValue: $("stockValue"),
  lowStockCount: $("lowStockCount"),
  totalSales: $("totalSales"),
};

const appSections = document.querySelectorAll(".app-auth");
const navButtons = document.querySelectorAll("[data-view]");
const viewJumpButtons = document.querySelectorAll("[data-view-jump]");
const views = document.querySelectorAll(".view");

const viewTitles = {
  dashboard: "Dashboard",
  inventory: "Inventory",
  billing: "Billing",
  invoices: "Invoices",
};

function money(value) {
  return `Rs. ${Number(value || 0).toFixed(2)}`;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.detail || result.error || "Request failed.");
  return result;
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("show");
  window.setTimeout(() => els.toast.classList.remove("show"), 2400);
}

function setStatus(message) {
  els.saveStatus.textContent = message;
}

function showApp() {
  els.loginPage.classList.add("hidden");
  appSections.forEach((section) => section.classList.remove("hidden"));
  showView("dashboard");
  loadAppData();
}

function showLogin() {
  appSections.forEach((section) => section.classList.add("hidden"));
  els.loginPage.classList.remove("hidden");
  els.loginPassword.value = "";
  els.loginEmail.focus();
}

function showView(viewName) {
  views.forEach((view) => view.classList.toggle("active", view.id === `${viewName}View`));
  navButtons.forEach((button) => button.classList.toggle("active", button.dataset.view === viewName));
  els.pageTitle.textContent = viewTitles[viewName] || "Dashboard";
}

function populateBranches() {
  els.productBranch.innerHTML = branches.map((branch) => `<option value="${branch}">${branch}</option>`).join("");
}

async function loadAppData() {
  try {
    setStatus("Connecting to MySQL...");
    const [medicineResult, invoiceResult] = await Promise.all([api("/api/medicines"), api("/api/invoices")]);
    medicines = medicineResult.medicines || [];
    invoices = invoiceResult.invoices || [];
    setStatus("Saved to MySQL");
    renderAll();
  } catch (error) {
    setStatus("Database error");
    showToast(error.message);
    renderAll();
  }
}

function renderAll() {
  renderInventory();
  renderBillProducts();
  renderBill();
  renderInvoices();
  renderDashboard();
}

function getFilteredMedicines() {
  const term = els.inventorySearch.value.trim().toLowerCase();
  if (!term) return medicines;
  return medicines.filter((medicine) =>
    [medicine.name, medicine.sku, medicine.branch, medicine.brand, medicine.generic]
      .join(" ")
      .toLowerCase()
      .includes(term)
  );
}

function quantityClass(medicine) {
  if (medicine.stock <= 0) return "branch-empty";
  if (medicine.stock <= medicine.threshold) return "quantity-critical";
  if (medicine.stock <= medicine.threshold * 2) return "quantity-medium";
  return "quantity-full";
}

function renderInventory() {
  const rows = getFilteredMedicines();
  if (!rows.length) {
    els.inventoryTable.innerHTML = `<tr><td colspan="7"><div class="empty-state">No medicines found.</div></td></tr>`;
    return;
  }

  els.inventoryTable.innerHTML = rows
    .map(
      (medicine) => `
        <tr class="${quantityClass(medicine)}">
          <td>
            <strong>${escapeHtml(medicine.name)}</strong>
            <span class="medicine-meta">${escapeHtml(medicine.generic || medicine.brand || "No generic/brand")}</span>
          </td>
          <td>${escapeHtml(medicine.sku)}</td>
          <td>${escapeHtml(medicine.branch)}</td>
          <td>
            ${medicine.stock}
            ${medicine.stock <= medicine.threshold ? '<span class="low-stock">Low</span>' : ""}
          </td>
          <td>${money(medicine.cost)}</td>
          <td>${money(medicine.price)}</td>
          <td>
            <div class="row-actions">
              <button class="small-button" data-action="availability" data-id="${medicine.id}">View</button>
              <button class="small-button" data-action="edit" data-id="${medicine.id}">Edit</button>
              <button class="small-button" data-action="delete" data-id="${medicine.id}">Delete</button>
            </div>
          </td>
        </tr>`
    )
    .join("");
}

function renderBillProducts() {
  const inStock = medicines.filter((medicine) => medicine.stock > 0);
  els.billProduct.innerHTML = inStock.length
    ? inStock
        .map(
          (medicine) =>
            `<option value="${medicine.id}">${escapeHtml(medicine.name)} - ${escapeHtml(medicine.branch)} (${medicine.stock})</option>`
        )
        .join("")
    : '<option value="">No stock available</option>';
}

function getBillTotals() {
  const subtotal = billItems.reduce((sum, item) => sum + item.qty * item.price, 0);
  const tax = subtotal * (Number(els.taxRate.value || 0) / 100);
  const discount = subtotal * (Number(els.discountAmount.value || 0) / 100);
  const total = Math.max(0, subtotal + tax - discount);
  return { subtotal, tax, discount, total };
}

function renderBill() {
  if (!billItems.length) {
    els.billTable.innerHTML = `<tr><td colspan="5"><div class="empty-state">No bill items added.</div></td></tr>`;
  } else {
    els.billTable.innerHTML = billItems
      .map(
        (item) => `
          <tr>
            <td>${escapeHtml(item.name)}<span class="medicine-meta">${escapeHtml(item.sku)}</span></td>
            <td>${item.qty}</td>
            <td>${money(item.price)}</td>
            <td>${money(item.qty * item.price)}</td>
            <td><button class="small-button" data-remove-bill="${item.medicineId}">Remove</button></td>
          </tr>`
      )
      .join("");
  }

  const totals = getBillTotals();
  els.billSubtotal.textContent = money(totals.subtotal);
  els.billTax.textContent = money(totals.tax);
  els.billDiscount.textContent = money(totals.discount);
  els.billTotal.textContent = money(totals.total);
}

function renderInvoices() {
  const term = els.invoiceSearch.value.trim().toLowerCase();
  const rows = invoices.filter((invoice) =>
    [invoice.number, invoice.customerName, invoice.customerPhone].join(" ").toLowerCase().includes(term)
  );

  if (!rows.length) {
    els.invoiceTable.innerHTML = `<tr><td colspan="6"><div class="empty-state">No invoices found.</div></td></tr>`;
    return;
  }

  els.invoiceTable.innerHTML = rows
    .map((invoice) => {
      const qty = (invoice.items || []).reduce((sum, item) => sum + Number(item.qty || 0), 0);
      return `
        <tr>
          <td>${escapeHtml(invoice.number)}</td>
          <td>${new Date(invoice.createdAt).toLocaleString()}</td>
          <td>${escapeHtml(invoice.customerName || "Walk-in patient")}</td>
          <td>${qty}</td>
          <td>${money(invoice.total)}</td>
          <td><button class="small-button" data-print-invoice="${invoice.id}">Print</button></td>
        </tr>`;
    })
    .join("");
}

function renderDashboard() {
  const lowStock = medicines.filter((medicine) => medicine.stock <= medicine.threshold);
  els.totalProducts.textContent = medicines.length;
  els.stockValue.textContent = money(medicines.reduce((sum, medicine) => sum + medicine.stock * medicine.cost, 0));
  els.lowStockCount.textContent = lowStock.length;
  els.totalSales.textContent = money(invoices.reduce((sum, invoice) => sum + Number(invoice.total || 0), 0));

  els.lowStockList.innerHTML = lowStock.length
    ? lowStock
        .slice(0, 5)
        .map(
          (medicine) => `
            <div class="list-item">
              <div><strong>${escapeHtml(medicine.name)}</strong><span>${escapeHtml(medicine.branch)}</span></div>
              <span>${medicine.stock} left</span>
            </div>`
        )
        .join("")
    : '<div class="empty-state">No low quantity medicines.</div>';

  els.recentInvoices.innerHTML = invoices.length
    ? invoices
        .slice(0, 5)
        .map(
          (invoice) => `
            <div class="list-item">
              <div><strong>${escapeHtml(invoice.number)}</strong><span>${escapeHtml(invoice.customerName || "Walk-in patient")}</span></div>
              <span>${money(invoice.total)}</span>
            </div>`
        )
        .join("")
    : '<div class="empty-state">No invoices yet.</div>';
}

function openProductForm(medicine = null) {
  els.productForm.reset();
  els.productId.value = medicine?.id || "";
  els.productBarcode.value = medicine?.barcode || "";
  els.productName.value = medicine?.name || "";
  els.productGeneric.value = medicine?.generic || "";
  els.productBrand.value = medicine?.brand || "";
  els.productComposition.value = medicine?.composition || "";
  els.productSku.value = medicine?.sku || "";
  els.productManufacturer.value = medicine?.manufacturer || "";
  els.productMfgDate.value = medicine?.mfgDate || "";
  els.productExpiryDate.value = medicine?.expiryDate || "";
  els.productBranch.value = medicine?.branch || branches[0];
  els.productStock.value = medicine?.stock ?? "";
  els.productThreshold.value = medicine?.threshold ?? 10;
  els.productCost.value = medicine?.cost ?? "";
  els.productPrice.value = medicine?.price ?? "";
  els.productFormOverlay.classList.remove("hidden");
  els.productName.focus();
}

function closeProductForm() {
  els.productFormOverlay.classList.add("hidden");
}

function getMedicineFromForm() {
  return {
    barcode: els.productBarcode.value,
    name: els.productName.value,
    generic: els.productGeneric.value,
    brand: els.productBrand.value,
    composition: els.productComposition.value,
    sku: els.productSku.value,
    manufacturer: els.productManufacturer.value,
    mfgDate: els.productMfgDate.value,
    expiryDate: els.productExpiryDate.value,
    branch: els.productBranch.value,
    stock: Number(els.productStock.value),
    threshold: Number(els.productThreshold.value),
    cost: Number(els.productCost.value),
    price: Number(els.productPrice.value),
  };
}

async function saveMedicine(event) {
  event.preventDefault();
  const id = els.productId.value;
  const method = id ? "PUT" : "POST";
  const path = id ? `/api/medicines/${id}` : "/api/medicines";

  try {
    const result = await api(path, { method, body: JSON.stringify(getMedicineFromForm()) });
    closeProductForm();
    if (result.lowStockAlertError) {
      showToast(`${id ? "Medicine updated" : "Medicine saved"}, alert failed: ${result.lowStockAlertError}`);
    } else if (result.lowStockAlerts?.length) {
      showToast(`${id ? "Medicine updated" : "Medicine saved"}. Low-stock WhatsApp alert sent.`);
    } else {
      showToast(id ? "Medicine updated." : "Medicine saved.");
    }
    await loadAppData();
  } catch (error) {
    showToast(error.message);
  }
}

async function deleteMedicine(id) {
  try {
    await api(`/api/medicines/${id}`, { method: "DELETE" });
    billItems = billItems.filter((item) => item.medicineId !== Number(id));
    showToast("Medicine deleted.");
    await loadAppData();
  } catch (error) {
    showToast(error.message);
  }
}

function showAvailability(id) {
  const medicine = medicines.find((item) => item.id === Number(id));
  if (!medicine) return;
  const sameSku = medicines.filter((item) => item.sku.toLowerCase() === medicine.sku.toLowerCase());
  els.availabilityTitle.textContent = medicine.name;
  els.availabilitySku.textContent = `Batch / code: ${medicine.sku}`;
  els.availabilityTable.innerHTML = sameSku
    .map(
      (item, index) => `
        <tr>
          <td>${escapeHtml(item.branch)}</td>
          <td>${index === 0 ? "Current" : `${index + 1} km`}</td>
          <td>${item.stock}</td>
        </tr>`
    )
    .join("");
  els.availabilityOverlay.classList.remove("hidden");
}

function setScannerStatus(message) {
  els.barcodeScannerStatus.textContent = message;
}

function stopBarcodeScanner() {
  if (barcodeScanTimer) {
    window.clearTimeout(barcodeScanTimer);
    barcodeScanTimer = null;
  }
  if (barcodeScannerStream) {
    barcodeScannerStream.getTracks().forEach((track) => track.stop());
    barcodeScannerStream = null;
  }
  els.barcodeVideo.srcObject = null;
  isBarcodeScanBusy = false;
}

function fillMedicineFromLookup(medicine, scannedBarcode) {
  els.productBarcode.value = scannedBarcode || medicine.barcode || "";
  els.productName.value = medicine.name || "";
  els.productGeneric.value = medicine.generic || "";
  els.productBrand.value = medicine.brand || "";
  els.productComposition.value = medicine.composition || "";
  els.productSku.value = medicine.sku || scannedBarcode || "";
  els.productManufacturer.value = medicine.manufacturer || "";
  els.productMfgDate.value = medicine.mfgDate || "";
  els.productExpiryDate.value = medicine.expiryDate || "";
  els.productBranch.value = medicine.branch || branches[0];
  els.productThreshold.value = medicine.threshold ?? 10;
  els.productCost.value = medicine.cost ?? "";
  els.productPrice.value = medicine.price ?? "";
  els.productStock.value = "";
  els.productStock.focus();
}

async function applyBarcodeValue(rawBarcode) {
  const barcode = String(rawBarcode || "").replace(/\D/g, "");
  if (!barcode) {
    setScannerStatus("Enter or scan a valid barcode number.");
    return;
  }

  els.productBarcode.value = barcode;
  setScannerStatus(`Looking up ${barcode}...`);

  const localMatch = medicines.find((medicine) => String(medicine.barcode || "").replace(/\D/g, "") === barcode);
  if (localMatch) {
    fillMedicineFromLookup(localMatch, barcode);
    stopBarcodeScanner();
    els.barcodeScannerOverlay.classList.add("hidden");
    showToast("Medicine details filled. Enter quantity.");
    return;
  }

  try {
    const result = await api(`/api/medicine-lookup/${encodeURIComponent(barcode)}`);
    fillMedicineFromLookup(result.medicine, barcode);
    stopBarcodeScanner();
    els.barcodeScannerOverlay.classList.add("hidden");
    showToast("Medicine details filled. Enter quantity.");
  } catch (error) {
    setScannerStatus(error.message);
    showToast(error.message);
  }
}

async function runBarcodeScanLoop() {
  if (!barcodeDetector || !barcodeScannerStream || isBarcodeScanBusy) return;

  try {
    isBarcodeScanBusy = true;
    const results = await barcodeDetector.detect(els.barcodeVideo);
    const barcode = results[0]?.rawValue;
    if (barcode) {
      await applyBarcodeValue(barcode);
      return;
    }
  } catch (error) {
    setScannerStatus(`Scanner error: ${error.message}`);
  } finally {
    isBarcodeScanBusy = false;
  }

  barcodeScanTimer = window.setTimeout(runBarcodeScanLoop, 350);
}

async function startBarcodeScanner() {
  els.manualBarcode.value = "";
  els.barcodeScannerOverlay.classList.remove("hidden");
  setScannerStatus("Starting camera...");

  if (!("BarcodeDetector" in window)) {
    setScannerStatus("Camera barcode scanning is not supported in this browser. Type the barcode below.");
    return;
  }

  try {
    barcodeDetector =
      barcodeDetector ||
      new BarcodeDetector({
        formats: ["ean_13", "ean_8", "code_128", "code_39", "upc_a", "upc_e", "itf"],
      });
    barcodeScannerStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" } },
      audio: false,
    });
    els.barcodeVideo.srcObject = barcodeScannerStream;
    await els.barcodeVideo.play();
    setScannerStatus("Point the camera at the medicine barcode.");
    runBarcodeScanLoop();
  } catch (error) {
    setScannerStatus(`Camera unavailable: ${error.message}. Type the barcode below.`);
  }
}

function addBillItem() {
  const medicine = medicines.find((item) => item.id === Number(els.billProduct.value));
  const qty = Math.max(1, Number.parseInt(els.billQty.value, 10) || 1);
  if (!medicine) return showToast("Select a medicine.");
  if (qty > medicine.stock) return showToast(`${medicine.name} has only ${medicine.stock} quantity available.`);

  const existing = billItems.find((item) => item.medicineId === medicine.id);
  if (existing) {
    if (existing.qty + qty > medicine.stock) return showToast(`Cannot exceed available quantity ${medicine.stock}.`);
    existing.qty += qty;
  } else {
    billItems.push({
      medicineId: medicine.id,
      name: medicine.name,
      sku: medicine.sku,
      qty,
      price: medicine.price,
    });
  }

  els.billQty.value = 1;
  renderBill();
}

function clearBill() {
  billItems = [];
  lastSavedInvoice = null;
  els.customerName.value = "";
  els.customerPhone.value = "";
  els.taxRate.value = 0;
  els.discountAmount.value = 0;
  renderBill();
}

function currentInvoicePayload(number = "") {
  const totals = getBillTotals();
  return {
    number,
    customerName: els.customerName.value.trim() || "Walk-in patient",
    customerPhone: els.customerPhone.value.trim(),
    items: billItems.map((item) => ({ ...item })),
    ...totals,
  };
}

async function saveInvoice() {
  if (!billItems.length) return showToast("Add at least one bill item.");
  const invoiceToSave = currentInvoicePayload();
  if (!invoiceToSave.customerPhone) return showToast("Enter patient phone number for WhatsApp invoice.");

  try {
    const result = await api("/api/invoices", {
      method: "POST",
      body: JSON.stringify({ invoice: invoiceToSave }),
    });
    lastSavedInvoice = result.invoice;
    showToast("Invoice saved. Sending WhatsApp PDF...");

    try {
      await api("/api/send-invoice-whatsapp", {
        method: "POST",
        body: JSON.stringify({ invoice: lastSavedInvoice, phone: lastSavedInvoice.customerPhone }),
      });
      showToast(result.lowStockAlertError ? `Invoice sent. Alert issue: ${result.lowStockAlertError}` : "Invoice PDF sent on WhatsApp.");
    } catch (whatsappError) {
      showToast(`Invoice saved, WhatsApp failed: ${whatsappError.message}`);
    }

    await loadAppData();
    clearBill();
  } catch (error) {
    showToast(error.message);
  }
}

function printInvoice(invoice = currentInvoicePayload("DRAFT")) {
  const rows = (invoice.items || [])
    .map(
      (item) => `
        <tr>
          <td>${escapeHtml(item.name)}</td>
          <td>${item.qty}</td>
          <td>${money(item.price)}</td>
          <td>${money(item.qty * item.price)}</td>
        </tr>`
    )
    .join("");
  const html = `
    <html>
      <head><title>${escapeHtml(invoice.number || "Invoice")}</title></head>
      <body style="font-family:Arial,sans-serif;padding:28px;color:#18231f">
        <h1>MediStock</h1>
        <h2>${escapeHtml(invoice.number || "Draft Invoice")}</h2>
        <p><strong>Patient:</strong> ${escapeHtml(invoice.customerName || "Walk-in patient")}</p>
        <p><strong>Phone:</strong> ${escapeHtml(invoice.customerPhone || "")}</p>
        <table style="width:100%;border-collapse:collapse;margin-top:20px" border="1" cellpadding="8">
          <thead><tr><th>Medicine</th><th>Qty</th><th>Rate</th><th>Total</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
        <h3 style="text-align:right">Total: ${money(invoice.total)}</h3>
      </body>
    </html>`;
  const printWindow = window.open("", "_blank");
  printWindow.document.write(html);
  printWindow.document.close();
  printWindow.print();
}

async function sendWhatsAppInvoice() {
  const invoice = lastSavedInvoice || currentInvoicePayload("DRAFT");
  const phone = invoice.customerPhone || els.customerPhone.value.trim();
  if (!phone) return showToast("Enter patient phone number first.");
  if (!invoice.items?.length) return showToast("Add bill items first.");

  try {
    await api("/api/send-invoice-whatsapp", {
      method: "POST",
      body: JSON.stringify({ invoice, phone }),
    });
    showToast("WhatsApp invoice sent.");
  } catch (error) {
    showToast(error.message);
  }
}

async function seedData() {
  try {
    await api("/api/seed", { method: "POST" });
    showToast("Sample medicines loaded.");
    await loadAppData();
  } catch (error) {
    showToast(error.message);
  }
}

async function clearData() {
  try {
    await api("/api/data", { method: "DELETE" });
    billItems = [];
    showToast("All data cleared.");
    await loadAppData();
  } catch (error) {
    showToast(error.message);
  }
}

function setupEvents() {
  els.loginForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const email = els.loginEmail.value.trim().toLowerCase();
    const password = els.loginPassword.value;
    if (email === VALID_EMAIL && password === VALID_PASSWORD) {
      els.loginError.textContent = "";
      localStorage.setItem(SESSION_KEY, "true");
      showApp();
      return;
    }
    els.loginError.textContent = "Invalid email or password.";
    els.loginPassword.select();
  });

  els.logoutButton.addEventListener("click", () => {
    localStorage.removeItem(SESSION_KEY);
    showLogin();
  });

  navButtons.forEach((button) => button.addEventListener("click", () => showView(button.dataset.view)));
  viewJumpButtons.forEach((button) => button.addEventListener("click", () => showView(button.dataset.viewJump)));

  $("toggleProductForm").addEventListener("click", () => openProductForm());
  $("closeProductForm").addEventListener("click", closeProductForm);
  $("resetProductForm").addEventListener("click", () => openProductForm());
  els.productForm.addEventListener("submit", saveMedicine);
  els.inventorySearch.addEventListener("input", renderInventory);
  els.invoiceSearch.addEventListener("input", renderInvoices);

  els.inventoryTable.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const id = button.dataset.id;
    if (button.dataset.action === "edit") openProductForm(medicines.find((medicine) => medicine.id === Number(id)));
    if (button.dataset.action === "delete") deleteMedicine(id);
    if (button.dataset.action === "availability") showAvailability(id);
  });

  $("closeAvailability").addEventListener("click", () => els.availabilityOverlay.classList.add("hidden"));
  $("scanMedicineBarcode").addEventListener("click", startBarcodeScanner);
  $("closeBarcodeScanner").addEventListener("click", () => {
    stopBarcodeScanner();
    els.barcodeScannerOverlay.classList.add("hidden");
  });
  $("applyManualBarcode").addEventListener("click", () => {
    applyBarcodeValue(els.manualBarcode.value);
  });
  els.manualBarcode.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      applyBarcodeValue(els.manualBarcode.value);
    }
  });

  $("addBillItem").addEventListener("click", addBillItem);
  $("clearBill").addEventListener("click", clearBill);
  $("saveInvoice").addEventListener("click", saveInvoice);
  $("printInvoice").addEventListener("click", () => printInvoice());
  $("whatsappInvoice").addEventListener("click", sendWhatsAppInvoice);
  els.taxRate.addEventListener("input", renderBill);
  els.discountAmount.addEventListener("input", renderBill);
  els.billTable.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-remove-bill]");
    if (!button) return;
    billItems = billItems.filter((item) => item.medicineId !== Number(button.dataset.removeBill));
    renderBill();
  });

  els.invoiceTable.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-print-invoice]");
    if (!button) return;
    const invoice = invoices.find((item) => item.id === Number(button.dataset.printInvoice));
    if (invoice) printInvoice(invoice);
  });

  $("seedDataButton").addEventListener("click", seedData);
  $("clearDataButton").addEventListener("click", clearData);
}

populateBranches();
setupEvents();
renderAll();

if (localStorage.getItem(SESSION_KEY) === "true") {
  showApp();
} else {
  showLogin();
}
