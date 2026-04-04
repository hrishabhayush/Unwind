import { ethers } from "ethers";
import { config } from "./config.js";
import { MERCHANT_VAULT_ABI, ERC20_ABI } from "./abi.js";

// Track payment IDs we've already relayed
const relayedPayments = new Set<string>();

interface PaymentRecord {
  payment_id: string;
  status: string;
  token_amount?: string;
  buyer_caip10?: string;
  chain_id?: string;
  is_terminal: boolean;
}

interface TransactionsResponse {
  data: PaymentRecord[];
  next_cursor?: string | null;
}

// --- WC Pay merchant API ---

async function fetchCompletedPayments(): Promise<PaymentRecord[]> {
  const url = `${config.wcp.apiUrl}/merchants/${config.wcp.merchantId}/payments?status=succeeded&sort_by=date&sort_dir=desc&limit=20`;

  const res = await fetch(url, {
    headers: {
      "x-api-key": config.wcp.apiKey,
      "Content-Type": "application/json",
    },
  });

  if (!res.ok) {
    throw new Error(`WCP API error: ${res.status} ${res.statusText}`);
  }

  const data: TransactionsResponse = await res.json();
  return data.data;
}

// --- Arc testnet relay ---

function parseBuyerAddress(caip10?: string): string | null {
  if (!caip10) return null;
  // format: eip155:{chainId}:{address}
  const parts = caip10.split(":");
  return parts.length >= 3 ? parts[2] : null;
}

function wcPaymentIdHash(paymentId: string): string {
  return ethers.keccak256(ethers.toUtf8Bytes(paymentId));
}

async function relayToArc(payment: PaymentRecord) {
  const provider = new ethers.JsonRpcProvider(config.arc.rpcUrl);
  const wallet = new ethers.Wallet(config.arc.privateKey, provider);

  const vault = new ethers.Contract(
    config.arc.vaultAddress,
    MERCHANT_VAULT_ABI,
    wallet,
  );

  const buyerAddress = parseBuyerAddress(payment.buyer_caip10);
  if (!buyerAddress) {
    console.log(`  skipping ${payment.payment_id}: no buyer address`);
    return;
  }

  const amount = ethers.parseUnits(payment.token_amount || "0", 6); // USDC 6 decimals
  if (amount === 0n) {
    console.log(`  skipping ${payment.payment_id}: zero amount`);
    return;
  }

  const idHash = wcPaymentIdHash(payment.payment_id);
  const merchantAddress = wallet.address; // relayer acts as merchant on testnet

  console.log(`  relaying ${payment.payment_id}`);
  console.log(`    buyer: ${buyerAddress}`);
  console.log(`    amount: ${payment.token_amount} USDC`);
  console.log(`    wcPaymentIdHash: ${idHash}`);

  try {
    const tx = await vault.escrowToRefundProtocol(
      merchantAddress, // recipient (merchant)
      buyerAddress,     // payer (customer)
      amount,
      buyerAddress,     // refundTo (same as payer)
      idHash,
    );

    console.log(`    tx hash: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`    confirmed in block ${receipt?.blockNumber}`);
  } catch (err: any) {
    console.error(`    relay failed: ${err.message}`);
  }
}

// --- Main loop ---

async function poll() {
  console.log(`[${new Date().toISOString()}] polling for new payments...`);

  try {
    const payments = await fetchCompletedPayments();
    const newPayments = payments.filter((p) => !relayedPayments.has(p.payment_id));

    if (newPayments.length === 0) {
      console.log("  no new payments");
      return;
    }

    console.log(`  found ${newPayments.length} new payment(s)`);

    for (const payment of newPayments) {
      await relayToArc(payment);
      relayedPayments.add(payment.payment_id);
    }
  } catch (err: any) {
    console.error(`  poll error: ${err.message}`);
  }
}

async function main() {
  console.log("arc testnet relayer starting");
  console.log(`  merchant: ${config.wcp.merchantId}`);
  console.log(`  vault: ${config.arc.vaultAddress}`);
  console.log(`  poll interval: ${config.pollIntervalMs}ms`);
  console.log("");

  // Initial poll
  await poll();

  // Continuous polling
  setInterval(poll, config.pollIntervalMs);
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
