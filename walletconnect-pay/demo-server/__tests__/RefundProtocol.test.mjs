import { describe, it, expect, vi } from "vitest";
import { RefundProtocol } from "../contracts/RefundProtocol.mjs";

const ADDR = "0x1111111111111111111111111111111111111111";
const HASH = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab";

describe("RefundProtocol", () => {
  describe("getInfo", () => {
    it("returns { payer, amount } on success", async () => {
      const payer = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1";
      const amount = 1_000_000n;
      const readContract = vi.fn().mockResolvedValue([payer, amount]);

      const contract = new RefundProtocol({ publicClient: { readContract }, address: ADDR });
      const result = await contract.getInfo(HASH);

      expect(result).toEqual({ payer, amount });
      expect(readContract).toHaveBeenCalledWith(
        expect.objectContaining({ functionName: "getInfo", args: [HASH] }),
      );
    });

    it("returns null when WcPaymentHashUnknown is thrown via cause.data", async () => {
      const error = { cause: { data: { errorName: "WcPaymentHashUnknown" } } };
      const readContract = vi.fn().mockRejectedValue(error);

      const contract = new RefundProtocol({ publicClient: { readContract }, address: ADDR });
      await expect(contract.getInfo(HASH)).resolves.toBeNull();
    });

    it("returns null when WcPaymentHashUnknown is thrown via direct data", async () => {
      const error = { data: { errorName: "WcPaymentHashUnknown" } };
      const readContract = vi.fn().mockRejectedValue(error);

      const contract = new RefundProtocol({ publicClient: { readContract }, address: ADDR });
      await expect(contract.getInfo(HASH)).resolves.toBeNull();
    });

    it("re-throws unexpected errors", async () => {
      const error = new Error("network timeout");
      const readContract = vi.fn().mockRejectedValue(error);

      const contract = new RefundProtocol({ publicClient: { readContract }, address: ADDR });
      await expect(contract.getInfo(HASH)).rejects.toThrow("network timeout");
    });
  });

  describe("paymentIdForWcHash", () => {
    it("returns the paymentID bigint", async () => {
      const paymentID = 7n;
      const readContract = vi.fn().mockResolvedValue(paymentID);

      const contract = new RefundProtocol({ publicClient: { readContract }, address: ADDR });
      const result = await contract.paymentIdForWcHash(HASH);

      expect(result).toBe(paymentID);
      expect(readContract).toHaveBeenCalledWith(
        expect.objectContaining({ functionName: "paymentIdForWcHash", args: [HASH] }),
      );
    });
  });
});
