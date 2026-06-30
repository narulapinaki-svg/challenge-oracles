// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { ORA } from "./OracleToken.sol";
import { StatisticsUtils } from "../utils/StatisticsUtils.sol";

contract StakingOracle {
    using StatisticsUtils for uint256[];

    error NodeNotRegistered();
    error InsufficientStake();
    error NodeAlreadyRegistered();
    error NoRewardsAvailable();
    error OnlyPastBucketsAllowed();
    error NodeAlreadySlashed();
    error AlreadyReportedInCurrentBucket();
    error NotDeviated();
    error WaitingPeriodNotOver();
    error InvalidPrice();
    error IndexOutOfBounds();
    error NodeNotAtGivenIndex();
    error TransferFailed();
    error MedianNotRecorded();
    error BucketMedianAlreadyRecorded();
    error NodeDidNotReport();

    ORA public oracleToken;

    struct OracleNode {
        uint256 stakedAmount;
        uint256 lastReportedBucket;
        uint256 reportCount;
        uint256 claimedReportCount;
        uint256 firstBucket;
        bool active;
    }

    struct BlockBucket {
        mapping(address => bool) slashedOffenses;
        address[] reporters;
        uint256[] prices;
        uint256 medianPrice;
    }

    mapping(address => OracleNode) public nodes;
    mapping(uint256 => BlockBucket) public blockBuckets;
    address[] public nodeAddresses;

    uint256 public constant MINIMUM_STAKE = 100 ether;
    uint256 public constant BUCKET_WINDOW = 24;
    uint256 public constant SLASHER_REWARD_PERCENTAGE = 10;
    uint256 public constant REWARD_PER_REPORT = 1 ether;
    uint256 public constant INACTIVITY_PENALTY = 1 ether;
    uint256 public constant MISREPORT_PENALTY = 100 ether;
    uint256 public constant MAX_DEVIATION_BPS = 1000;
    uint256 public constant WAITING_PERIOD = 2;

    event NodeRegistered(address indexed node, uint256 stakedAmount);
    event PriceReported(address indexed node, uint256 price, uint256 bucketNumber);
    event BucketMedianRecorded(uint256 indexed bucketNumber, uint256 medianPrice);
    event NodeSlashed(address indexed node, uint256 amount);
    event NodeRewarded(address indexed node, uint256 amount);
    event StakeAdded(address indexed node, uint256 amount);
    event NodeExited(address indexed node, uint256 amount);

    modifier onlyNode() {
        if (nodes[msg.sender].active == false) revert NodeNotRegistered();
        _;
    }

    constructor(address oraTokenAddress) {
        oracleToken = ORA(payable(oraTokenAddress));
    }

    function registerNode(uint256 amount) public {
        if (nodes[msg.sender].active) revert NodeAlreadyRegistered();
        if (amount < MINIMUM_STAKE) revert InsufficientStake();
        bool success = oracleToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        nodes[msg.sender] = OracleNode({
            stakedAmount: amount,
            lastReportedBucket: 0,
            reportCount: 0,
            claimedReportCount: 0,
            firstBucket: getCurrentBucketNumber(),
            active: true
        });
        nodeAddresses.push(msg.sender);
        emit NodeRegistered(msg.sender, amount);
    }

    function reportPrice(uint256 price) public onlyNode {
        if (price == 0) revert InvalidPrice();
        uint256 currentBucket = getCurrentBucketNumber();
        OracleNode storage node = nodes[msg.sender];
        if (node.lastReportedBucket == currentBucket) revert AlreadyReportedInCurrentBucket();
        if (getEffectiveStake(msg.sender) < MINIMUM_STAKE) revert InsufficientStake();
        if (node.lastReportedBucket != 0 && node.lastReportedBucket < currentBucket - 1) {
            if (blockBuckets[node.lastReportedBucket].medianPrice == 0) revert MedianNotRecorded();
        }
        node.lastReportedBucket = currentBucket;
        node.reportCount++;
        blockBuckets[currentBucket].reporters.push(msg.sender);
        blockBuckets[currentBucket].prices.push(price);
        emit PriceReported(msg.sender, price, currentBucket);
    }

    function claimReward() public {
        OracleNode storage node = nodes[msg.sender];
        uint256 unclaimedReports = node.reportCount - node.claimedReportCount;
        if (unclaimedReports == 0) revert NoRewardsAvailable();
        uint256 reward = unclaimedReports * REWARD_PER_REPORT;
        node.claimedReportCount = node.reportCount;
        oracleToken.mint(msg.sender, reward);
        emit NodeRewarded(msg.sender, reward);
    }

    function addStake(uint256 amount) public onlyNode {
        bool success = oracleToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        nodes[msg.sender].stakedAmount += amount;
        emit StakeAdded(msg.sender, amount);
    }

    function recordBucketMedian(uint256 bucketNumber) public {
        if (bucketNumber >= getCurrentBucketNumber()) revert OnlyPastBucketsAllowed();
        if (blockBuckets[bucketNumber].medianPrice != 0) revert BucketMedianAlreadyRecorded();
        uint256[] memory prices = blockBuckets[bucketNumber].prices;
        if (prices.length == 0) revert NoRewardsAvailable();
        prices.sort();
        uint256 median = prices.getMedian();
        blockBuckets[bucketNumber].medianPrice = median;
        emit BucketMedianRecorded(bucketNumber, median);
    }

    function slashNode(address nodeToSlash, uint256 bucketNumber, uint256 reportIndex, uint256 nodeAddressesIndex) public {
        if (bucketNumber >= getCurrentBucketNumber()) revert OnlyPastBucketsAllowed();
        if (blockBuckets[bucketNumber].medianPrice == 0) revert MedianNotRecorded();
        if (blockBuckets[bucketNumber].slashedOffenses[nodeToSlash]) revert NodeAlreadySlashed();
        if (nodeAddresses[nodeAddressesIndex] != nodeToSlash) revert NodeNotAtGivenIndex();
        BlockBucket storage bucket = blockBuckets[bucketNumber];
        if (reportIndex >= bucket.reporters.length) revert IndexOutOfBounds();
        if (bucket.reporters[reportIndex] != nodeToSlash) revert NodeDidNotReport();
        uint256 reportedPrice = bucket.prices[reportIndex];
        if (!_checkPriceDeviated(reportedPrice, bucket.medianPrice)) revert NotDeviated();
        bucket.slashedOffenses[nodeToSlash] = true;
        uint256 slashAmount = MISREPORT_PENALTY;
        if (nodes[nodeToSlash].stakedAmount < slashAmount) {
            slashAmount = nodes[nodeToSlash].stakedAmount;
        }
        nodes[nodeToSlash].stakedAmount -= slashAmount;
        uint256 slasherReward = (slashAmount * SLASHER_REWARD_PERCENTAGE) / 100;
        oracleToken.transfer(msg.sender, slasherReward);
        emit NodeSlashed(nodeToSlash, slashAmount);
    }

    function exitNode(uint256 index) public onlyNode {
        OracleNode storage node = nodes[msg.sender];
        uint256 currentBucket = getCurrentBucketNumber();
        if (currentBucket < node.lastReportedBucket + WAITING_PERIOD) revert WaitingPeriodNotOver();
        uint256 stakeToReturn = node.stakedAmount;
        _removeNode(msg.sender, index);
        node.active = false;
        node.stakedAmount = 0;
        oracleToken.transfer(msg.sender, stakeToReturn);
        emit NodeExited(msg.sender, stakeToReturn);
    }

    function getCurrentBucketNumber() public view returns (uint256) {
        return (block.number / BUCKET_WINDOW) + 1;
    }

    function getNodeAddresses() public view returns (address[] memory) {
        return nodeAddresses;
    }

    function getLatestPrice() public view returns (uint256) {
        uint256 currentBucket = getCurrentBucketNumber();
        for (uint256 i = currentBucket - 1; i >= 1; i--) {
            if (blockBuckets[i].medianPrice != 0) {
                return blockBuckets[i].medianPrice;
            }
            if (i == 1) break;
        }
        revert MedianNotRecorded();
    }

    function getPastPrice(uint256 bucketNumber) public view returns (uint256) {
        if (blockBuckets[bucketNumber].medianPrice == 0) revert MedianNotRecorded();
        return blockBuckets[bucketNumber].medianPrice;
    }

    function getSlashedStatus(address nodeAddress, uint256 bucketNumber) public view returns (uint256 price, bool slashed) {
        BlockBucket storage bucket = blockBuckets[bucketNumber];
        slashed = bucket.slashedOffenses[nodeAddress];
        for (uint256 i = 0; i < bucket.reporters.length; i++) {
            if (bucket.reporters[i] == nodeAddress) {
                price = bucket.prices[i];
                break;
            }
        }
    }

    function getEffectiveStake(address nodeAddress) public view returns (uint256) {
        OracleNode storage node = nodes[nodeAddress];
        uint256 currentBucket = getCurrentBucketNumber();
        uint256 missedBuckets = 0;
        if (node.lastReportedBucket < currentBucket - 1) {
            missedBuckets = currentBucket - 1 - node.lastReportedBucket;
        }
        uint256 penalty = missedBuckets * INACTIVITY_PENALTY;
        if (penalty >= node.stakedAmount) return 0;
        return node.stakedAmount - penalty;
    }

    function getOutlierNodes(uint256 bucketNumber) public view returns (address[] memory) {
        BlockBucket storage bucket = blockBuckets[bucketNumber];
        if (bucket.medianPrice == 0) revert MedianNotRecorded();
        address[] memory temp = new address[](bucket.reporters.length);
        uint256 count = 0;
        for (uint256 i = 0; i < bucket.reporters.length; i++) {
            if (_checkPriceDeviated(bucket.prices[i], bucket.medianPrice)) {
                temp[count] = bucket.reporters[i];
                count++;
            }
        }
        address[] memory outliers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            outliers[i] = temp[i];
        }
        return outliers;
    }

    function _removeNode(address nodeAddress, uint256 index) internal {
        if (index >= nodeAddresses.length) revert IndexOutOfBounds();
        if (nodeAddresses[index] != nodeAddress) revert NodeNotAtGivenIndex();
        nodeAddresses[index] = nodeAddresses[nodeAddresses.length - 1];
        nodeAddresses.pop();
    }

    function _checkPriceDeviated(uint256 reportedPrice, uint256 medianPrice) internal pure returns (bool) {
        if (medianPrice == 0) return false;
        uint256 diff = reportedPrice > medianPrice ? reportedPrice - medianPrice : medianPrice - reportedPrice;
        return (diff * 10000) / medianPrice > MAX_DEVIATION_BPS;
    }
}