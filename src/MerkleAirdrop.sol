// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title MerkleAirdrop
/// @notice Gas-efficient ERC-20 airdrop: eligible accounts claim with a Merkle proof.
/// @dev Leaves are `keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))))`,
///      the format produced by OpenZeppelin's `StandardMerkleTree` (JavaScript library).
///      Claims are tracked in a bitmap. Unclaimed tokens can be swept after the deadline.
contract MerkleAirdrop is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    bytes32 public immutable merkleRoot;
    uint64 public immutable deadline;

    mapping(uint256 => uint256) private _claimedBitMap;

    event Claimed(uint256 indexed index, address indexed account, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    error ZeroAddress();
    error AlreadyClaimed();
    error InvalidProof();
    error ClaimWindowClosed();
    error ClaimWindowOpen();

    constructor(IERC20 token_, bytes32 merkleRoot_, uint64 deadline_, address owner_) Ownable(owner_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
        merkleRoot = merkleRoot_;
        deadline = deadline_;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 word = _claimedBitMap[index / 256];
        uint256 mask = 1 << (index % 256);
        return word & mask != 0;
    }

    /// @notice Claims `amount` tokens for `account`. Anyone can submit the claim;
    ///         tokens always go to `account`.
    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof) external {
        if (block.timestamp > deadline) revert ClaimWindowClosed();
        if (isClaimed(index)) revert AlreadyClaimed();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        if (!MerkleProof.verifyCalldata(proof, merkleRoot, leaf)) revert InvalidProof();

        _claimedBitMap[index / 256] |= 1 << (index % 256);
        token.safeTransfer(account, amount);

        emit Claimed(index, account, amount);
    }

    /// @notice Recovers unclaimed tokens once the claim window is closed.
    function sweep(address to) external onlyOwner {
        if (block.timestamp <= deadline) revert ClaimWindowOpen();
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);
        emit Swept(to, amount);
    }
}
