export const MERCHANT_VAULT_ABI = [
  "function escrowToRefundProtocol(address recipient, address payer, uint256 amount, address refundTo, bytes32 wcPaymentIdHash) external",
  "function usdc() view returns (address)",
  "function refundProtocol() view returns (address)",
] as const;

export const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
] as const;
