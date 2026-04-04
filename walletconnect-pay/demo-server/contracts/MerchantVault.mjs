import { MERCHANT_VAULT_ABI } from "../constants/merchantVaultAbi.mjs";

export class MerchantVault {
  constructor({ walletClient, address }) {
    this.walletClient = walletClient;
    this.address = address;
  }

  /**
   * Moves USDC from the vault into RefundProtocol escrow.
   * @param {{ recipient: string, payer: string, amount: string, refundTo: string, wcPaymentIdHash: `0x${string}` }} params
   * @returns {Promise<`0x${string}`>} txHash
   */
  async escrowToRefundProtocol({ recipient, payer, amount, refundTo, wcPaymentIdHash }) {
    return this.walletClient.writeContract({
      address: this.address,
      abi: MERCHANT_VAULT_ABI,
      functionName: "escrowToRefundProtocol",
      args: [recipient, payer, BigInt(amount), refundTo, wcPaymentIdHash],
    });
  }
}
