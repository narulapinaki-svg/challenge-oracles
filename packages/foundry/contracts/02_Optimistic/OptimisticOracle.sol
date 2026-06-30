// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract OptimisticOracle {
    enum State { Invalid, Asserted, Proposed, Disputed, Settled, Expired }

    error AssertionNotFound();
    error AssertionProposed();
    error InvalidValue();
    error InvalidTime();
    error ProposalDisputed();
    error NotProposedAssertion();
    error AlreadyClaimed();
    error AlreadySettled();
    error AwaitingDecider();
    error NotDisputedAssertion();
    error OnlyDecider();
    error OnlyOwner();
    error TransferFailed();

    struct EventAssertion {
        address asserter;
        address proposer;
        address disputer;
        bool proposedOutcome;
        bool resolvedOutcome;
        uint256 reward;
        uint256 bond;
        uint256 startTime;
        uint256 endTime;
        bool claimed;
        address winner;
        string description;
    }

    uint256 public constant MINIMUM_ASSERTION_WINDOW = 3 minutes;
    uint256 public constant DISPUTE_WINDOW = 3 minutes;
    address public decider;
    address public owner;
    uint256 public nextAssertionId = 1;
    mapping(uint256 => EventAssertion) public assertions;

    event EventAsserted(uint256 assertionId, address asserter, string description, uint256 reward);
    event OutcomeProposed(uint256 assertionId, address proposer, bool outcome);
    event OutcomeDisputed(uint256 assertionId, address disputer);
    event AssertionSettled(uint256 assertionId, bool outcome, address winner);
    event DeciderUpdated(address oldDecider, address newDecider);
    event RewardClaimed(uint256 assertionId, address winner, uint256 amount);
    event RefundClaimed(uint256 assertionId, address asserter, uint256 amount);

    modifier onlyDecider() {
        if (msg.sender != decider) revert OnlyDecider();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _decider) {
        decider = _decider;
        owner = msg.sender;
    }

    function setDecider(address _decider) external onlyOwner {
        address oldDecider = address(decider);
        decider = _decider;
        emit DeciderUpdated(oldDecider, _decider);
    }

    function getAssertion(uint256 assertionId) external view returns (EventAssertion memory) {
        return assertions[assertionId];
    }

    function assertEvent(string memory description, uint256 startTime, uint256 endTime)
        external
        payable
        returns (uint256)
    {
        if (msg.value == 0) revert InvalidValue();
        uint256 _startTime = startTime == 0 ? block.timestamp : startTime;
        uint256 _endTime = endTime == 0 ? _startTime + MINIMUM_ASSERTION_WINDOW : endTime;
        if (_endTime <= _startTime) revert InvalidTime();
        if (_endTime < _startTime + MINIMUM_ASSERTION_WINDOW) revert InvalidTime();

        uint256 assertionId = nextAssertionId++;
        assertions[assertionId] = EventAssertion({
            asserter: msg.sender,
            proposer: address(0),
            disputer: address(0),
            proposedOutcome: false,
            resolvedOutcome: false,
            reward: msg.value,
            bond: msg.value * 2,
            startTime: _startTime,
            endTime: _endTime,
            claimed: false,
            winner: address(0),
            description: description
        });

        emit EventAsserted(assertionId, msg.sender, description, msg.value);
        return assertionId;
    }

    function proposeOutcome(uint256 assertionId, bool outcome) external payable {
        EventAssertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert AssertionNotFound();
        if (a.proposer != address(0)) revert AssertionProposed();
        if (block.timestamp < a.startTime || block.timestamp > a.endTime) revert InvalidTime();
        if (msg.value != a.bond) revert InvalidValue();

        a.proposer = msg.sender;
        a.proposedOutcome = outcome;
        a.endTime = block.timestamp + DISPUTE_WINDOW;

        emit OutcomeProposed(assertionId, msg.sender, outcome);
    }

    function disputeOutcome(uint256 assertionId) external payable {
        EventAssertion storage a = assertions[assertionId];
        if (a.proposer == address(0)) revert NotProposedAssertion();
        if (a.disputer != address(0)) revert ProposalDisputed();
        if (block.timestamp > a.endTime) revert InvalidTime();
        if (msg.value != a.bond) revert InvalidValue();

        a.disputer = msg.sender;

        emit OutcomeDisputed(assertionId, msg.sender);
    }

    function claimUndisputedReward(uint256 assertionId) external {
        EventAssertion storage a = assertions[assertionId];
        if (a.proposer == address(0)) revert NotProposedAssertion();
        if (a.disputer != address(0)) revert ProposalDisputed();
        if (block.timestamp <= a.endTime) revert InvalidTime();
        if (a.claimed) revert AlreadyClaimed();

        a.claimed = true;
        a.resolvedOutcome = a.proposedOutcome;
        a.winner = a.proposer;

        uint256 payout = a.reward + a.bond;
        (bool success, ) = a.proposer.call{value: payout}("");
        if (!success) revert TransferFailed();

        emit AssertionSettled(assertionId, a.resolvedOutcome, a.proposer);
        emit RewardClaimed(assertionId, a.proposer, payout);
    }

    function claimDisputedReward(uint256 assertionId) external {
        EventAssertion storage a = assertions[assertionId];
        if (a.disputer == address(0)) revert NotDisputedAssertion();
        if (a.winner == address(0)) revert AwaitingDecider();
        if (a.claimed) revert AlreadyClaimed();

        a.claimed = true;

        uint256 totalPool = a.reward + (a.bond * 2);
        uint256 deciderFee = totalPool / 20; // 5% decider fee
        uint256 winnerPayout = totalPool - deciderFee;

        (bool successDecider, ) = decider.call{value: deciderFee}("");
        if (!successDecider) revert TransferFailed();

        (bool successWinner, ) = a.winner.call{value: winnerPayout}("");
        if (!successWinner) revert TransferFailed();

        emit RewardClaimed(assertionId, a.winner, winnerPayout);
    }

    function claimRefund(uint256 assertionId) external {
        EventAssertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert AssertionNotFound();
        if (a.proposer != address(0)) revert AssertionProposed();
        if (block.timestamp <= a.endTime) revert InvalidTime();
        if (a.claimed) revert AlreadyClaimed();

        a.claimed = true;

        (bool success, ) = a.asserter.call{value: a.reward}("");
        if (!success) revert TransferFailed();

        emit RefundClaimed(assertionId, a.asserter, a.reward);
    }

    function settleAssertion(uint256 assertionId, bool resolvedOutcome) external onlyDecider {
        EventAssertion storage a = assertions[assertionId];
        if (a.disputer == address(0)) revert NotDisputedAssertion();
        if (a.winner != address(0)) revert AlreadySettled();

        a.resolvedOutcome = resolvedOutcome;
        a.winner = (resolvedOutcome == a.proposedOutcome) ? a.proposer : a.disputer;

        emit AssertionSettled(assertionId, resolvedOutcome, a.winner);
    }

    function getState(uint256 assertionId) external view returns (State) {
        EventAssertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) return State.Invalid;
        if (a.claimed) return State.Settled;
        if (a.disputer != address(0)) {
            if (a.winner != address(0)) return State.Settled;
            return State.Disputed;
        }
        if (a.proposer != address(0)) {
            if (block.timestamp > a.endTime) return State.Settled;
            return State.Proposed;
        }
        if (block.timestamp > a.endTime) return State.Expired;
        return State.Asserted;
    }

    function getResolution(uint256 assertionId) external view returns (bool) {
        EventAssertion storage a = assertions[assertionId];
        if (a.disputer != address(0)) {
            return a.resolvedOutcome;
        }
        return a.proposedOutcome;
    }
}