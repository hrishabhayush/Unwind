import { describe, it, expect, vi } from "vitest";
import { MerchantVault } from "../contracts/MerchantVault.mjs";

const ADDR = "0x2222222222222222222222222222222222222222";

describe("MerchantVault", () => {
  describe("escrowToRefundProtocol", () => {
    it("calls writeContract with correct args and returns txHash", async () => {
      const txHash = "0xtxhash123";
      const writeContract = vi.fn().mockResolvedValue(txHash);

      const contract = new MerchantVault({ walletClient: { writeContract }, address: ADDR });
      const params = {
        recipient: "0xrecipient0000000000000000000000000000001",
        payer: "0xpayer00000000000000000000000000000000001",
        amount: "1000000",
        refundTo: "0xrefundto000000000000000000000000000000001",
        wcPaymentIdHash: "0xhash",
      };

      const result = await contract.escrowToRefundProtocol(params);

      expect(result).toBe(txHash);
      expect(writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          address: ADDR,
          functionName: "escrowToRefundProtocol",
          args: [params.recipient, params.payer, 1_000_000n, params.refundTo, params.wcPaymentIdHash],
        }),
      );
    });

    it("converts amount string to BigInt", async () => {
      const writeContract = vi.fn().mockResolvedValue("0xtx");

      const contract = new MerchantVault({ walletClient: { writeContract }, address: ADDR });
      await contract.escrowToRefundProtocol({
        recipient: "0xr",
        payer: "0xp",
        amount: "999999",
        refundTo: "0xf",
        wcPaymentIdHash: "0xh",
      });

      const [, , amount] = writeContract.mock.calls[0][0].args;
      expect(amount).toBe(999_999n);
    });

    it("propagates writeContract errors", async () => {
      const writeContract = vi.fn().mockRejectedValue(new Error("insufficient funds"));

      const contract = new MerchantVault({ walletClient: { writeContract }, address: ADDR });
      await expect(
        contract.escrowToRefundProtocol({
          recipient: "0xr", payer: "0xp", amount: "1", refundTo: "0xf", wcPaymentIdHash: "0xh",
        }),
      ).rejects.toThrow("insufficient funds");
    });
  });
});
