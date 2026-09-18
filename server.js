require("dotenv").config();

const express = require("express");
const fs = require("fs");
const path = require("path");
const twilio = require("twilio");
const mysql = require("mysql2/promise");

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(express.json({ limit: "15mb" }));
app.use(express.static(__dirname));

const invoicePdfDir = path.join(__dirname, "generated-invoices");
fs.mkdirSync(invoicePdfDir, { recursive: true });
app.use("/generated-invoices", express.static(invoicePdfDir));

const dbConfig = {
  host: process.env.MYSQL_HOST || "localhost",
  port: Number(process.env.MYSQL_PORT || 3307),
  user: process.env.MYSQL_USER || "root",
  password: process.env.MYSQL_PASSWORD || "",
  database: process.env.MYSQL_DATABASE || "medistock",
  waitForConnections: true,
  connectionLimit: 10,
};

let pool;

async function initDatabase() {
  const bootstrap = await mysql.createConnection({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
  });

  await bootstrap.query(
    `CREATE DATABASE IF NOT EXISTS \`${dbConfig.database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
  );
  await bootstrap.end();

  pool = mysql.createPool(dbConfig);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS medicines (
      id INT AUTO_INCREMENT PRIMARY KEY,
      barcode VARCHAR(120) DEFAULT '',
      name VARCHAR(255) NOT NULL,
      generic_name VARCHAR(255) DEFAULT '',
      brand_name VARCHAR(255) DEFAULT '',
      composition TEXT,
      sku VARCHAR(120) NOT NULL,
      manufacturer VARCHAR(255) DEFAULT '',
      mfg_date DATE NULL,
      expiry_date DATE NULL,
      branch VARCHAR(120) NOT NULL,
      stock INT NOT NULL DEFAULT 0,
      threshold_qty INT NOT NULL DEFAULT 0,
      cost DECIMAL(10,2) NOT NULL DEFAULT 0,
      price DECIMAL(10,2) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_sku (sku),
      INDEX idx_name (name),
      INDEX idx_branch (branch)
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS invoices (
      id INT AUTO_INCREMENT PRIMARY KEY,
      invoice_number VARCHAR(80) NOT NULL UNIQUE,
      customer_name VARCHAR(255) DEFAULT '',
      customer_phone VARCHAR(30) DEFAULT '',
      subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
      tax DECIMAL(10,2) NOT NULL DEFAULT 0,
      discount DECIMAL(10,2) NOT NULL DEFAULT 0,
      total DECIMAL(10,2) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS invoice_items (
      id INT AUTO_INCREMENT PRIMARY KEY,
      invoice_id INT NOT NULL,
      medicine_id INT NULL,
      medicine_name VARCHAR(255) NOT NULL,
      sku VARCHAR(120) DEFAULT '',
      qty INT NOT NULL,
      price DECIMAL(10,2) NOT NULL DEFAULT 0,
      line_total DECIMAL(10,2) NOT NULL DEFAULT 0,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
      FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE SET NULL
    )
  `);
}

const dbReady = initDatabase().catch((error) => {
  console.error("MySQL database initialization failed:", error.message);
  throw error;
});

async function requireDb(_req, res, next) {
  try {
    await dbReady;
    next();
  } catch (error) {
    res.status(500).json({
      error: "Database connection failed.",
      detail: `Check XAMPP MySQL is running on ${dbConfig.host}:${dbConfig.port} and verify .env credentials.`,
    });
  }
}

function toDbDate(value) {
  return value ? String(value).slice(0, 10) : null;
}

function mapMedicine(row) {
  return {
    id: row.id,
    barcode: row.barcode || "",
    name: row.name || "",
    generic: row.generic_name || "",
    brand: row.brand_name || "",
    composition: row.composition || "",
    sku: row.sku || "",
    manufacturer: row.manufacturer || "",
    mfgDate: row.mfg_date ? row.mfg_date.toISOString().slice(0, 10) : "",
    expiryDate: row.expiry_date ? row.expiry_date.toISOString().slice(0, 10) : "",
    branch: row.branch || "",
    stock: Number(row.stock || 0),
    threshold: Number(row.threshold_qty || 0),
    cost: Number(row.cost || 0),
    price: Number(row.price || 0),
  };
}

function normalizeMedicine(body) {
  return {
    barcode: String(body.barcode || "").trim(),
    name: String(body.name || "").trim(),
    generic: String(body.generic || "").trim(),
    brand: String(body.brand || "").trim(),
    composition: String(body.composition || "").trim(),
    sku: String(body.sku || "").trim(),
    manufacturer: String(body.manufacturer || "").trim(),
    mfgDate: toDbDate(body.mfgDate),
    expiryDate: toDbDate(body.expiryDate),
    branch: String(body.branch || "").trim(),
    stock: Math.max(0, Number.parseInt(body.stock, 10) || 0),
    threshold: Math.max(0, Number.parseInt(body.threshold, 10) || 0),
    cost: Math.max(0, Number(body.cost || 0)),
    price: Math.max(0, Number(body.price || 0)),
  };
}

function getTwilioClient() {
  const { TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN } = process.env;

  if (
    !TWILIO_ACCOUNT_SID ||
    !TWILIO_AUTH_TOKEN ||
    TWILIO_ACCOUNT_SID.includes("xxxx") ||
    TWILIO_AUTH_TOKEN.includes("your_") ||
    TWILIO_AUTH_TOKEN.includes("[")
  ) {
    throw new Error("Twilio credentials are missing.");
  }

  return twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN);
}

function normalizeWhatsAppNumber(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  if (raw.startsWith("whatsapp:+")) return raw;

  const digits = raw.replace(/\D/g, "");
  if (!digits) return "";
  const withCountryCode = digits.length === 10 ? `91${digits}` : digits;

  return `whatsapp:+${withCountryCode}`;
}

function normalizeCloudWhatsAppNumber(value) {
  const digits = String(value || "").replace(/\D/g, "");
  if (!digits) return "";
  return digits.length === 10 ? `91${digits}` : digits;
}

function hasWhatsAppCloudConfig() {
  const token = String(process.env.WHATSAPP_TOKEN || "");
  const phoneNumberId = String(process.env.WHATSAPP_PHONE_NUMBER_ID || "");
  return (
    token &&
    phoneNumberId &&
    !token.includes("replace_with") &&
    !phoneNumberId.includes("replace_with")
  );
}

async function graphPost(pathname, body, headers) {
  const apiVersion = process.env.WHATSAPP_API_VERSION || "v20.0";
  const response = await fetch(`https://graph.facebook.com/${apiVersion}/${pathname}`, {
    method: "POST",
    headers,
    body,
  });
  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    const detail = result.error?.message || JSON.stringify(result) || response.statusText;
    throw new Error(detail);
  }

  return result;
}

async function sendInvoiceWithWhatsAppCloud({ phone, pdfBase64, fileName, message }) {
  const token = process.env.WHATSAPP_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const to = normalizeCloudWhatsAppNumber(phone);

  if (!to) {
    throw new Error("Customer WhatsApp number is missing.");
  }
  if (!pdfBase64) {
    throw new Error("Invoice PDF data is missing.");
  }

  const pdfBuffer = Buffer.from(pdfBase64, "base64");
  const formData = new FormData();
  formData.append("messaging_product", "whatsapp");
  formData.append("type", "application/pdf");
  formData.append("file", new Blob([pdfBuffer], { type: "application/pdf" }), fileName);

  const media = await graphPost(`${phoneNumberId}/media`, formData, {
    Authorization: `Bearer ${token}`,
  });

  const whatsapp = await graphPost(
    `${phoneNumberId}/messages`,
    JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "document",
      document: {
        id: media.id,
        filename: fileName,
        caption: message,
      },
    }),
    {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    }
  );

  return { mediaId: media.id, whatsapp };
}

function sendTwilioError(res, label, error) {
  console.error(`${label}:`, error.message);
  return res.status(500).json({
    error: label,
    detail: error.message,
    code: error.code,
    moreInfo: error.moreInfo,
  });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getTwilioDeliveryDetail(message) {
  if (message.errorCode === 63015) {
    return "Twilio WhatsApp sandbox blocked this number. The customer must join your Twilio WhatsApp sandbox first, or you must use an approved WhatsApp Business sender.";
  }

  if (message.errorCode) {
    return `Twilio returned WhatsApp error ${message.errorCode}.`;
  }

  return "";
}

function escapePdfText(value) {
  return String(value || "")
    .replace(/\\/g, "\\\\")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)")
    .replace(/[^\x20-\x7E]/g, "");
}

function buildInvoicePdf(invoice) {
  const formatAmount = (value) => `Rs. ${Number(value || 0).toFixed(2)}`;
  const items = Array.isArray(invoice.items) ? invoice.items : [];
  const invoiceNumber = invoice.number || "DRAFT";
  const invoiceDate = new Date(invoice.createdAt || Date.now()).toLocaleString("en-IN");
  const content = [];

  const text = (value, x, y, size = 11, font = "F1") => {
    content.push(`BT /${font} ${size} Tf ${x} ${y} Td (${escapePdfText(value)}) Tj ET`);
  };
  const line = (x1, y1, x2, y2, width = 1) => {
    content.push(`${width} w ${x1} ${y1} m ${x2} ${y2} l S`);
  };

  text("MediStock", 50, 720, 26, "F2");
  text("Pharmacy inventory and billing", 50, 700, 12);
  text(invoiceNumber, 435, 725, 20, "F2");
  text(invoiceDate, 435, 707, 11);
  line(50, 680, 560, 680, 1.4);

  text("Patient", 50, 650, 12, "F2");
  text(invoice.customerName || "Walk-in patient", 50, 633, 11);
  text(invoice.customerPhone || "", 50, 616, 11);

  text("Item", 58, 580, 12, "F2");
  text("Qty", 200, 580, 12, "F2");
  text("Rate", 315, 580, 12, "F2");
  text("Total", 460, 580, 12, "F2");
  line(50, 565, 560, 565, 0.6);

  let rowY = 545;
  items.forEach((item) => {
    const amount = Number(item.qty || 0) * Number(item.price || 0);
    text(item.name || "", 58, rowY, 11);
    text(String(item.qty || 0), 200, rowY, 11);
    text(formatAmount(item.price), 315, rowY, 11);
    text(formatAmount(amount), 460, rowY, 11);
    line(50, rowY - 14, 560, rowY - 14, 0.3);
    rowY -= 28;
  });

  const totalsTop = Math.min(rowY - 20, 505);
  text("Subtotal", 345, totalsTop, 12);
  text(formatAmount(invoice.subtotal), 505, totalsTop, 12, "F2");
  text("Tax", 345, totalsTop - 24, 12);
  text(formatAmount(invoice.tax), 505, totalsTop - 24, 12, "F2");
  text("Discount", 345, totalsTop - 48, 12);
  text(formatAmount(invoice.discount), 505, totalsTop - 48, 12, "F2");
  line(345, totalsTop - 60, 560, totalsTop - 60, 0.8);
  text("Total", 345, totalsTop - 85, 18, "F2");
  text(formatAmount(invoice.total), 500, totalsTop - 85, 18, "F2");

  const streamText = content.join("\n");
  const stream = `<< /Length ${Buffer.byteLength(streamText)} >>\nstream\n${streamText}\nendstream`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
    stream,
  ];

  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });

  const xrefOffset = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  offsets.slice(1).forEach((offset) => {
    pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  });
  pdf += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;

  return Buffer.from(pdf);
}

function getPublicBaseUrl() {
  const baseUrl = String(process.env.APP_BASE_URL || "").trim().replace(/\/$/, "");
  if (!baseUrl || baseUrl.includes("localhost") || baseUrl.includes("127.0.0.1")) return "";
  return baseUrl;
}

function buildLowStockMessage(medicine, branchRows) {
  const otherBranches = branchRows.filter((row) => row.id !== medicine.id);
  const otherBranchText = otherBranches.length
    ? otherBranches.map((row) => `${row.branch}: ${row.stock}`).join("\n")
    : "No other branch stock found.";

  return [
    "MediStock low stock alert",
    "",
    `Medicine name: ${medicine.name}`,
    `Stock quantity low: ${medicine.stock}`,
    `Branch name where stock is low: ${medicine.branch}`,
    "",
    "Other branch availability:",
    otherBranchText,
  ].join("\n");
}

async function sendLowStockAlertsForMedicineIds(medicineIds) {
  const uniqueIds = [...new Set(medicineIds.map((id) => Number(id)).filter(Boolean))];
  if (!uniqueIds.length) return [];

  const [lowRows] = await pool.query(
    `SELECT * FROM medicines
     WHERE id IN (?) AND stock <= threshold_qty`,
    [uniqueIds]
  );
  if (!lowRows.length) return [];

  const from = process.env.TWILIO_WHATSAPP_FROM;
  const to = process.env.LOW_STOCK_WHATSAPP_TO || process.env.TWILIO_WHATSAPP_FROM;
  if (!from || !to) throw new Error("Low-stock WhatsApp sender or receiver number is missing.");

  const client = getTwilioClient();
  const sent = [];

  for (const medicine of lowRows) {
    const [branchRows] = await pool.query(
      `SELECT id, branch, stock FROM medicines
       WHERE sku = ?
       ORDER BY branch ASC`,
      [medicine.sku]
    );

    const message = await client.messages.create({
      from,
      to,
      body: buildLowStockMessage(medicine, branchRows),
    });
    sent.push({ medicineId: medicine.id, sid: message.sid });
  }

  return sent;
}

async function trySendLowStockAlerts(medicineIds, label) {
  try {
    return { alerts: await sendLowStockAlertsForMedicineIds(medicineIds), error: "" };
  } catch (error) {
    console.error(`${label}:`, error.message);
    return { alerts: [], error: error.message };
  }
}

app.get("/api/health", requireDb, (_req, res) => {
  res.json({ ok: true, database: dbConfig.database, port: dbConfig.port });
});

app.get("/api/medicines", requireDb, async (_req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM medicines ORDER BY updated_at DESC, id DESC");
    res.json({ medicines: rows.map(mapMedicine) });
  } catch (error) {
    res.status(500).json({ error: "Unable to load medicines.", detail: error.message });
  }
});

app.get("/api/medicine-lookup/:barcode", requireDb, async (req, res) => {
  try {
    const barcode = String(req.params.barcode || "").replace(/\D/g, "");
    if (!barcode) return res.status(400).json({ error: "Barcode is required." });

    const [rows] = await pool.query(
      `SELECT * FROM medicines
       WHERE REPLACE(REPLACE(REPLACE(barcode, ' ', ''), '-', ''), '.', '') = ?
       ORDER BY updated_at DESC, id DESC
       LIMIT 1`,
      [barcode]
    );

    if (!rows.length) {
      return res.status(404).json({
        error: "No saved medicine found for this barcode. Save this medicine once, then future scans can auto-fill it.",
      });
    }

    return res.json({ medicine: mapMedicine(rows[0]) });
  } catch (error) {
    return res.status(500).json({ error: "Unable to look up barcode.", detail: error.message });
  }
});

app.post("/api/medicines", requireDb, async (req, res) => {
  try {
    const medicine = normalizeMedicine(req.body);
    if (!medicine.name || !medicine.sku || !medicine.branch) {
      return res.status(400).json({ error: "Medicine name, batch/code, and branch are required." });
    }

    const [result] = await pool.query(
      `INSERT INTO medicines
       (barcode, name, generic_name, brand_name, composition, sku, manufacturer, mfg_date, expiry_date, branch, stock, threshold_qty, cost, price)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        medicine.barcode,
        medicine.name,
        medicine.generic,
        medicine.brand,
        medicine.composition,
        medicine.sku,
        medicine.manufacturer,
        medicine.mfgDate,
        medicine.expiryDate,
        medicine.branch,
        medicine.stock,
        medicine.threshold,
        medicine.cost,
        medicine.price,
      ]
    );

    const [rows] = await pool.query("SELECT * FROM medicines WHERE id = ?", [result.insertId]);
    const savedMedicine = mapMedicine(rows[0]);
    const alertResult =
      savedMedicine.stock <= savedMedicine.threshold
        ? await trySendLowStockAlerts([savedMedicine.id], "Low-stock WhatsApp alert failed")
        : { alerts: [], error: "" };

    res.status(201).json({
      medicine: savedMedicine,
      lowStockAlerts: alertResult.alerts,
      lowStockAlertError: alertResult.error,
    });
  } catch (error) {
    res.status(500).json({ error: "Unable to save medicine.", detail: error.message });
  }
});

app.put("/api/medicines/:id", requireDb, async (req, res) => {
  try {
    const medicine = normalizeMedicine(req.body);
    if (!medicine.name || !medicine.sku || !medicine.branch) {
      return res.status(400).json({ error: "Medicine name, batch/code, and branch are required." });
    }

    const [existingRows] = await pool.query("SELECT * FROM medicines WHERE id = ?", [req.params.id]);
    if (!existingRows.length) return res.status(404).json({ error: "Medicine not found." });
    const previousMedicine = mapMedicine(existingRows[0]);

    await pool.query(
      `UPDATE medicines SET
       barcode = ?, name = ?, generic_name = ?, brand_name = ?, composition = ?, sku = ?,
       manufacturer = ?, mfg_date = ?, expiry_date = ?, branch = ?, stock = ?,
       threshold_qty = ?, cost = ?, price = ?
       WHERE id = ?`,
      [
        medicine.barcode,
        medicine.name,
        medicine.generic,
        medicine.brand,
        medicine.composition,
        medicine.sku,
        medicine.manufacturer,
        medicine.mfgDate,
        medicine.expiryDate,
        medicine.branch,
        medicine.stock,
        medicine.threshold,
        medicine.cost,
        medicine.price,
        req.params.id,
      ]
    );

    const [rows] = await pool.query("SELECT * FROM medicines WHERE id = ?", [req.params.id]);
    const savedMedicine = mapMedicine(rows[0]);
    const isLow = savedMedicine.stock <= savedMedicine.threshold;
    const alertResult =
      isLow
        ? await trySendLowStockAlerts([savedMedicine.id], "Low-stock WhatsApp alert failed")
        : { alerts: [], error: "" };

    res.json({
      medicine: savedMedicine,
      lowStockAlerts: alertResult.alerts,
      lowStockAlertError: alertResult.error,
    });
  } catch (error) {
    res.status(500).json({ error: "Unable to update medicine.", detail: error.message });
  }
});

app.delete("/api/medicines/:id", requireDb, async (req, res) => {
  try {
    await pool.query("DELETE FROM medicines WHERE id = ?", [req.params.id]);
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: "Unable to delete medicine.", detail: error.message });
  }
});

app.post("/api/seed", requireDb, async (_req, res) => {
  try {
    const samples = [
      ["8901234560011", "Paracetamol 500mg Tablets", "Paracetamol", "Dolo", "Paracetamol IP 500mg", "PCM500-A1", "Micro Labs", "2026-01-01", "2027-01-01", "Main Branch", 120, 25, 1.2, 2.5],
      ["8901234560028", "Amoxicillin 500mg Capsules", "Amoxicillin", "Mox", "Amoxicillin 500mg", "AMX500-B2", "Cipla", "2026-02-01", "2027-02-01", "Main Branch", 18, 20, 4.5, 8],
      ["8901234560035", "Cetirizine 10mg Tablets", "Cetirizine", "Cetzine", "Cetirizine 10mg", "CTZ10-C1", "Dr Reddy", "2026-03-01", "2028-03-01", "City Branch", 75, 15, 0.8, 1.5],
      ["8901234560042", "Pantoprazole 40mg Tablets", "Pantoprazole", "Pan-D", "Pantoprazole 40mg", "PAN40-D4", "Sun Pharma", "2026-01-15", "2027-09-15", "North Branch", 9, 15, 3, 6],
    ];

    await pool.query(
      `INSERT INTO medicines
       (barcode, name, generic_name, brand_name, composition, sku, manufacturer, mfg_date, expiry_date, branch, stock, threshold_qty, cost, price)
       VALUES ?`,
      [samples]
    );
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: "Unable to load sample data.", detail: error.message });
  }
});

app.delete("/api/data", requireDb, async (_req, res) => {
  try {
    await pool.query("DELETE FROM invoice_items");
    await pool.query("DELETE FROM invoices");
    await pool.query("DELETE FROM medicines");
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: "Unable to clear data.", detail: error.message });
  }
});

app.get("/api/invoices", requireDb, async (_req, res) => {
  try {
    const [invoices] = await pool.query("SELECT * FROM invoices ORDER BY created_at DESC, id DESC");
    const [items] = await pool.query("SELECT * FROM invoice_items ORDER BY id ASC");
    const itemsByInvoice = new Map();

    items.forEach((item) => {
      const list = itemsByInvoice.get(item.invoice_id) || [];
      list.push({
        id: item.id,
        medicineId: item.medicine_id,
        name: item.medicine_name,
        sku: item.sku,
        qty: Number(item.qty || 0),
        price: Number(item.price || 0),
        total: Number(item.line_total || 0),
      });
      itemsByInvoice.set(item.invoice_id, list);
    });

    res.json({
      invoices: invoices.map((invoice) => ({
        id: invoice.id,
        number: invoice.invoice_number,
        customerName: invoice.customer_name || "",
        customerPhone: invoice.customer_phone || "",
        subtotal: Number(invoice.subtotal || 0),
        tax: Number(invoice.tax || 0),
        discount: Number(invoice.discount || 0),
        total: Number(invoice.total || 0),
        createdAt: invoice.created_at,
        items: itemsByInvoice.get(invoice.id) || [],
      })),
    });
  } catch (error) {
    res.status(500).json({ error: "Unable to load invoices.", detail: error.message });
  }
});

app.post("/api/invoices", requireDb, async (req, res) => {
  const connection = await pool.getConnection();

  try {
    const invoice = req.body.invoice || {};
    const items = Array.isArray(invoice.items) ? invoice.items : [];
    if (!items.length) return res.status(400).json({ error: "Add at least one bill item." });

    await connection.beginTransaction();

    for (const item of items) {
      const [rows] = await connection.query("SELECT id, name, sku, stock, price FROM medicines WHERE id = ? FOR UPDATE", [
        item.medicineId,
      ]);
      const medicine = rows[0];
      if (!medicine) throw new Error(`Medicine not found for ${item.name || "bill item"}.`);
      if (Number(medicine.stock) < Number(item.qty)) {
        throw new Error(`${medicine.name} has only ${medicine.stock} quantity available.`);
      }
    }

    const invoiceNumber = `INV-${Date.now()}`;
    const [result] = await connection.query(
      `INSERT INTO invoices (invoice_number, customer_name, customer_phone, subtotal, tax, discount, total)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        invoiceNumber,
        String(invoice.customerName || "Walk-in patient").trim(),
        String(invoice.customerPhone || "").trim(),
        Number(invoice.subtotal || 0),
        Number(invoice.tax || 0),
        Number(invoice.discount || 0),
        Number(invoice.total || 0),
      ]
    );

    const billedMedicineIds = [];

    for (const item of items) {
      await connection.query("UPDATE medicines SET stock = stock - ? WHERE id = ?", [Number(item.qty), item.medicineId]);
      billedMedicineIds.push(item.medicineId);
      await connection.query(
        `INSERT INTO invoice_items (invoice_id, medicine_id, medicine_name, sku, qty, price, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          result.insertId,
          item.medicineId,
          item.name,
          item.sku || "",
          Number(item.qty),
          Number(item.price),
          Number(item.qty) * Number(item.price),
        ]
      );
    }

    await connection.commit();
    const savedInvoice = { ...invoice, id: result.insertId, number: invoiceNumber, createdAt: new Date() };
    let lowStockAlerts = [];
    let lowStockAlertError = "";

    const alertResult = await trySendLowStockAlerts(billedMedicineIds, "Low-stock WhatsApp alert failed");
    lowStockAlerts = alertResult.alerts;
    lowStockAlertError = alertResult.error;

    res.status(201).json({ invoice: savedInvoice, lowStockAlerts, lowStockAlertError });
  } catch (error) {
    await connection.rollback();
    res.status(400).json({ error: "Unable to save invoice.", detail: error.message });
  } finally {
    connection.release();
  }
});

app.post("/api/low-stock-alert", async (req, res) => {
  try {
    await dbReady;
    const medicineIds = Array.isArray(req.body.medicineIds)
      ? req.body.medicineIds
      : Array.isArray(req.body.medicines)
        ? req.body.medicines.map((medicine) => medicine.id)
        : [];

    if (!medicineIds.length) {
      return res.status(400).json({ error: "No low-stock medicines were provided." });
    }

    const messages = await sendLowStockAlertsForMedicineIds(medicineIds);
    return res.json({ ok: true, messages });
  } catch (error) {
    return sendTwilioError(res, "Unable to send WhatsApp alert.", error);
  }
});

app.post("/api/send-invoice-whatsapp", async (req, res) => {
  try {
    const invoice = req.body.invoice || {};
    const phone = req.body.phone || invoice.customerPhone;
    const fileName = String(
      req.body.fileName || `${String(invoice.number || `invoice-${Date.now()}`).replace(/[^a-z0-9-]/gi, "-")}.pdf`
    ).replace(/[\\/:*?"<>|]/g, "-");
    const message =
      req.body.message ||
      `MediStock bill ${invoice.number || "N/A"}: Rs. ${Number(invoice.total || 0).toFixed(
        2
      )}. Please find your bill PDF attached.`;

    if (hasWhatsAppCloudConfig()) {
      const pdfBase64 = req.body.pdfBase64 || buildInvoicePdf(invoice).toString("base64");
      const cloudResult = await sendInvoiceWithWhatsAppCloud({
        phone,
        pdfBase64,
        fileName,
        message,
      });

      return res.json({ ok: true, provider: "whatsapp-cloud", ...cloudResult });
    }

    const to = normalizeWhatsAppNumber(phone);
    const from = process.env.TWILIO_WHATSAPP_FROM;
    const publicBaseUrl = getPublicBaseUrl();

    if (!from || !to) {
      return res.status(400).json({ error: "Customer WhatsApp number is missing." });
    }

    if (!publicBaseUrl) {
      return res.status(400).json({
        error: "Invoice PDF needs a public APP_BASE_URL.",
        detail: "Set APP_BASE_URL to a public https URL so Twilio can download the PDF attachment.",
      });
    }

    const items = Array.isArray(invoice.items) ? invoice.items : [];
    if (!items.length) {
      return res.status(400).json({ error: "Invoice has no bill items." });
    }

    const formatAmount = (value) => `Rs. ${Number(value || 0).toFixed(2)}`;
    const body = [
      "MediStock Pharmacy Bill",
      `Invoice: ${invoice.number || "N/A"}`,
      `Customer: ${invoice.customerName || "Walk-in patient"}`,
      "",
      "Medicines:",
      ...items.map(
        (item) =>
          `${item.name} - Qty: ${item.qty} x ${formatAmount(item.price)} = ${formatAmount(
            Number(item.qty || 0) * Number(item.price || 0)
          )}`
      ),
      "",
      `Subtotal: ${formatAmount(invoice.subtotal)}`,
      `Tax: ${formatAmount(invoice.tax)}`,
      `Discount: ${formatAmount(invoice.discount)}`,
      `Total: ${formatAmount(invoice.total)}`,
      "",
      "Thank you for choosing MediStock.",
    ].join("\n");

    const filePath = path.join(invoicePdfDir, fileName);
    fs.writeFileSync(
      filePath,
      req.body.pdfBase64 ? Buffer.from(req.body.pdfBase64, "base64") : buildInvoicePdf(invoice)
    );

    const client = getTwilioClient();
    const twilioMessage = await client.messages.create({
      from,
      to,
      body,
      mediaUrl: [`${publicBaseUrl}/generated-invoices/${fileName}`],
    });
    await wait(2500);
    const delivery = await client.messages(twilioMessage.sid).fetch();

    if (["failed", "undelivered"].includes(delivery.status)) {
      return res.status(502).json({
        error: "WhatsApp message was not delivered.",
        detail: getTwilioDeliveryDetail(delivery),
        provider: "twilio",
        status: delivery.status,
        code: delivery.errorCode,
        sid: delivery.sid,
      });
    }

    return res.json({
      ok: true,
      provider: "twilio",
      status: delivery.status,
      sid: delivery.sid,
      pdfUrl: `${publicBaseUrl}/generated-invoices/${fileName}`,
    });
  } catch (error) {
    return sendTwilioError(res, "Unable to send invoice WhatsApp.", error);
  }
});

app.get("*", (_req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

async function startNgrokTunnel() {
  if (getPublicBaseUrl()) {
    console.log(`Public invoice PDF URL configured at ${getPublicBaseUrl()}`);
    return;
  }

  const authtoken = String(process.env.NGROK_AUTHTOKEN || "").trim();
  if (!authtoken) return;

  try {
    const ngrok = require("ngrok");
    const url = await ngrok.connect({ addr: port, authtoken });
    process.env.APP_BASE_URL = url;
    console.log(`Public invoice PDF URL ready at ${url}`);
  } catch (error) {
    console.error("ngrok tunnel could not be started:", error.message);
  }
}

app.listen(port, () => {
  console.log(`MediStock running at http://localhost:${port}`);
  startNgrokTunnel();
});
