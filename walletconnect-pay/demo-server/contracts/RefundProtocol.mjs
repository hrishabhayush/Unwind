import { REFUND_PROTOCOL_ABI } from "../constants/refundProtocolAbi.mjs";

export class RefundProtocol {
  constructor({ publicClient, walletClient, address }) {
    this.publicClient = publicClient;
    this.walletClient = walletClient ?? null;
    this.address = address;
  }

  /**
   * Returns { payer, amount } if the payment exists,
   * or null if the contract reverts with WcPaymentHashUnknown.
   * @param {`0x${string}`} wcPaymentIdHash
   * @returns {Promise<{ payer: string, amount: bigint } | null>}
   */
  async getInfo(wcPaymentIdHash) {
    try {
      const [payer, amount] = await this.publicClient.readContract({
        address: this.address,
        abi: REFUND_PROTOCOL_ABI,
        functionName: "getInfo",
        args: [wcPaymentIdHash],
      });
      return { payer, amount };
    } catch (e) {
      // viem wraps revert errors; custom error name lives on cause.data or direct data
      const revertData = e?.cause?.data ?? e?.data;
      if (revertData?.errorName === "WcPaymentHashUnknown") return null;
      throw e;
    }
  }

  /**
   * @param {`0x${string}`} wcPaymentIdHash
   * @returns {Promise<bigint>}
   */
  async paymentIdForWcHash(wcPaymentIdHash) {
    return this.publicClient.readContract({
      address: this.address,
      abi: REFUND_PROTOCOL_ABI,
      functionName: "paymentIdForWcHash",
      args: [wcPaymentIdHash],
    });
  }

  /**
   * Simulates then submits refundByRecipient.
   * @param {bigint} paymentID
   * @returns {Promise<`0x${string}`>} txHash
   */
  async refundByRecipient(paymentID) {
    const { request } = await this.publicClient.simulateContract({
      address: this.address,
      abi: REFUND_PROTOCOL_ABI,
      functionName: "refundByRecipient",
      args: [paymentID],
      account: this.walletClient.account,
    });

    return this.walletClient.writeContract(request);
  }
}
