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

import "forge-std/Test.sol";
import "../src/RefundProtocol.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev USDC lives here; merchant `recipient` is credited on RefundProtocol.
contract MerchantVault {
    function escrowForMerchant(
        RefundProtocol protocol,
        IERC20 token,
        address recipient,
        address payer,
        uint256 amount,
        address refundTo,
        bytes32 wcPaymentIdHash
    ) external {
        token.approve(address(protocol), amount);
        protocol.payFromContract(recipient, payer, amount, refundTo, wcPaymentIdHash);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RefundProtocolTest is Test {
    RefundProtocol public refundProtocol;
    MockERC20 public usdc;
    MerchantVault public vault;
    uint256 public expiry = block.timestamp + 9999999;
    uint256 public receiverPrivateKey = 0x5678;
    uint256 public userPrivateKey = 0x1234;
    address public owner = address(0x1111);
    address public arbiter = address(0xABCD);
    address public user = vm.addr(userPrivateKey);
    address public receiver = vm.addr(receiverPrivateKey);
    address public refundTo = address(0x9ABC);
    address public refundTo2 = address(0xDEF0);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        refundProtocol = new RefundProtocol(owner, arbiter, address(usdc), "Refund Protocol", "1.0");
        vault = new MerchantVault();

        // Mint USDC to user and approve the protocol
        usdc.mint(user, 1000);
        usdc.mint(arbiter, 1000);
        vm.prank(user);
        usdc.approve(address(refundProtocol), 1000);
        vm.prank(arbiter);
        usdc.approve(address(refundProtocol), 1000);
    }

    function testPay() public {
        vm.startPrank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        (address to, uint256 amount,, address refundAddr,,,, address payer, bytes32 wcHash) = refundProtocol.payments(0);
        assertEq(to, receiver);
        assertEq(amount, 100);
        assertEq(refundAddr, refundTo);
        assertEq(payer, user);
        assertEq(wcHash, bytes32(0));
        assertEq(refundProtocol.balances(receiver), 100);
    }

    function testPayRefundToIsZeroAddress() public {
        vm.startPrank(user);
        vm.expectRevert(RefundProtocol.RefundToIsZeroAddress.selector);
        refundProtocol.pay(receiver, 100, address(0), bytes32(0));
    }

    function testSetLockupSeconds() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 1);
        vm.stopPrank();

        assertEq(refundProtocol.lockupSeconds(receiver), 1);
    }

    function testSetLockupSecondsExceedsMax() public {
        uint256 lockupSeconds = refundProtocol.MAX_LOCKUP_SECONDS() + 1;
        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.LockupSecondsExceedsMax.selector);
        refundProtocol.setLockupSeconds(receiver, lockupSeconds);
    }

    function testSetLockupSecondsUnauthorized() public {
        vm.prank(receiver);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.setLockupSeconds(receiver, 1);
    }

    function testWithdrawWithoutLockup() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        vm.prank(receiver);
        refundProtocol.withdraw(paymentIDs);
        vm.assertEq(refundProtocol.balances(receiver), 0);
        vm.assertEq(usdc.balanceOf(receiver), 100);
    }

    function testWithdrawWithSetLockup() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.startPrank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.stopPrank();
        vm.startPrank(receiver);

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.PaymentIsStillLocked.selector, 0));
        refundProtocol.withdraw(paymentIDs);

        vm.warp(block.timestamp + 3600); // Advance time to a valid timestamp
        refundProtocol.withdraw(paymentIDs);
        vm.assertEq(refundProtocol.balances(receiver), 0);
        vm.assertEq(usdc.balanceOf(receiver), 100);
    }

    function testWithdrawAfterPartialEarlyWithdrawal() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 90;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        vm.assertEq(refundProtocol.balances(receiver), 10);
        vm.assertEq(usdc.balanceOf(receiver), 90);

        vm.warp(block.timestamp + 3600); // Advance time to a valid timestamp
        vm.prank(receiver);
        refundProtocol.withdraw(paymentIDs);
        vm.assertEq(refundProtocol.balances(receiver), 0);
        vm.assertEq(usdc.balanceOf(receiver), 100);
    }

    function testWithdrawAfterRefund() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(owner);
        refundProtocol.refundByRecipient(0);

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        vm.warp(block.timestamp + 3600); // Advance time to a valid timestamp
        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.PaymentRefunded.selector, 0));
        refundProtocol.withdraw(paymentIDs);
    }

    function testWithdrawInsufficientFunds() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.startPrank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
        refundProtocol.depositArbiterFunds(100);
        refundProtocol.refundByArbiter(0);
        vm.stopPrank();

        vm.assertEq(refundProtocol.debts(receiver), 100);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.assertEq(refundProtocol.debts(receiver), 100);
        vm.assertEq(refundProtocol.balances(receiver), 100);

        uint256[] memory withdrawPaymentIDs = new uint256[](1);
        withdrawPaymentIDs[0] = 1;

        vm.warp(block.timestamp + 3600); // Advance time to a valid timestamp
        vm.prank(receiver);
        vm.expectRevert(RefundProtocol.InsufficientFunds.selector);
        refundProtocol.withdraw(withdrawPaymentIDs);
    }

    function testUnauthorizedWithdraw() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        vm.prank(address(user)); // Unauthorized user
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.withdraw(paymentIDs);
    }

    function testDepositArbiterFunds() public {
        assertEq(refundProtocol.balances(arbiter), 0);
        assertEq(usdc.balanceOf(address(refundProtocol)), 0);

        vm.startPrank(arbiter);
        refundProtocol.depositArbiterFunds(100);
        vm.stopPrank();

        assertEq(refundProtocol.balances(arbiter), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 100);
    }

    function testDepositArbiterFundsUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.depositArbiterFunds(100);
        vm.stopPrank();
    }

    function testWithdrawArbiterFunds() public {
        assertEq(refundProtocol.balances(arbiter), 0);
        assertEq(usdc.balanceOf(address(refundProtocol)), 0);

        vm.startPrank(arbiter);
        refundProtocol.depositArbiterFunds(100);
        vm.stopPrank();

        assertEq(refundProtocol.balances(arbiter), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 100);

        vm.startPrank(arbiter);
        refundProtocol.withdrawArbiterFunds(10);

        assertEq(refundProtocol.balances(arbiter), 90);
        assertEq(usdc.balanceOf(address(refundProtocol)), 90);
        assertEq(usdc.balanceOf(arbiter), 910);
    }

    function testWithdrawArbiterFundsUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.withdrawArbiterFunds(100);
        vm.stopPrank();
    }

    function testEarlyWithdrawByArbiter() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.PaymentIsStillLocked.selector, 0));
        refundProtocol.withdraw(paymentIDs);

        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 90;
        uint256 feeAmount = 1;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        assertEq(refundProtocol.balances(receiver), 10);
        assertEq(refundProtocol.balances(arbiter), 1);
        assertEq(usdc.balanceOf(receiver), 89);
        assertEq(usdc.balanceOf(address(refundProtocol)), 11);
    }

    function testEarlyWithdrawByArbiterInsufficientFunds() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs1 = new uint256[](1);
        paymentIDs1[0] = 0;
        uint256[] memory withdrawalAmounts1 = new uint256[](1);
        withdrawalAmounts1[0] = 100;
        uint256 feeAmount1 = 0;

        (uint8 v1, bytes32 r1, bytes32 s1) = _generateEarlyWithdrawalSignature(
            paymentIDs1, withdrawalAmounts1, feeAmount1, expiry, 0, receiverPrivateKey
        );

        vm.startPrank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(
            paymentIDs1, withdrawalAmounts1, feeAmount1, expiry, 0, receiver, v1, r1, s1
        );
        refundProtocol.depositArbiterFunds(100);
        refundProtocol.refundByArbiter(0);
        vm.stopPrank();

        vm.assertEq(refundProtocol.debts(receiver), 100);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(arbiter);
        refundProtocol.settleDebt(receiver);

        vm.assertEq(refundProtocol.debts(receiver), 0);
        vm.assertEq(refundProtocol.balances(receiver), 0);

        uint256[] memory paymentIDs2 = new uint256[](1);
        paymentIDs2[0] = 1;
        uint256[] memory withdrawalAmounts2 = new uint256[](1);
        withdrawalAmounts2[0] = 100;
        uint256 feeAmount2 = 0;

        (uint8 v2, bytes32 r2, bytes32 s2) = _generateEarlyWithdrawalSignature(
            paymentIDs2, withdrawalAmounts2, feeAmount2, expiry, 0, receiverPrivateKey
        );

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.InsufficientFunds.selector);
        refundProtocol.earlyWithdrawByArbiter(
            paymentIDs2, withdrawalAmounts2, feeAmount2, expiry, 0, receiver, v2, r2, s2
        );
    }

    function testEarlyWithdrawByArbiterInvalidWithdrawalAmount() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 110;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.InvalidWithdrawalAmount.selector, 0, 110));
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterInvalidFeeAmount() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 101;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.InvalidFeeAmount.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterInvalidSignature() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 100;

        uint256 agreedToFeeAmount = 1;

        (uint8 v, bytes32 r, bytes32 s) = _generateEarlyWithdrawalSignature(
            paymentIDs, withdrawalAmounts, agreedToFeeAmount, expiry, 0, receiverPrivateKey
        );

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.InvalidSignature.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterWithdrawalHashAlreadyUsed() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 10;
        uint256 feeAmount = 2;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.WithdrawalHashAlreadyUsed.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterAfterRefund() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(owner);
        refundProtocol.refundByRecipient(0);

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.PaymentRefunded.selector, 0));
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterExpired() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.warp(expiry + 1);

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.WithdrawalHashExpired.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterPaymentDoesNotBelongToRecipient() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, userPrivateKey);

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.PaymentDoesNotBelongToRecipient.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, user, v, r, s);
    }

    function testEarlyWithdrawByArbiterMismatchedArrays() public {
        uint256[] memory paymentIDs = new uint256[](2);
        paymentIDs[0] = 0;
        paymentIDs[0] = 1;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.MismatchedEarlyWithdrawalArrays.selector);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testEarlyWithdrawByArbiterUnauthorized() public {
        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(user);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);

        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);
    }

    function testUpdateRefundTo() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(refundTo);
        refundProtocol.updateRefundTo(0, refundTo2);

        (,,, address refundAddr,,,,, bytes32 wcH) = refundProtocol.payments(0);
        assertEq(refundAddr, refundTo2);
        assertEq(wcH, bytes32(0));
    }

    function testUpdateRefundToZeroAddress() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(refundTo);
        vm.expectRevert(RefundProtocol.RefundToIsZeroAddress.selector);
        refundProtocol.updateRefundTo(0, address(0));
    }

    function testUpdateRefundToUnauthorized() public {
        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(receiver);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.updateRefundTo(0, receiver);
    }

    function testRefundByRecipient() public {
        // Use lockup so refund window is open
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(owner);
        refundProtocol.refundByRecipient(0);

        assertEq(usdc.balanceOf(refundTo), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 0);
        assertEq(refundProtocol.balances(receiver), 0);
    }

    function testRefundByRecipientUnauthorized() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        refundProtocol.refundByRecipient(0);
    }

    function testRefundByArbiter() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(arbiter);
        refundProtocol.refundByArbiter(0);

        assertEq(usdc.balanceOf(refundTo), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 0);
        assertEq(refundProtocol.balances(receiver), 0);
    }

    function testRefundByArbiterWhenArbiterFundsAreUsed() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;

        // Early withdraw so balance goes to zero but payment still has lockup window open
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        vm.startPrank(arbiter);
        refundProtocol.depositArbiterFunds(100);

        refundProtocol.refundByArbiter(0);

        assertEq(usdc.balanceOf(refundTo), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 0);
        assertEq(refundProtocol.balances(receiver), 0);
        assertEq(refundProtocol.balances(arbiter), 0);
        assertEq(refundProtocol.debts(receiver), 100);
    }

    function testRefundByArbiterUnauthorized() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        vm.prank(user);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.refundByArbiter(0);
    }

    function testSettleDebt() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        vm.startPrank(arbiter);
        refundProtocol.depositArbiterFunds(100);

        refundProtocol.refundByArbiter(0);
        vm.stopPrank();

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));
        vm.startPrank(arbiter);
        refundProtocol.settleDebt(receiver);

        assertEq(usdc.balanceOf(address(refundProtocol)), 100);
        assertEq(refundProtocol.balances(receiver), 0);
        assertEq(refundProtocol.balances(arbiter), 100);
        assertEq(refundProtocol.debts(receiver), 0);
    }

    function testSettleDebtPartially() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 100;
        uint256 feeAmount = 0;

        (uint8 v, bytes32 r, bytes32 s) =
            _generateEarlyWithdrawalSignature(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiverPrivateKey);

        vm.prank(arbiter);
        refundProtocol.earlyWithdrawByArbiter(paymentIDs, withdrawalAmounts, feeAmount, expiry, 0, receiver, v, r, s);

        vm.startPrank(arbiter);
        refundProtocol.depositArbiterFunds(100);

        refundProtocol.refundByArbiter(0);
        vm.stopPrank();

        vm.prank(user);
        refundProtocol.pay(receiver, 50, refundTo, bytes32(0));
        vm.startPrank(arbiter);
        refundProtocol.settleDebt(receiver);

        assertEq(usdc.balanceOf(address(refundProtocol)), 50);
        assertEq(refundProtocol.balances(receiver), 0);
        assertEq(refundProtocol.balances(arbiter), 50);
        assertEq(refundProtocol.debts(receiver), 50);
    }

    // ========== Settlement Finality Tests ==========

    function testRefundByRecipientAfterExpiry() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Warp past releaseTimestamp (refund expiry)
        vm.warp(block.timestamp + 3600);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.RefundWindowExpired.selector, 0));
        refundProtocol.refundByRecipient(0);
    }

    function testRefundByArbiterAfterExpiry() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Warp past releaseTimestamp (refund expiry)
        vm.warp(block.timestamp + 3600);

        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.RefundWindowExpired.selector, 0));
        refundProtocol.refundByArbiter(0);
    }

    function testRefundByRecipientDuringLockup() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Refund during lockup (before releaseTimestamp) should succeed
        vm.warp(block.timestamp + 1800); // halfway through lockup

        vm.prank(owner);
        refundProtocol.refundByRecipient(0);

        assertEq(usdc.balanceOf(refundTo), 100);
        assertEq(refundProtocol.balances(receiver), 0);
    }

    function testRefundByArbiterDuringLockup() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Refund during lockup should succeed
        vm.warp(block.timestamp + 1800);

        vm.prank(arbiter);
        refundProtocol.refundByArbiter(0);

        assertEq(usdc.balanceOf(refundTo), 100);
        assertEq(refundProtocol.balances(receiver), 0);
    }

    // ========== Payer Reclaim Tests ==========

    function testReclaimAfterGracePeriod() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256 reclaimGracePeriod = refundProtocol.RECLAIM_GRACE_PERIOD();

        // Warp past lockup + grace period
        vm.warp(block.timestamp + 3600 + reclaimGracePeriod);

        vm.prank(user);
        refundProtocol.reclaim(0);

        assertEq(usdc.balanceOf(user), 1000); // 1000 minted - 100 paid + 100 reclaimed
        assertEq(refundProtocol.balances(receiver), 0);
    }

    function testReclaimBeforeGracePeriod() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Warp past lockup but not past grace period
        vm.warp(block.timestamp + 3600 + 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.ReclaimNotYetAvailable.selector, 0));
        refundProtocol.reclaim(0);
    }

    function testReclaimAfterWithdraw() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Merchant withdraws after lockup
        vm.warp(block.timestamp + 3600);
        uint256[] memory paymentIDs = new uint256[](1);
        paymentIDs[0] = 0;
        vm.prank(receiver);
        refundProtocol.withdraw(paymentIDs);

        uint256 reclaimGracePeriod = refundProtocol.RECLAIM_GRACE_PERIOD();
        vm.warp(block.timestamp + reclaimGracePeriod);

        // Payer tries to reclaim but no balance left (withdrawnAmount == amount)
        vm.prank(user);
        vm.expectRevert(RefundProtocol.InsufficientFunds.selector);
        refundProtocol.reclaim(0);
    }

    function testReclaimAfterRefund() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        // Refund during lockup (POS admin / protocol owner)
        vm.prank(owner);
        refundProtocol.refundByRecipient(0);

        uint256 reclaimGracePeriod = refundProtocol.RECLAIM_GRACE_PERIOD();
        vm.warp(block.timestamp + 3600 + reclaimGracePeriod);

        // Already refunded
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RefundProtocol.PaymentRefunded.selector, 0));
        refundProtocol.reclaim(0);
    }

    function testReclaimUnauthorized() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        vm.prank(user);
        refundProtocol.pay(receiver, 100, refundTo, bytes32(0));

        uint256 reclaimGracePeriod = refundProtocol.RECLAIM_GRACE_PERIOD();
        vm.warp(block.timestamp + 3600 + reclaimGracePeriod);

        // Non-payer tries to reclaim
        vm.prank(receiver);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.reclaim(0);
    }

    function testPayWithWcHashSetsMapping() public {
        bytes32 h = keccak256(bytes("wc-pay-123"));
        vm.startPrank(user);
        refundProtocol.pay(receiver, 100, refundTo, h);
        vm.stopPrank();
        assertEq(refundProtocol.wcHashToPaymentId(h), 1);
        assertEq(refundProtocol.paymentIdForWcHash(h), 0);
        (address gPayer, uint256 gAmount) = refundProtocol.getInfo(h);
        assertEq(gPayer, user);
        assertEq(gAmount, 100);
        (,,,,,,, address payer, bytes32 stored) = refundProtocol.payments(0);
        assertEq(stored, h);
        assertEq(payer, user);
    }

    function testGetInfoUnknownWcHashReverts() public {
        bytes32 h = keccak256(bytes("never-linked"));
        vm.expectRevert(RefundProtocol.WcPaymentHashUnknown.selector);
        refundProtocol.getInfo(h);
    }

    function testPaymentIdForWcHashUnknownReverts() public {
        bytes32 h = keccak256(bytes("never-linked"));
        vm.expectRevert(RefundProtocol.WcPaymentHashUnknown.selector);
        refundProtocol.paymentIdForWcHash(h);
    }

    function testGetInfoResolvesCorrectPaymentWhenNotFirstNonce() public {
        bytes32 h1 = keccak256(bytes("wc-1"));
        bytes32 h2 = keccak256(bytes("wc-2"));
        vm.startPrank(user);
        refundProtocol.pay(receiver, 100, refundTo, h1);
        refundProtocol.pay(receiver, 250, refundTo, h2);
        vm.stopPrank();
        assertEq(refundProtocol.paymentIdForWcHash(h1), 0);
        assertEq(refundProtocol.paymentIdForWcHash(h2), 1);
        (address p1, uint256 a1) = refundProtocol.getInfo(h1);
        (address p2, uint256 a2) = refundProtocol.getInfo(h2);
        assertEq(p1, user);
        assertEq(a1, 100);
        assertEq(p2, user);
        assertEq(a2, 250);
    }

    function testPayDuplicateWcHashReverts() public {
        bytes32 h = keccak256(bytes("same-id"));
        vm.startPrank(user);
        refundProtocol.pay(receiver, 100, refundTo, h);
        vm.expectRevert(RefundProtocol.WcPaymentIdAlreadyUsed.selector);
        refundProtocol.pay(receiver, 100, refundTo, h);
        vm.stopPrank();
    }

    function testPayAsRecipientLinksWcHashAndGetInfo() public {
        bytes32 h = keccak256(bytes("wc-settled-off-chain"));
        usdc.mint(receiver, 500);
        vm.startPrank(receiver);
        usdc.approve(address(refundProtocol), 500);
        refundProtocol.payAsRecipient(user, 100, refundTo, h);
        vm.stopPrank();
        (address p, uint256 a) = refundProtocol.getInfo(h);
        assertEq(p, user);
        assertEq(a, 100);
        assertEq(refundProtocol.balances(receiver), 100);
        assertEq(refundProtocol.paymentIdForWcHash(h), 0);
    }

    function testPayAsRecipientPayerZeroReverts() public {
        vm.startPrank(receiver);
        vm.expectRevert(RefundProtocol.PayerIsZeroAddress.selector);
        refundProtocol.payAsRecipient(address(0), 100, refundTo, bytes32(0));
        vm.stopPrank();
    }

    function testPayAsRecipientDuplicateWcHashReverts() public {
        bytes32 h = keccak256(bytes("wc-dup-recipient"));
        usdc.mint(receiver, 500);
        vm.startPrank(receiver);
        usdc.approve(address(refundProtocol), 500);
        refundProtocol.payAsRecipient(user, 100, refundTo, h);
        vm.expectRevert(RefundProtocol.WcPaymentIdAlreadyUsed.selector);
        refundProtocol.payAsRecipient(user, 100, refundTo, h);
        vm.stopPrank();
    }

    function testPayAsRecipientPayerCanReclaim() public {
        vm.prank(arbiter);
        refundProtocol.setLockupSeconds(receiver, 3600);

        usdc.mint(receiver, 500);
        vm.startPrank(receiver);
        usdc.approve(address(refundProtocol), 500);
        refundProtocol.payAsRecipient(user, 100, refundTo, bytes32(0));
        vm.stopPrank();

        uint256 reclaimGracePeriod = refundProtocol.RECLAIM_GRACE_PERIOD();
        vm.warp(block.timestamp + 3600 + reclaimGracePeriod);

        uint256 userBalBefore = usdc.balanceOf(user);
        vm.prank(user);
        refundProtocol.reclaim(0);
        assertEq(usdc.balanceOf(user), userBalBefore + 100);
    }

    function testPayFromContractVaultCreditsMerchantRecipient() public {
        bytes32 h = keccak256(bytes("wc-vault-escrow"));
        usdc.mint(address(vault), 500);
        vault.escrowForMerchant(refundProtocol, IERC20(address(usdc)), receiver, user, 100, refundTo, h);
        (address p, uint256 a) = refundProtocol.getInfo(h);
        assertEq(p, user);
        assertEq(a, 100);
        assertEq(refundProtocol.balances(receiver), 100);
        assertEq(usdc.balanceOf(address(vault)), 400);
        assertEq(usdc.balanceOf(address(refundProtocol)), 100);
    }

    function testPayFromContractRecipientZeroReverts() public {
        usdc.mint(address(vault), 500);
        vm.expectRevert(RefundProtocol.RecipientIsZeroAddress.selector);
        vault.escrowForMerchant(
            refundProtocol, IERC20(address(usdc)), address(0), user, 100, refundTo, bytes32(0)
        );
    }

    function testRegisterPaymentArbiterCreditsEscrowWithoutTransfer() public {
        bytes32 h = keccak256(bytes("wc-arbiter-registered"));
        usdc.mint(address(refundProtocol), 100);
        vm.prank(arbiter);
        refundProtocol.registerPayment(user, receiver, 100, refundTo, h);
        (address p, uint256 a) = refundProtocol.getInfo(h);
        assertEq(p, user);
        assertEq(a, 100);
        assertEq(refundProtocol.balances(receiver), 100);
        assertEq(usdc.balanceOf(address(refundProtocol)), 100);
    }

    function testRegisterPaymentNonArbiterReverts() public {
        vm.prank(user);
        vm.expectRevert(RefundProtocol.CallerNotAllowed.selector);
        refundProtocol.registerPayment(user, receiver, 100, refundTo, bytes32(0));
    }

    function testRegisterPaymentFromZeroReverts() public {
        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.PayerIsZeroAddress.selector);
        refundProtocol.registerPayment(address(0), receiver, 100, refundTo, bytes32(0));
    }

    function testRegisterPaymentRecipientZeroReverts() public {
        vm.prank(arbiter);
        vm.expectRevert(RefundProtocol.RecipientIsZeroAddress.selector);
        refundProtocol.registerPayment(user, address(0), 100, refundTo, bytes32(0));
    }

    function testRegisterPaymentDuplicateWcHashReverts() public {
        bytes32 h = keccak256(bytes("wc-dup-arbiter"));
        usdc.mint(address(refundProtocol), 200);
        vm.startPrank(arbiter);
        refundProtocol.registerPayment(user, receiver, 100, refundTo, h);
        vm.expectRevert(RefundProtocol.WcPaymentIdAlreadyUsed.selector);
        refundProtocol.registerPayment(user, receiver, 100, refundTo, h);
        vm.stopPrank();
    }

    function _generateEarlyWithdrawalSignature(
        uint256[] memory paymentIDs,
        uint256[] memory withdrawalAmounts,
        uint256 feeAmount,
        uint256 _expiry,
        uint256 salt,
        uint256 signerPrivateKey
    ) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 withdrawalInfoHash =
            refundProtocol.hashEarlyWithdrawalInfo(paymentIDs, withdrawalAmounts, feeAmount, _expiry, salt);
        (v, r, s) = vm.sign(signerPrivateKey, withdrawalInfoHash);
    }
}
