// SPDX-License-Identifier: Apache-2.0
/*
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RefundProtocol is EIP712, ReentrancyGuard {
    struct Payment {
        address to;
        uint256 amount;
        uint256 releaseTimestamp;
        address refundTo;
        uint256 withdrawnAmount;
        bool refunded;
        uint256 refundExpiryTimestamp;
        address payer;
        /// @dev keccak256(bytes(wcPaymentId)) off-chain; zero if not linked to WalletConnect Pay
        bytes32 wcPaymentIdHash;
    }

    uint256 public constant MAX_LOCKUP_SECONDS = 60 * 60 * 24 * 180; // 180 days
    uint256 public constant RECLAIM_GRACE_PERIOD = 60 * 60 * 24 * 30; // 30 days
    bytes32 public constant EARLY_WITHDRAWAL_TYPEHASH = keccak256(
        "EarlyWithdrawalByArbiter(uint256[] paymentIDs,uint256[] withdrawalAmounts,uint256 feeAmount,uint256 expiry,uint256 salt)"
    );

    IERC20 public fiatToken;
    uint256 public nonce;
    address public arbiter;
    mapping(address => uint256) public lockupSeconds;
    mapping(uint256 => Payment) public payments;
    /// @dev WC Pay id hash -> protocol paymentID + 1 (0 means unset; real id is value - 1)
    mapping(bytes32 => uint256) public wcHashToPaymentId;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public debts;
    mapping(bytes32 => bool) public withdrawalHashes;

    event PaymentCreated(
        uint256 indexed paymentID,
        address indexed to,
        uint256 amount,
        uint256 releaseTimestamp,
        address indexed refundTo,
        uint256 refundExpiryTimestamp,
        bytes32 wcPaymentIdHash
    );
    event Refund(uint256 indexed paymentID, address indexed refundTo, uint256 amount);
    event RefundToUpdated(uint256 indexed paymentID, address indexed oldRefundTo, address indexed newRefundTo);
    event Withdrawal(address indexed to, uint256 amount);
    event WithdrawalFeePaid(address indexed recipient, uint256 amount);
    event Reclaim(uint256 indexed paymentID, address indexed payer, uint256 amount);

    error CallerNotAllowed();
    error PaymentIsStillLocked(uint256 paymentID);
    error PaymentDoesNotBelongToRecipient();
    error RefundToIsZeroAddress();
    error InsufficientFunds();
    error InvalidWithdrawalAmount(uint256 paymentID, uint256 withdrawalAmount);
    error InvalidFeeAmount();
    error InvalidSignature();
    error WithdrawalHashAlreadyUsed();
    error WithdrawalHashExpired();
    error PaymentRefunded(uint256 paymentID);
    error LockupSecondsExceedsMax();
    error MismatchedEarlyWithdrawalArrays();
    error RefundWindowExpired(uint256 paymentID);
    error ReclaimNotYetAvailable(uint256 paymentID);
    error WcPaymentIdAlreadyUsed();
    error WcPaymentHashUnknown();
    error PayerIsZeroAddress();
    error RecipientIsZeroAddress();

    constructor(address _arbiter, address _usdc, string memory eip712Name, string memory eip712version)
        EIP712(eip712Name, eip712version)
    {
        arbiter = _arbiter;
        fiatToken = IERC20(_usdc);
        nonce = 0;
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) {
            revert CallerNotAllowed();
        }
        _;
    }

    /**
     * Returns the domain separator for the contract.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * Initiates a payment to a recipient with a lockup period and a refund address.
     * @param to - recipient of the payment
     * @param amount - amount of USDC to send
     * @param refundTo - address to refund to if triggered
     * @param wcPaymentIdHash - keccak256(bytes(wcPaymentId)) from WalletConnect Pay, or bytes32(0) if none
     */
    function pay(address to, uint256 amount, address refundTo, bytes32 wcPaymentIdHash) external nonReentrant {
        if (refundTo == address(0)) {
            revert RefundToIsZeroAddress();
        }
        if (wcPaymentIdHash != bytes32(0)) {
            if (wcHashToPaymentId[wcPaymentIdHash] != 0) {
                revert WcPaymentIdAlreadyUsed();
            }
        }

        uint256 recipientlockupSeconds = lockupSeconds[to];
        uint256 releaseTimestamp = block.timestamp + recipientlockupSeconds;

        uint256 paymentID = nonce;
        fiatToken.transferFrom(msg.sender, address(this), amount);
        payments[paymentID] =
            Payment(to, amount, releaseTimestamp, refundTo, 0, false, releaseTimestamp, msg.sender, wcPaymentIdHash);
        balances[to] += amount;

        if (wcPaymentIdHash != bytes32(0)) {
            wcHashToPaymentId[wcPaymentIdHash] = paymentID + 1;
        }

        emit PaymentCreated(paymentID, to, amount, releaseTimestamp, refundTo, releaseTimestamp, wcPaymentIdHash);
        nonce += 1;
    }

    /**
     * @notice Records escrow for a settlement that did not call pay() on-chain (e.g. WalletConnect Pay API).
     * Caller must be the merchant address that both holds USDC and receives escrow accounting (same as `to`).
     * If USDC sits in another contract (vault), use payFromContract instead.
     * @param payer The customer address stored as payer (reclaim, refunds to refundTo semantics match pay()).
     * @param amount USDC to escrow (must match what was settled off-chain for your integration).
     * @param refundTo Customer refund destination (same role as pay()).
     * @param wcPaymentIdHash keccak256(bytes(wcPaymentId)) to link off-chain id, or bytes32(0).
     */
    function payAsRecipient(address payer, uint256 amount, address refundTo, bytes32 wcPaymentIdHash)
        external
        nonReentrant
    {
        _validateEscrowParams(msg.sender, payer, refundTo, wcPaymentIdHash);
        fiatToken.transferFrom(msg.sender, address(this), amount);
        _commitEscrowPayment(msg.sender, payer, amount, refundTo, wcPaymentIdHash);
    }

    /**
     * @notice Escrow USDC held by a smart contract (vault) while crediting a separate merchant `recipient`.
     * Caller is the token source: it must approve this contract, then call with the merchant as `recipient`.
     * @param recipient Merchant address (`Payment.to`, withdraw/refund recipient).
     * @param payer Customer address stored as payer (same semantics as pay()).
     */
    function payFromContract(
        address recipient,
        address payer,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) external nonReentrant {
        _validateEscrowParams(recipient, payer, refundTo, wcPaymentIdHash);
        fiatToken.transferFrom(msg.sender, address(this), amount);
        _commitEscrowPayment(recipient, payer, amount, refundTo, wcPaymentIdHash);
    }

    /**
     * @notice Arbiter-only bookkeeping when USDC is already held by this contract (e.g. pre-funded pool).
     * Does not pull tokens; ensure contract balance covers obligations before calling.
     * @param payer Customer address recorded on the Payment (same as pay()).
     * @param to Merchant recipient.
     */
    function registerPayment(
        address payer,
        address to,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) external onlyArbiter nonReentrant {
        _validateEscrowParams(to, payer, refundTo, wcPaymentIdHash);
        _commitEscrowPayment(to, payer, amount, refundTo, wcPaymentIdHash);
    }

    function _validateEscrowParams(address to, address payer, address refundTo, bytes32 wcPaymentIdHash) private view {
        if (payer == address(0)) {
            revert PayerIsZeroAddress();
        }
        if (refundTo == address(0)) {
            revert RefundToIsZeroAddress();
        }
        if (to == address(0)) {
            revert RecipientIsZeroAddress();
        }
        if (wcPaymentIdHash != bytes32(0)) {
            if (wcHashToPaymentId[wcPaymentIdHash] != 0) {
                revert WcPaymentIdAlreadyUsed();
            }
        }
    }

    /// @dev State write for off-chain-linked escrows; validate with _validateEscrowParams first (especially before transferFrom).
    function _commitEscrowPayment(
        address to,
        address payer,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) private {
        uint256 recipientlockupSeconds = lockupSeconds[to];
        uint256 releaseTimestamp = block.timestamp + recipientlockupSeconds;

        uint256 paymentID = nonce;
        payments[paymentID] =
            Payment(to, amount, releaseTimestamp, refundTo, 0, false, releaseTimestamp, payer, wcPaymentIdHash);
        balances[to] += amount;

        if (wcPaymentIdHash != bytes32(0)) {
            wcHashToPaymentId[wcPaymentIdHash] = paymentID + 1;
        }

        emit PaymentCreated(paymentID, to, amount, releaseTimestamp, refundTo, releaseTimestamp, wcPaymentIdHash);
        nonce += 1;
    }

    /**
     * @notice Resolve WalletConnect Pay id hash to on-chain payment id (if linked).
     * @return paymentID The escrow payment id; reverts if hash was never used.
     */
    function paymentIdForWcHash(bytes32 wcPaymentIdHash) external view returns (uint256 paymentID) {
        uint256 stored = wcHashToPaymentId[wcPaymentIdHash];
        if (stored == 0) {
            revert WcPaymentHashUnknown();
        }
        return stored - 1;
    }


    /**
     * A function that returns a payment to the refundTo address to cover a refund or a chargeback.
     * This function is callable only by the recipient of the payment, and can only be payed by the recipient.
     * @param paymentID payment to refund
     */
    function refundByRecipient(uint256 paymentID) external nonReentrant {
        Payment memory payment = payments[paymentID];
        if (msg.sender != payment.to) {
            revert CallerNotAllowed();
        }

        uint256 recipientBalance = balances[payment.to];

        if (payment.amount > recipientBalance) {
            revert InsufficientFunds();
        }

        balances[payment.to] = recipientBalance - payment.amount;

        _executeRefund(paymentID, payment);
    }

    /**
     * A function that returns a payment to the refundTo address to cover a refund or a chargeback.
     * It will first attempt to draw funds from the recipient's balance, and if that is insufficient,
     * it will draw from the arbiter's balance.
     * This function is callable only by the arbiter.
     * @param paymentID payment to refund
     */
    function refundByArbiter(uint256 paymentID) external onlyArbiter nonReentrant {
        Payment memory payment = payments[paymentID];

        uint256 recipientBalance = balances[payment.to];

        if (payment.amount <= recipientBalance) {
            balances[payment.to] = recipientBalance - payment.amount;
            return _executeRefund(paymentID, payment);
        }

        uint256 arbiterBalance = balances[arbiter];

        if (payment.amount > arbiterBalance) {
            revert InsufficientFunds();
        }

        balances[arbiter] = arbiterBalance - payment.amount;
        debts[payment.to] += payment.amount;

        _executeRefund(paymentID, payment);
    }

    /**
     * A function to settle recipient debts.
     * @param recipient the recipient address
     */
    function settleDebt(address recipient) external {
        _settleDebt(recipient);
    }

    /**
     * A function to add funds to the arbiter balance.
     * Funds will be drawn from the arbiter address and added to the arbiter balance.
     * @param amount amount to deposit
     */
    function depositArbiterFunds(uint256 amount) external onlyArbiter nonReentrant {
        fiatToken.transferFrom(msg.sender, address(this), amount);
        balances[arbiter] += amount;
    }

    /**
     * A function to withdraw arbiter funds
     * Funds will be drawn from the arbiter balance and remitted to the arbiter address.
     * @param amount amount to withdraw
     */
    function withdrawArbiterFunds(uint256 amount) external onlyArbiter nonReentrant {
        uint256 arbiterBalance = balances[arbiter];
        if (amount > arbiterBalance) {
            revert InsufficientFunds();
        }

        balances[arbiter] = arbiterBalance - amount;
        fiatToken.transfer(arbiter, amount);
    }

    /**
     * A function to set the lockup period for a recipient.
     * @param recipient the recipient address
     * @param recipientLockupSeconds the lockup period in seconds
     */
    function setLockupSeconds(address recipient, uint256 recipientLockupSeconds) external onlyArbiter {
        if (recipientLockupSeconds > MAX_LOCKUP_SECONDS) {
            revert LockupSecondsExceedsMax();
        }
        lockupSeconds[recipient] = recipientLockupSeconds;
    }

    /**
     * A permissionless function that allows users to withdraw their funds
     * after the lockup period has passed.
     * It will fail if:
     * 1. The caller is not the recipient of the payment
     * 2. The payment is still locked
     * 3. The payment has already been refunded
     * @param paymentIDs an array of payments to release
     */
    function withdraw(uint256[] calldata paymentIDs) external nonReentrant {
        _settleDebt(msg.sender);

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < paymentIDs.length; ++i) {
            Payment memory payment = payments[paymentIDs[i]];
            if (payment.to != msg.sender) {
                revert CallerNotAllowed();
            }
            if (block.timestamp < payment.releaseTimestamp) {
                revert PaymentIsStillLocked(paymentIDs[i]);
            }
            if (payment.refunded) {
                revert PaymentRefunded(paymentIDs[i]);
            }
            totalAmount += payment.amount - payment.withdrawnAmount;
            payments[paymentIDs[i]].withdrawnAmount = payment.amount;
        }
        uint256 recipientBalance = balances[msg.sender];
        if (totalAmount > recipientBalance) {
            revert InsufficientFunds();
        }
        balances[msg.sender] = recipientBalance - totalAmount;
        fiatToken.transfer(msg.sender, totalAmount);
        emit Withdrawal(msg.sender, totalAmount);
    }

    /**
     * Allows the arbiter to authorize early withdrawals for a recipient.
     * There is an optional fee that can be charged for the early withdrawal.
     * But the recipient must accept the terms of the early withdrawal
     * by signing the hash of the withdrawal information.
     * @param paymentIDs an array of payment IDS to release
     * @param withdrawalAmounts an array of withdrawal amounts
     * @param feeAmount an overall fee amount for the early withdrawal
     * @param expiry the expiration time for the early withdrawal
     * @param salt a value to make the hash unique
     * @param recipient the address to which to send the funds
     * @param v the v value of the signature
     * @param r the r value of the signature
     * @param s the s value of the signature
     */
    function earlyWithdrawByArbiter(
        uint256[] calldata paymentIDs,
        uint256[] calldata withdrawalAmounts,
        uint256 feeAmount,
        uint256 expiry,
        uint256 salt,
        address recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyArbiter nonReentrant {
        bytes32 withdrawalInfoHash = _hashEarlyWithdrawalInfo(paymentIDs, withdrawalAmounts, feeAmount, expiry, salt);

        // prevent replay attacks
        if (withdrawalHashes[withdrawalInfoHash]) {
            revert WithdrawalHashAlreadyUsed();
        }
        if (ecrecover(withdrawalInfoHash, v, r, s) != recipient) {
            revert InvalidSignature();
        }
        if (block.timestamp > expiry) {
            revert WithdrawalHashExpired();
        }

        uint256 totalAmount = 0;

        if (paymentIDs.length != withdrawalAmounts.length) {
            revert MismatchedEarlyWithdrawalArrays();
        }

        for (uint256 i = 0; i < paymentIDs.length; ++i) {
            uint256 paymentID = paymentIDs[i];
            uint256 withdrawalAmount = withdrawalAmounts[i];

            Payment memory payment = payments[paymentID];

            if (withdrawalAmount > payment.amount) {
                revert InvalidWithdrawalAmount(paymentID, withdrawalAmount);
            }
            if (payment.to != recipient) {
                revert PaymentDoesNotBelongToRecipient();
            }
            if (payment.refunded) {
                revert PaymentRefunded(paymentID);
            }
            totalAmount += withdrawalAmount;
            payments[paymentID].withdrawnAmount += withdrawalAmount;
        }
        if (feeAmount > totalAmount) {
            revert InvalidFeeAmount();
        }
        uint256 recipientBalance = balances[recipient];
        if (recipientBalance < totalAmount) {
            revert InsufficientFunds();
        }
        balances[recipient] = recipientBalance - totalAmount;
        balances[arbiter] += feeAmount;

        fiatToken.transfer(recipient, totalAmount - feeAmount);
        emit Withdrawal(recipient, totalAmount);
        emit WithdrawalFeePaid(recipient, feeAmount);

        withdrawalHashes[withdrawalInfoHash] = true;
    }

    /**
     * Allows the owner to authorize early withdrawals for a merchant
     * @param paymentID the payment ID to update
     * @param newRefundTo the address to which to update the refund address
     */
    function updateRefundTo(uint256 paymentID, address newRefundTo) external {
        if (newRefundTo == address(0)) {
            revert RefundToIsZeroAddress();
        }
        Payment memory payment = payments[paymentID];
        if (msg.sender != payment.refundTo) {
            revert CallerNotAllowed();
        }
        emit RefundToUpdated(paymentID, payment.refundTo, newRefundTo);
        payments[paymentID].refundTo = newRefundTo;
    }

    /**
     * Allows the payer to reclaim funds if the arbiter is offline and the merchant
     * has not withdrawn or refunded. Only available after lockup + grace period.
     * @param paymentID the payment ID to reclaim
     */
    function reclaim(uint256 paymentID) external nonReentrant {
        Payment memory payment = payments[paymentID];

        if (msg.sender != payment.payer) {
            revert CallerNotAllowed();
        }
        if (block.timestamp < payment.releaseTimestamp + RECLAIM_GRACE_PERIOD) {
            revert ReclaimNotYetAvailable(paymentID);
        }
        if (payment.refunded) {
            revert PaymentRefunded(paymentID);
        }

        uint256 reclaimAmount = payment.amount - payment.withdrawnAmount;
        if (reclaimAmount == 0) {
            revert InsufficientFunds();
        }

        balances[payment.to] -= reclaimAmount;
        payments[paymentID].refunded = true;

        fiatToken.transfer(msg.sender, reclaimAmount);

        emit Reclaim(paymentID, msg.sender, reclaimAmount);
    }

    /**
     * @notice Read payer and amount for a WalletConnect Pay id hash (off-chain: keccak256(bytes(wcPaymentId))).
     * @return payer Customer address on the Payment (from pay(), payAsRecipient(), payFromContract(), or registerPayment())
     * @return amount Escrow amount (USDC base units)
     */
    function getInfo(bytes32 wcPaymentIdHash) external view returns (address payer, uint256 amount) {
        uint256 stored = wcHashToPaymentId[wcPaymentIdHash];
        if (stored == 0) {
            revert WcPaymentHashUnknown();
        }
        uint256 paymentID = stored - 1;
        Payment memory p = payments[paymentID];
        payer = p.payer;
        amount = p.amount;
    }

    /**
     * External function to hash early withdrawal information
     * @param paymentIDs an array of payment IDS to release
     * @param withdrawalAmounts an array of amounts to withdraw from those payment IDs
     * @param feeAmount the fee amount for the early withdrawal
     * @param expiry the expiration time for the early withdrawal
     * @param salt a value to make the hash unique
     */
    function hashEarlyWithdrawalInfo(
        uint256[] calldata paymentIDs,
        uint256[] calldata withdrawalAmounts,
        uint256 feeAmount,
        uint256 expiry,
        uint256 salt
    ) external view returns (bytes32) {
        return _hashEarlyWithdrawalInfo(paymentIDs, withdrawalAmounts, feeAmount, expiry, salt);
    }

    /**
     * Internal function to execute a refund
     * @param paymentID the payment ID to refund
     * @param payment the payment struct
     */
    function _executeRefund(uint256 paymentID, Payment memory payment) internal {
        if (payment.refunded) {
            revert PaymentRefunded(paymentID);
        }
        if (block.timestamp >= payment.refundExpiryTimestamp) {
            revert RefundWindowExpired(paymentID);
        }

        payments[paymentID].refunded = true;

        fiatToken.transfer(payment.refundTo, payment.amount);

        emit Refund(paymentID, payment.refundTo, payment.amount);
    }

    /**
     * Internal function to settle recipient debts
     * @param recipient the recipient address
     */
    function _settleDebt(address recipient) internal {
        uint256 recipientDebt = debts[recipient];
        uint256 recipientBalance = balances[recipient];

        uint256 settleAmount = recipientBalance < recipientDebt ? recipientBalance : recipientDebt;

        balances[recipient] = recipientBalance - settleAmount;
        balances[arbiter] += settleAmount;
        debts[recipient] = recipientDebt - settleAmount;
    }

    /**
     * Internal function to hash early withdrawal information
     * @param paymentIDs an array of payment IDS to release
     * @param withdrawalAmounts an array of amounts to withdraw from those payment IDs
     * @param feeAmount the fee amount for the early withdrawal
     * @param expiry the expiration time for the early withdrawal
     * @param salt a value to make the hash unique
     */
    function _hashEarlyWithdrawalInfo(
        uint256[] calldata paymentIDs,
        uint256[] calldata withdrawalAmounts,
        uint256 feeAmount,
        uint256 expiry,
        uint256 salt
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(EARLY_WITHDRAWAL_TYPEHASH, paymentIDs, withdrawalAmounts, feeAmount, expiry, salt)
        );
        return _hashTypedDataV4(structHash);
    }
}
