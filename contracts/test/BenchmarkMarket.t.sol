// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BenchmarkMarket} from "../src/BenchmarkMarket.sol";
import {MockVerifier} from "../src/MockVerifier.sol";
import {MockERC20} from "./MockERC20.sol";

contract BenchmarkMarketTest is Test {
    BenchmarkMarket market;
    MockVerifier verifier;
    MockERC20 usdc;

    address creator = address(0xC0);
    address poster = address(0xD0);
    address agent = address(0xA0);
    address other = address(0xE0);

    bytes32 pcr0 = keccak256("pcr0");
    bytes32 pcr0Other = keccak256("pcr0-other");
    bytes32 nonce1 = keccak256("nonce1");
    bytes32 nonce2 = keccak256("nonce2");
    bytes32 commitCid = keccak256("commit");

    function setUp() public {
        verifier = new MockVerifier();
        usdc = new MockERC20();
        market = new BenchmarkMarket(address(verifier), address(usdc));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _encodeUserData(
        uint256 benchmarkId,
        uint256 score,
        bytes32 cid,
        address agentAddr,
        bytes32 n,
        uint64 elapsed
    ) internal pure returns (bytes memory) {
        return abi.encode(benchmarkId, score, cid, agentAddr, n, elapsed);
    }

    function _createBenchmark() internal returns (uint256) {
        vm.prank(creator);
        return market.createBenchmark(pcr0);
    }

    function _fundAndApprove(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(market), amount);
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(address(market.verifier()), address(verifier));
        assertEq(address(market.usdc()), address(usdc));
    }

    // ------------------------------------------------------------------
    // createBenchmark
    // ------------------------------------------------------------------

    function test_createBenchmark() public {
        vm.prank(creator);
        uint256 id = market.createBenchmark(pcr0);
        assertEq(id, 0);

        (address c, uint256 best) = market.getBenchmark(id);
        assertEq(c, creator);
        assertEq(best, 0);
        assertTrue(market.isPcr0Allowed(id, pcr0));
    }

    function test_createBenchmark_incrementsId() public {
        vm.prank(creator);
        uint256 id1 = market.createBenchmark(pcr0);
        vm.prank(creator);
        uint256 id2 = market.createBenchmark(pcr0);
        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    // ------------------------------------------------------------------
    // registerOracle
    // ------------------------------------------------------------------

    function test_registerOracle() public {
        uint256 id = _createBenchmark();
        vm.prank(creator);
        market.registerOracle(id, pcr0Other);
        assertTrue(market.isPcr0Allowed(id, pcr0Other));
    }

    function test_registerOracle_revert_notExist() public {
        vm.prank(creator);
        vm.expectRevert("benchmark does not exist");
        market.registerOracle(999, pcr0Other);
    }

    function test_registerOracle_revert_notCreator() public {
        uint256 id = _createBenchmark();
        vm.prank(other);
        vm.expectRevert("not creator");
        market.registerOracle(id, pcr0Other);
    }

    // ------------------------------------------------------------------
    // postThreshold
    // ------------------------------------------------------------------

    function test_postThreshold() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);

        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);

        (
            uint256 benchmarkId,
            uint256 scoreTarget,
            uint256 deadline,
            uint256 amount,
            address p,
            bool settled,
            bool refunded
        ) = market.thresholds(0);

        assertEq(benchmarkId, bmId);
        assertEq(scoreTarget, 100);
        assertEq(deadline, block.timestamp + 1 days);
        assertEq(amount, 1000);
        assertEq(p, poster);
        assertFalse(settled);
        assertFalse(refunded);
        assertEq(usdc.balanceOf(address(market)), 1000);
    }

    function test_postThreshold_revert_benchmarkNotExist() public {
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        vm.expectRevert("benchmark does not exist");
        market.postThreshold(999, 100, block.timestamp + 1 days, 1000);
    }

    function test_postThreshold_revert_deadlinePast() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.warp(1000);
        vm.prank(poster);
        vm.expectRevert("deadline must be in future");
        market.postThreshold(bmId, 100, 999, 1000);
    }

    function test_postThreshold_revert_zeroAmount() public {
        uint256 bmId = _createBenchmark();
        vm.prank(poster);
        vm.expectRevert("amount must be positive");
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 0);
    }

    function test_postThreshold_revert_transferFailed() public {
        uint256 bmId = _createBenchmark();
        // Don't approve or fund → transferFrom fails
        usdc.setShouldFailTransfer(true);
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        vm.expectRevert("transfer failed");
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);
    }

    // ------------------------------------------------------------------
    // submitImprovement
    // ------------------------------------------------------------------

    function test_submitImprovement_basic() public {
        uint256 bmId = _createBenchmark();

        bytes memory ud = _encodeUserData(bmId, 500, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);

        market.submitImprovement("tbs", "sig", pcr0);

        (, uint256 best) = market.getBenchmark(bmId);
        assertEq(best, 500);
        assertTrue(market.usedNonces(nonce1));
    }

    function test_submitImprovement_revert_benchmarkNotExist() public {
        bytes memory ud = _encodeUserData(999, 500, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        vm.expectRevert("benchmark does not exist");
        market.submitImprovement("tbs", "sig", pcr0);
    }

    function test_submitImprovement_revert_pcr0NotRegistered() public {
        uint256 bmId = _createBenchmark();
        bytes memory ud = _encodeUserData(bmId, 500, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        vm.expectRevert("pcr0 not registered");
        market.submitImprovement("tbs", "sig", keccak256("bad-pcr0"));
    }

    function test_submitImprovement_revert_nonceAlreadyUsed() public {
        uint256 bmId = _createBenchmark();

        bytes memory ud = _encodeUserData(bmId, 500, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // Try again with same nonce but higher score
        ud = _encodeUserData(bmId, 600, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        vm.expectRevert("nonce already used");
        market.submitImprovement("tbs", "sig", pcr0);
    }

    function test_submitImprovement_revert_scoreNotImprovement() public {
        uint256 bmId = _createBenchmark();

        // First improvement
        bytes memory ud = _encodeUserData(bmId, 500, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // Second with equal score → not an improvement
        ud = _encodeUserData(bmId, 500, commitCid, agent, nonce2, 60);
        verifier.setUserData(ud);
        vm.expectRevert("score not an improvement");
        market.submitImprovement("tbs", "sig", pcr0);
    }

    function test_submitImprovement_settlesThreshold() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);

        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (,,,,, bool settled,) = market.thresholds(0);
        assertTrue(settled);
        assertEq(usdc.balanceOf(agent), 1000);
    }

    function test_submitImprovement_noThresholds() public {
        // Improvement with no thresholds posted (empty loop)
        uint256 bmId = _createBenchmark();
        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (, uint256 best) = market.getBenchmark(bmId);
        assertEq(best, 200);
    }

    function test_submitImprovement_skipAlreadySettled() public {
        uint256 bmId = _createBenchmark();

        // Post threshold and settle it
        _fundAndApprove(poster, 2000);
        vm.prank(poster);
        market.postThreshold(bmId, 50, block.timestamp + 1 days, 1000);

        bytes memory ud = _encodeUserData(bmId, 100, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // Threshold 0 is now settled. Post another threshold and submit new improvement.
        vm.prank(poster);
        market.postThreshold(bmId, 150, block.timestamp + 1 days, 1000);

        ud = _encodeUserData(bmId, 200, commitCid, agent, nonce2, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // Threshold 0 still settled (not double-paid), threshold 1 settled
        (,,,,, bool s0,) = market.thresholds(0);
        (,,,,, bool s1,) = market.thresholds(1);
        assertTrue(s0);
        assertTrue(s1);
        // Agent got 1000 from first settlement + 1000 from second
        assertEq(usdc.balanceOf(agent), 2000);
    }

    function test_submitImprovement_skipRefundedThreshold() public {
        uint256 bmId = _createBenchmark();

        vm.warp(1000);

        // Threshold A: will be refunded
        _fundAndApprove(poster, 2000);
        vm.prank(poster);
        market.postThreshold(bmId, 50, 2000, 1000);

        // Warp past A's deadline and refund
        vm.warp(2001);
        vm.prank(poster);
        market.claimRefund(0);

        // Threshold B: still active
        vm.prank(poster);
        market.postThreshold(bmId, 80, 5000, 1000);

        // Submit improvement that crosses both targets
        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // A was refunded → not settled again; B is settled
        (,,,,, bool sA, bool rA) = market.thresholds(0);
        (,,,,, bool sB,) = market.thresholds(1);
        assertFalse(sA);
        assertTrue(rA);
        assertTrue(sB);
        assertEq(usdc.balanceOf(agent), 1000);
    }

    function test_submitImprovement_skipScoreBelowTarget() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 500, block.timestamp + 1 days, 1000);

        // Score 200 < target 500 → not settled
        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (,,,,, bool s,) = market.thresholds(0);
        assertFalse(s);
        assertEq(usdc.balanceOf(agent), 0);
    }

    function test_submitImprovement_skipTargetAlreadyMetByOldBest() public {
        uint256 bmId = _createBenchmark();

        // Submit first improvement to set bestScore = 200
        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        // Post threshold with target = 100 (already below bestScore)
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);

        // Submit another improvement: score = 300, oldBest = 200, target 100 <= 200 (oldBest) → skip
        ud = _encodeUserData(bmId, 300, commitCid, agent, nonce2, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (,,,,, bool s,) = market.thresholds(0);
        assertFalse(s);
    }

    function test_submitImprovement_skipDeadlinePassed() public {
        uint256 bmId = _createBenchmark();
        vm.warp(1000);

        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 50, 2000, 1000);

        // Warp past deadline
        vm.warp(2001);

        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (,,,,, bool s,) = market.thresholds(0);
        assertFalse(s);
        assertEq(usdc.balanceOf(agent), 0);
    }

    function test_submitImprovement_revert_settlementTransferFailed() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 50, block.timestamp + 1 days, 1000);

        // Make transfers fail
        usdc.setShouldFailTransfer(true);

        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        vm.expectRevert("settlement transfer failed");
        market.submitImprovement("tbs", "sig", pcr0);
    }

    function test_submitImprovement_multipleThresholdsMixed() public {
        uint256 bmId = _createBenchmark();
        vm.warp(1000);

        _fundAndApprove(poster, 3000);

        // Threshold 0: target 50, deadline 5000 → will be crossed
        vm.prank(poster);
        market.postThreshold(bmId, 50, 5000, 1000);

        // Threshold 1: target 500, deadline 5000 → score won't reach
        vm.prank(poster);
        market.postThreshold(bmId, 500, 5000, 1000);

        // Threshold 2: target 80, deadline 5000 → will be crossed
        vm.prank(poster);
        market.postThreshold(bmId, 80, 5000, 1000);

        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        (,,,,, bool s0,) = market.thresholds(0);
        (,,,,, bool s1,) = market.thresholds(1);
        (,,,,, bool s2,) = market.thresholds(2);
        assertTrue(s0);
        assertFalse(s1);
        assertTrue(s2);
        assertEq(usdc.balanceOf(agent), 2000);
    }

    // ------------------------------------------------------------------
    // claimRefund
    // ------------------------------------------------------------------

    function test_claimRefund() public {
        uint256 bmId = _createBenchmark();
        vm.warp(1000);

        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, 2000, 1000);

        vm.warp(2001);
        vm.prank(poster);
        market.claimRefund(0);

        (,,,,, bool settled, bool refunded) = market.thresholds(0);
        assertFalse(settled);
        assertTrue(refunded);
        assertEq(usdc.balanceOf(poster), 1000);
    }

    function test_claimRefund_revert_notExist() public {
        vm.prank(poster);
        vm.expectRevert("threshold does not exist");
        market.claimRefund(999);
    }

    function test_claimRefund_revert_notPoster() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);

        vm.warp(block.timestamp + 2 days);
        vm.prank(other);
        vm.expectRevert("not poster");
        market.claimRefund(0);
    }

    function test_claimRefund_revert_alreadySettled() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 50, block.timestamp + 1 days, 1000);

        // Settle it
        bytes memory ud = _encodeUserData(bmId, 200, commitCid, agent, nonce1, 60);
        verifier.setUserData(ud);
        market.submitImprovement("tbs", "sig", pcr0);

        vm.warp(block.timestamp + 2 days);
        vm.prank(poster);
        vm.expectRevert("already settled");
        market.claimRefund(0);
    }

    function test_claimRefund_revert_alreadyRefunded() public {
        uint256 bmId = _createBenchmark();
        vm.warp(1000);

        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, 2000, 1000);

        vm.warp(2001);
        vm.prank(poster);
        market.claimRefund(0);

        vm.prank(poster);
        vm.expectRevert("already refunded");
        market.claimRefund(0);
    }

    function test_claimRefund_revert_deadlineNotPassed() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);

        vm.prank(poster);
        vm.expectRevert("deadline not passed");
        market.claimRefund(0);
    }

    function test_claimRefund_revert_transferFailed() public {
        uint256 bmId = _createBenchmark();
        vm.warp(1000);

        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, 2000, 1000);

        vm.warp(2001);
        usdc.setShouldFailTransfer(true);
        vm.prank(poster);
        vm.expectRevert("refund transfer failed");
        market.claimRefund(0);
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------

    function test_getBenchmarkThresholdCount() public {
        uint256 bmId = _createBenchmark();
        assertEq(market.getBenchmarkThresholdCount(bmId), 0);

        _fundAndApprove(poster, 2000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);
        assertEq(market.getBenchmarkThresholdCount(bmId), 1);

        vm.prank(poster);
        market.postThreshold(bmId, 200, block.timestamp + 1 days, 1000);
        assertEq(market.getBenchmarkThresholdCount(bmId), 2);
    }

    function test_getBenchmarkThresholdId() public {
        uint256 bmId = _createBenchmark();
        _fundAndApprove(poster, 1000);
        vm.prank(poster);
        market.postThreshold(bmId, 100, block.timestamp + 1 days, 1000);
        assertEq(market.getBenchmarkThresholdId(bmId, 0), 0);
    }
}
