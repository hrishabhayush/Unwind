import { describe, it, expect, vi } from "vitest";
import { MerchantVault } from "../contracts/MerchantVault.mjs";

const ADDR = "0x2222222222222222222222222222222222222222";

function makeClients(txHash = "0xtxhash123") {
  const simulatedRequest = { address: ADDR, functionName: "escrowToRefundProtocol" };
  const simulateContract = vi.fn().mockResolvedValue({ request: simulatedRequest });
  const writeContract = vi.fn().mockResolvedValue(txHash);
  const publicClient = { simulateContract };
  const walletClient = { writeContract, account: { address: "0xexecutor" } };
  return { publicClient, walletClient, simulateContract, writeContract, simulatedRequest };
}

describe("MerchantVault", () => {
  describe("escrowToRefundProtocol", () => {
    it("simulates then writes and returns txHash", async () => {
      const { publicClient, walletClient, simulateContract, writeContract, simulatedRequest } = makeClients();

      const contract = new MerchantVault({ publicClient, walletClient, address: ADDR });
      const params = {
        recipient: "0xrecipient0000000000000000000000000000001",
        payer: "0xpayer00000000000000000000000000000000001",
        amount: "1000000",
        refundTo: "0xrefundto000000000000000000000000000000001",
        wcPaymentIdHash: "0xhash",
      };

      const result = await contract.escrowToRefundProtocol(params);

      expect(result).toBe("0xtxhash123");
      expect(simulateContract).toHaveBeenCalledWith(
        expect.objectContaining({
          address: ADDR,
          functionName: "escrowToRefundProtocol",
          args: [params.recipient, params.payer, 1_000_000n, params.refundTo, params.wcPaymentIdHash],
        }),
      );
      // writeContract receives the simulated request object
      expect(writeContract).toHaveBeenCalledWith(simulatedRequest);
    });

    it("converts amount string to BigInt in simulate call", async () => {
      const { publicClient, walletClient, simulateContract } = makeClients();

      const contract = new MerchantVault({ publicClient, walletClient, address: ADDR });
      await contract.escrowToRefundProtocol({
        recipient: "0xr", payer: "0xp", amount: "999999", refundTo: "0xf", wcPaymentIdHash: "0xh",
      });

      const [, , amount] = simulateContract.mock.calls[0][0].args;
      expect(amount).toBe(999_999n);
    });

    it("propagates simulateContract errors before sending tx", async () => {
      const revertError = new Error("WcPaymentIdAlreadyUsed");
      const simulateContract = vi.fn().mockRejectedValue(revertError);
      const writeContract = vi.fn();
      const publicClient = { simulateContract };
      const walletClient = { writeContract, account: {} };

      const contract = new MerchantVault({ publicClient, walletClient, address: ADDR });
      await expect(
        contract.escrowToRefundProtocol({
          recipient: "0xr", payer: "0xp", amount: "1", refundTo: "0xf", wcPaymentIdHash: "0xh",
        }),
      ).rejects.toThrow("WcPaymentIdAlreadyUsed");

      expect(writeContract).not.toHaveBeenCalled();
    });
  });
});
