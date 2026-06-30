//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./SimpleOracle.sol";
import { StatisticsUtils } from "../utils/StatisticsUtils.sol";

contract WhitelistOracle {
    using StatisticsUtils for uint256[];

    /////////////////
    /// Errors //////
    /////////////////

    error OnlyOwner();
    error IndexOutOfBounds();
    error NoOraclesAvailable();

    //////////////////////
    /// State Variables //
    //////////////////////

    address public owner;
    SimpleOracle[] public oracles;
    uint256 public constant STALE_DATA_WINDOW = 24 seconds;

    ////////////////
    /// Events /////
    ////////////////

    event OracleAdded(address oracleAddress, address oracleOwner);
    event OracleRemoved(address oracleAddress);

    ///////////////////
    /// Modifiers /////
    ///////////////////

    modifier onlyOwner() {
        // if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    ///////////////////
    /// Constructor ///
    ///////////////////

    constructor() {
        owner = msg.sender;
    }

    ///////////////////
    /// Functions /////
    ///////////////////

    function addOracle(address _owner) public onlyOwner {
        SimpleOracle newOracle = new SimpleOracle(_owner);
        oracles.push(newOracle);
        emit OracleAdded(address(newOracle), _owner);
    }

    function removeOracle(uint256 index) public onlyOwner {
        if (index >= oracles.length) revert IndexOutOfBounds();
        emit OracleRemoved(address(oracles[index]));
        oracles[index] = oracles[oracles.length - 1];
        oracles.pop();
    }

    function getPrice() public view returns (uint256) {
        if (oracles.length == 0) revert NoOraclesAvailable();
        uint256[] memory prices = new uint256[](oracles.length);
        uint256 count = 0;
        for (uint256 i = 0; i < oracles.length; i++) {
            (uint256 price, uint256 timestamp) = oracles[i].getPrice();
            if (block.timestamp - timestamp <= STALE_DATA_WINDOW) {
                prices[count] = price;
                count++;
            }
        }
        if (count == 0) revert NoOraclesAvailable();
        uint256[] memory validPrices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            validPrices[i] = prices[i];
        }
        validPrices.sort();
        return validPrices.getMedian();
    }

    function getActiveOracleNodes() public view returns (address[] memory) {
        address[] memory temp = new address[](oracles.length);
        uint256 count = 0;
        for (uint256 i = 0; i < oracles.length; i++) {
            (, uint256 timestamp) = oracles[i].getPrice();
            if (block.timestamp - timestamp <= STALE_DATA_WINDOW) {
                temp[count] = address(oracles[i]);
                count++;
            }
        }
        address[] memory active = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            active[i] = temp[i];
        }
        return active;
    }
}