// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRefundProtocolEscrow {
    function payFromContract(
        address recipient,
        address payer,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) external;
}

/**
 * @title MerchantVault
 * @notice Holds USDC from payment rails (e.g. WalletConnect Pay payout address). The owner moves funds
 *         into RefundProtocol escrow via payFromContract, crediting `recipient` (merchant) while
 *         recording `payer` (customer) on the protocol.
 */
contract MerchantVault is Ownable {
    using SafeERC20 for IERC20;

    IRefundProtocolEscrow public immutable refundProtocol;
    IERC20 public immutable usdc;

    error ZeroAddress();

    constructor(address initialOwner, address _refundProtocol, address _usdc) Ownable(initialOwner) {
        if (_refundProtocol == address(0) || _usdc == address(0)) {
            revert ZeroAddress();
        }
        refundProtocol = IRefundProtocolEscrow(_refundProtocol);
        usdc = IERC20(_usdc);
    }

    /**
     * @notice USDC: vault → RefundProtocol; see RefundProtocol.payFromContract for parameters.
     * @dev Callable only by owner (e.g. backend hot wallet or multisig). Approve is scoped to `amount` per call.
     */
    function escrowToRefundProtocol(
        address recipient,
        address payer,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) external onlyOwner {
        usdc.forceApprove(address(refundProtocol), amount);
        refundProtocol.payFromContract(recipient, payer, amount, refundTo, wcPaymentIdHash);
        usdc.forceApprove(address(refundProtocol), 0);
    }

    /// @notice Recover tokens sent by mistake (owner custody).
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }
}
