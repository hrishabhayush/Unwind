import "dotenv/config";

function required(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing env var: ${key}`);
  return val;
}

export const config = {
  wcp: {
    merchantId: required("WCP_MERCHANT_ID"),
    apiKey: required("WCP_API_KEY"),
    apiUrl: process.env.WCP_MERCHANT_API_URL || "https://merchant-api.walletconnect.com",
  },
  arc: {
    rpcUrl: required("ARC_TESTNET_RPC_URL"),
    privateKey: required("ARC_RELAYER_PRIVATE_KEY"),
    vaultAddress: required("ARC_MERCHANT_VAULT_ADDRESS"),
    usdcAddress: required("ARC_USDC_ADDRESS"),
  },
  pollIntervalMs: Number(process.env.POLL_INTERVAL_MS) || 10_000,
};
