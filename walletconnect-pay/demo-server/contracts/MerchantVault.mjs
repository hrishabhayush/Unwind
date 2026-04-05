import { MERCHANT_VAULT_ABI } from "../constants/merchantVaultAbi.mjs";

export class MerchantVault {
  constructor({ publicClient, walletClient, address }) {
    this.publicClient = publicClient;
    this.walletClient = walletClient;
    this.address = address;
  }

  /**
   * Simulates then submits escrowToRefundProtocol.
   * Simulation catches reverts (e.g. WcPaymentIdAlreadyUsed) before spending gas.
   * @param {{ recipient: string, payer: string, amount: string, refundTo: string, wcPaymentIdHash: `0x${string}` }} params
   * @returns {Promise<`0x${string}`>} txHash
   */
  async escrowToRefundProtocol({ recipient, payer, amount, refundTo, wcPaymentIdHash }) {
    const args = [recipient, payer, BigInt(amount), refundTo, wcPaymentIdHash];

    const { request } = await this.publicClient.simulateContract({
      address: this.address,
      abi: MERCHANT_VAULT_ABI,
      functionName: "escrowToRefundProtocol",
      args,
      account: this.walletClient.account,
    });

    return this.walletClient.writeContract(request);
  }
}
