export const MERCHANT_VAULT_ABI = [
  {
    inputs: [
      { internalType: "address", name: "recipient", type: "address" },
      { internalType: "address", name: "payer", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
      { internalType: "address", name: "refundTo", type: "address" },
      { internalType: "bytes32", name: "wcPaymentIdHash", type: "bytes32" },
    ],
    name: "escrowToRefundProtocol",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  // RefundProtocol errors that bubble up through escrowToRefundProtocol
  { inputs: [], name: "WcPaymentIdAlreadyUsed", type: "error" },
  { inputs: [], name: "WcPaymentHashUnknown", type: "error" },
  { inputs: [], name: "PayerIsZeroAddress", type: "error" },
  { inputs: [], name: "RecipientIsZeroAddress", type: "error" },
  { inputs: [], name: "RefundToIsZeroAddress", type: "error" },
  { inputs: [], name: "InsufficientFunds", type: "error" },
  { inputs: [], name: "ZeroAddress", type: "error" },
];
