// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SimpleMultisig
/// @notice M-of-N wallet: owners submit, confirm and execute transactions
///         (ETH transfers or arbitrary contract calls).
/// @dev The threshold can only be changed by the wallet itself, i.e. through a
///      transaction approved by the owners. For large treasuries, prefer an
///      audited production wallet such as Safe.
contract SimpleMultisig {
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    address[] private _owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;

    Transaction[] private _transactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    event Deposit(address indexed from, uint256 amount);
    event Submitted(uint256 indexed id, address indexed owner, address indexed to, uint256 value, bytes data);
    event Confirmed(uint256 indexed id, address indexed owner);
    event ConfirmationRevoked(uint256 indexed id, address indexed owner);
    event Executed(uint256 indexed id);
    event ThresholdChanged(uint256 threshold);

    error NotOwner();
    error NotSelf();
    error InvalidOwners();
    error InvalidThreshold();
    error UnknownTransaction();
    error AlreadyExecuted();
    error AlreadyConfirmed();
    error NotConfirmed();
    error NotEnoughConfirmations();
    error ExecutionFailed(bytes reason);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    modifier pending(uint256 id) {
        if (id >= _transactions.length) revert UnknownTransaction();
        if (_transactions[id].executed) revert AlreadyExecuted();
        _;
    }

    constructor(address[] memory owners_, uint256 threshold_) {
        if (owners_.length == 0) revert InvalidOwners();
        if (threshold_ == 0 || threshold_ > owners_.length) revert InvalidThreshold();
        for (uint256 i = 0; i < owners_.length; i++) {
            address o = owners_[i];
            if (o == address(0) || isOwner[o]) revert InvalidOwners();
            isOwner[o] = true;
            _owners.push(o);
        }
        threshold = threshold_;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Proposes a transaction; the submitter's confirmation is counted.
    function submit(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256 id) {
        id = _transactions.length;
        _transactions.push(Transaction(to, value, data, false, 0));
        emit Submitted(id, msg.sender, to, value, data);
        _confirm(id);
    }

    function confirm(uint256 id) external onlyOwner pending(id) {
        _confirm(id);
    }

    function revokeConfirmation(uint256 id) external onlyOwner pending(id) {
        if (!isConfirmed[id][msg.sender]) revert NotConfirmed();
        isConfirmed[id][msg.sender] = false;
        _transactions[id].confirmations -= 1;
        emit ConfirmationRevoked(id, msg.sender);
    }

    /// @notice Executes a transaction once it has enough confirmations.
    /// @dev State is updated before the external call; a failed call reverts everything.
    function execute(uint256 id) external onlyOwner pending(id) {
        Transaction storage t = _transactions[id];
        if (t.confirmations < threshold) revert NotEnoughConfirmations();

        t.executed = true;
        (bool ok, bytes memory reason) = t.to.call{value: t.value}(t.data);
        if (!ok) revert ExecutionFailed(reason);

        emit Executed(id);
    }

    /// @notice Changes the threshold. Must be called through an approved transaction.
    function changeThreshold(uint256 newThreshold) external onlySelf {
        if (newThreshold == 0 || newThreshold > _owners.length) revert InvalidThreshold();
        threshold = newThreshold;
        emit ThresholdChanged(newThreshold);
    }

    // ---------------------------------------------------------------- views

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function transactionCount() external view returns (uint256) {
        return _transactions.length;
    }

    function getTransaction(uint256 id) external view returns (Transaction memory) {
        if (id >= _transactions.length) revert UnknownTransaction();
        return _transactions[id];
    }

    function _confirm(uint256 id) private {
        if (isConfirmed[id][msg.sender]) revert AlreadyConfirmed();
        isConfirmed[id][msg.sender] = true;
        _transactions[id].confirmations += 1;
        emit Confirmed(id, msg.sender);
    }
}
