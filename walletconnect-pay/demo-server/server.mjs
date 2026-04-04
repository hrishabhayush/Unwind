import "dotenv/config";
import express from "express";
import QRCode from "qrcode";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { createPublicClient, createWalletClient, http, keccak256, toBytes } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { REFUND_PROTOCOL_ABI } from "./constants/refundProtocolAbi.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const API_BASE = process.env.WCP_API_BASE || "https://api.pay.walletconnect.com";
const API_KEY = process.env.WCP_API_KEY;
const MERCHANT_ID = process.env.WCP_MERCHANT_ID;

const app = express();

// CORS so the RN/web app can call this server
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.header("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

app.use(express.json());
app.use(express.static(join(__dirname, "public")));

function wcpHeaders() {
  return {
    "Content-Type": "application/json",
    "Api-Key": API_KEY,
    "Merchant-Id": MERCHANT_ID,
  };
}

app.post("/api/payments", async (req, res) => {
  if (!API_KEY || !MERCHANT_ID) {
    return res.status(500).json({
      error: "Set WCP_API_KEY and WCP_MERCHANT_ID in .env (see .env.example)",
    });
  }

  let centsNum;
  if (req.body?.amountCents != null && req.body.amountCents !== "") {
    centsNum = Number(req.body.amountCents);
  } else {
    centsNum = Math.round(Number(req.body?.amountUsd ?? 1) * 100);
  }
  if (!Number.isFinite(centsNum) || centsNum < 1) centsNum = 100;
  const cents = String(centsNum);
  const referenceId =
    req.body?.referenceId || `demo-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

  try {
    const wcpRes = await fetch(`${API_BASE}/v1/payments`, {
      method: "POST",
      headers: wcpHeaders(),
      body: JSON.stringify({
        referenceId,
        amount: { value: cents, unit: "iso4217/USD" },
      }),
    });

    const text = await wcpRes.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      data = { raw: text };
    }

    if (!wcpRes.ok) {
      return res.status(wcpRes.status).json(data);
    }

    const { paymentId, gatewayUrl, status, expiresAt, pollInMs, isFinal } = data;
    let qrDataUrl = null;
    if (gatewayUrl) {
      qrDataUrl = await QRCode.toDataURL(gatewayUrl, { width: 280, margin: 2 });
    }

    return res.json({
      paymentId,
      gatewayUrl,
      status,
      expiresAt,
      pollInMs,
      isFinal,
      referenceId,
      qrDataUrl,
    });
  } catch (e) {
    return res.status(500).json({ error: String(e.message || e) });
  }
});


app.post("/api/payments/:paymentId/refund", async (req, res) => {
  const { paymentId } = req.params;
  const executorKey = process.env.EXECUTOR_PRIVATE_KEY;
  const contractAddress = process.env.REFUND_PROTOCOL_ADDRESS;

  if (!executorKey || !contractAddress) {
    return res.status(500).json({
      error: "EXECUTOR_PRIVATE_KEY and REFUND_PROTOCOL_ADDRESS must be set in .env",
    });
  }

  try {
    // 1. viem setup
    const publicClient = createPublicClient({ chain: base, transport: http() });
    const account = privateKeyToAccount(executorKey);
    const walletClient = createWalletClient({ chain: base, transport: http(), account });

    // 2. Compute wcPaymentIdHash = keccak256(bytes(paymentId))
    const wcPaymentIdHash = keccak256(toBytes(paymentId));

    // 3. Read getInfo → log payer + amount
    const [payer, amount] = await publicClient.readContract({
      address: contractAddress,
      abi: REFUND_PROTOCOL_ABI,
      functionName: "getInfo",
      args: [wcPaymentIdHash],
    });
    console.log(`Refund info — payer: ${payer}, amount: ${amount.toString()} (USDC base units)`);

    // 4. Resolve uint256 paymentID from wcPaymentIdHash
    const paymentID = await publicClient.readContract({
      address: contractAddress,
      abi: REFUND_PROTOCOL_ABI,
      functionName: "paymentIdForWcHash",
      args: [wcPaymentIdHash],
    });

    // 5. Execute on-chain refund
    const txHash = await walletClient.writeContract({
      address: contractAddress,
      abi: REFUND_PROTOCOL_ABI,
      functionName: "refundByRecipient",
      args: [paymentID],
    });

    // 6. All on-chain steps succeeded — cancel the payment on WC Pay
    // 400 = already cancelled / not cancellable, safe to ignore
    const cancelRes = await fetch(
      `${API_BASE}/v1/payments/${encodeURIComponent(paymentId)}/cancel`,
      { method: "POST", headers: wcpHeaders() },
    );
    if (!cancelRes.ok && cancelRes.status !== 400) {
      console.warn(`WC Pay cancel returned ${cancelRes.status} — refund is already on-chain`);
    }

    return res.json({ success: true, txHash, payer, amount: amount.toString() });
  } catch (e) {
    return res.status(500).json({ error: String(e.message || e) });
  }
});

app.get("/api/payments/:paymentId/status", async (req, res) => {
  if (!API_KEY || !MERCHANT_ID) {
    return res.status(500).json({
      error: "Set WCP_API_KEY and WCP_MERCHANT_ID in .env",
    });
  }

  try {
    const wcpRes = await fetch(
      `${API_BASE}/v1/payments/${encodeURIComponent(req.params.paymentId)}/status`,
      { headers: wcpHeaders() }
    );
    const text = await wcpRes.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      data = { raw: text };
    }
    return res.status(wcpRes.status).json(data);
  } catch (e) {
    return res.status(500).json({ error: String(e.message || e) });
  }
});

const PORT = Number(process.env.PORT) || 3847;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`WCP demo: http://localhost:${PORT}`);
  console.log(`On your phone (same Wi‑Fi): http://<this-machine-LAN-IP>:${PORT}`);
});
