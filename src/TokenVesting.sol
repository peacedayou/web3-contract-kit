// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title TokenVesting
/// @notice Linear ERC-20 vesting with a cliff, for any number of beneficiaries.
/// @dev Each schedule is funded at creation. Revoking a schedule freezes what is
///      already vested (still claimable by the beneficiary) and refunds the rest
///      to the owner. Fee-on-transfer tokens are rejected.
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Schedule {
        address beneficiary;
        uint64 start;
        uint64 cliff; // absolute timestamp
        uint64 duration;
        bool revocable;
        bool revoked;
        uint256 total;
        uint256 released;
    }

    IERC20 public immutable token;

    /// @notice Tokens still owed to beneficiaries across all schedules.
    uint256 public totalCommitted;

    Schedule[] private _schedules;

    event ScheduleCreated(
        uint256 indexed id, address indexed beneficiary, uint256 amount, uint64 start, uint64 cliff, uint64 duration
    );
    event Released(uint256 indexed id, address indexed beneficiary, uint256 amount);
    event Revoked(uint256 indexed id, uint256 refunded);

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error UnsupportedToken();
    error UnknownSchedule();
    error NothingToRelease();
    error NotRevocable();
    error AlreadyRevoked();

    constructor(IERC20 token_, address owner_) Ownable(owner_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    /// @notice Creates and funds a schedule. The caller must have approved `amount`.
    function createSchedule(
        address beneficiary,
        uint64 start,
        uint64 cliffDuration,
        uint64 duration,
        uint256 amount,
        bool revocable
    ) external onlyOwner returns (uint256 id) {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (duration == 0 || cliffDuration > duration) revert InvalidDuration();

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.balanceOf(address(this)) - balanceBefore != amount) revert UnsupportedToken();

        id = _schedules.length;
        uint64 cliff = start + cliffDuration;
        _schedules.push(Schedule(beneficiary, start, cliff, duration, revocable, false, amount, 0));
        totalCommitted += amount;

        emit ScheduleCreated(id, beneficiary, amount, start, cliff, duration);
    }

    /// @notice Sends the releasable amount to the beneficiary. Callable by anyone.
    function release(uint256 id) external nonReentrant {
        Schedule storage s = _get(id);
        uint256 amount = _vested(s) - s.released;
        if (amount == 0) revert NothingToRelease();

        s.released += amount;
        totalCommitted -= amount;
        token.safeTransfer(s.beneficiary, amount);

        emit Released(id, s.beneficiary, amount);
    }

    /// @notice Stops a revocable schedule and refunds the unvested part to the owner.
    function revoke(uint256 id) external onlyOwner nonReentrant {
        Schedule storage s = _get(id);
        if (!s.revocable) revert NotRevocable();
        if (s.revoked) revert AlreadyRevoked();

        uint256 vested = _vested(s);
        uint256 refund = s.total - vested;
        s.total = vested;
        s.revoked = true;
        totalCommitted -= refund;

        if (refund > 0) token.safeTransfer(owner(), refund);
        emit Revoked(id, refund);
    }

    // ---------------------------------------------------------------- views

    function scheduleCount() external view returns (uint256) {
        return _schedules.length;
    }

    function getSchedule(uint256 id) external view returns (Schedule memory) {
        return _get(id);
    }

    function vestedAmount(uint256 id) external view returns (uint256) {
        return _vested(_get(id));
    }

    function releasableAmount(uint256 id) external view returns (uint256) {
        Schedule storage s = _get(id);
        return _vested(s) - s.released;
    }

    // ------------------------------------------------------------- internal

    function _get(uint256 id) private view returns (Schedule storage) {
        if (id >= _schedules.length) revert UnknownSchedule();
        return _schedules[id];
    }

    function _vested(Schedule storage s) private view returns (uint256) {
        if (s.revoked) return s.total;
        if (block.timestamp < s.cliff) return 0;
        uint256 end = uint256(s.start) + s.duration;
        if (block.timestamp >= end) return s.total;
        return Math.mulDiv(s.total, block.timestamp - s.start, s.duration);
    }
}
