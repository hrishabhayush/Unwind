import { http } from "viem";
import { base, baseSepolia } from "viem/chains";

/**
 * Returns a viem http transport for the given chain.
 * Uses Alchemy if ALCHEMY_API_KEY is set, otherwise falls back to the public RPC.
 *
 * @param {import("viem").Chain} chain
 * @returns {import("viem").HttpTransport}
 */
export function getRpcTransport(chain) {
  const apiKey = process.env.ALCHEMY_API_KEY;
  if (!apiKey) return http();

  switch (chain.id) {
    case base.id:
      return http(`https://base-mainnet.g.alchemy.com/v2/${apiKey}`);
    case baseSepolia.id:
      return http(`https://base-sepolia.g.alchemy.com/v2/${apiKey}`);
    default:
      return http();
  }
}
