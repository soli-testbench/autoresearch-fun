// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAttestationVerifier} from "./IAttestationVerifier.sol";

/// @notice Minimal ERC-20 interface (TIP-20 compatible subset).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title BenchmarkMarket
/// @notice Permissionless market for benchmark improvements verified via enclave attestations.
///         No owner, no upgrade proxy, no pause.
contract BenchmarkMarket {
    // ------------------------------------------------------------------
    // Immutables
    // ------------------------------------------------------------------
    IAttestationVerifier public immutable verifier;
    IERC20 public immutable usdc;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    uint256 public nextBenchmarkId;
    uint256 public nextThresholdId;

    struct Benchmark {
        address creator;
        uint256 bestScore;
        mapping(bytes32 => bool) allowedPcr0s;
    }

    struct Threshold {
        uint256 benchmarkId;
        uint256 scoreTarget;
        uint256 deadline;
        uint256 amount;
        address poster;
        bool settled;
        bool refunded;
    }

    mapping(uint256 => Benchmark) internal _benchmarks;
    mapping(uint256 => Threshold) public thresholds;
    mapping(uint256 => uint256[]) internal _benchmarkThresholds;
    mapping(bytes32 => bool) public usedNonces;

    /// @dev Reentrancy guard state.
    bool private _locked;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event BenchmarkCreated(uint256 indexed benchmarkId, address indexed creator, bytes32 pcr0);
    event OracleRegistered(uint256 indexed benchmarkId, bytes32 pcr0);
    event ThresholdPosted(
        uint256 indexed thresholdId,
        uint256 indexed benchmarkId,
        uint256 scoreTarget,
        uint256 deadline,
        uint256 amount
    );
    event ImprovementSubmitted(uint256 indexed benchmarkId, uint256 score, address indexed agent);
    event ThresholdSettled(uint256 indexed thresholdId, address indexed agent, uint256 amount);
    event RefundClaimed(uint256 indexed thresholdId, address indexed poster, uint256 amount);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    constructor(address verifier_, address usdc_) {
        verifier = IAttestationVerifier(verifier_);
        usdc = IERC20(usdc_);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    function getBenchmark(uint256 benchmarkId) external view returns (address creator, uint256 bestScore) {
        Benchmark storage b = _benchmarks[benchmarkId];
        return (b.creator, b.bestScore);
    }

    function isPcr0Allowed(uint256 benchmarkId, bytes32 pcr0) external view returns (bool) {
        return _benchmarks[benchmarkId].allowedPcr0s[pcr0];
    }

    function getBenchmarkThresholdCount(uint256 benchmarkId) external view returns (uint256) {
        return _benchmarkThresholds[benchmarkId].length;
    }

    function getBenchmarkThresholdId(uint256 benchmarkId, uint256 index) external view returns (uint256) {
        return _benchmarkThresholds[benchmarkId][index];
    }

    // ------------------------------------------------------------------
    // Mutations
    // ------------------------------------------------------------------

    /// @notice Create a new benchmark with an initial allowed PCR0 value.
    function createBenchmark(bytes32 pcr0) external returns (uint256 benchmarkId) {
        benchmarkId = nextBenchmarkId++;
        Benchmark storage b = _benchmarks[benchmarkId];
        b.creator = msg.sender;
        b.allowedPcr0s[pcr0] = true;
        emit BenchmarkCreated(benchmarkId, msg.sender, pcr0);
    }

    /// @notice Register an additional PCR0 value for an existing benchmark (creator only).
    function registerOracle(uint256 benchmarkId, bytes32 pcr0) external {
        Benchmark storage b = _benchmarks[benchmarkId];
        require(b.creator != address(0), "benchmark does not exist");
        require(b.creator == msg.sender, "not creator");
        b.allowedPcr0s[pcr0] = true;
        emit OracleRegistered(benchmarkId, pcr0);
    }

    /// @notice Post a bounty threshold: deposit USDC that pays the agent if the score target
    ///         is crossed before the deadline.
    function postThreshold(
        uint256 benchmarkId,
        uint256 scoreTarget,
        uint256 deadline,
        uint256 amount
    ) external {
        require(_benchmarks[benchmarkId].creator != address(0), "benchmark does not exist");
        require(deadline > block.timestamp, "deadline must be in future");
        require(amount > 0, "amount must be positive");
        require(usdc.transferFrom(msg.sender, address(this), amount), "transfer failed");

        uint256 thresholdId = nextThresholdId++;
        thresholds[thresholdId] = Threshold({
            benchmarkId: benchmarkId,
            scoreTarget: scoreTarget,
            deadline: deadline,
            amount: amount,
            poster: msg.sender,
            settled: false,
            refunded: false
        });
        _benchmarkThresholds[benchmarkId].push(thresholdId);
        emit ThresholdPosted(thresholdId, benchmarkId, scoreTarget, deadline, amount);
    }

    /// @notice Submit a verified improvement. Decodes attestation userData, checks PCR0
    ///         (cryptographically bound in the signed attestation), deduplicates nonces,
    ///         verifies score improvement, settles crossed thresholds, and pays the agent.
    /// @dev userData ABI layout:
    ///      (uint256 benchmarkId, uint256 score, bytes32 commitCid, address agent,
    ///       bytes32 nonce, uint64 elapsedSeconds, bytes32 pcr0)
    ///      PCR0 is included in the signed userData so it cannot be forged by the caller.
    function submitImprovement(
        bytes calldata attestationTbs,
        bytes calldata sig
    ) external {
        require(!_locked, "reentrant call");
        _locked = true;

        bytes memory userData = verifier.verify(attestationTbs, sig);

        (uint256 benchmarkId, uint256 score, , address agent, bytes32 nonce, , bytes32 pcr0) =
            abi.decode(userData, (uint256, uint256, bytes32, address, bytes32, uint64, bytes32));

        Benchmark storage b = _benchmarks[benchmarkId];
        require(b.creator != address(0), "benchmark does not exist");
        require(b.allowedPcr0s[pcr0], "pcr0 not registered");
        require(!usedNonces[nonce], "nonce already used");
        usedNonces[nonce] = true;

        uint256 oldBest = b.bestScore;
        require(score > oldBest, "score not an improvement");
        b.bestScore = score;

        // Settle crossed thresholds
        uint256[] storage tids = _benchmarkThresholds[benchmarkId];
        uint256 len = tids.length;
        for (uint256 i = 0; i < len; i++) {
            Threshold storage t = thresholds[tids[i]];
            if (
                !t.settled
                    && !t.refunded
                    && t.scoreTarget <= score
                    && t.scoreTarget > oldBest
                    && block.timestamp <= t.deadline
            ) {
                t.settled = true;
                require(usdc.transfer(agent, t.amount), "settlement transfer failed");
                emit ThresholdSettled(tids[i], agent, t.amount);
            }
        }

        _locked = false;
        emit ImprovementSubmitted(benchmarkId, score, agent);
    }

    /// @notice Claim a refund for a threshold whose deadline has passed without being crossed.
    function claimRefund(uint256 thresholdId) external {
        Threshold storage t = thresholds[thresholdId];
        require(t.poster != address(0), "threshold does not exist");
        require(t.poster == msg.sender, "not poster");
        require(!t.settled, "already settled");
        require(!t.refunded, "already refunded");
        require(block.timestamp > t.deadline, "deadline not passed");

        t.refunded = true;
        require(usdc.transfer(msg.sender, t.amount), "refund transfer failed");
        emit RefundClaimed(thresholdId, msg.sender, t.amount);
    }
}
