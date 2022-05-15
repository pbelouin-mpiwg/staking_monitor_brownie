//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
pragma abicoder v2;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/UniswapV2RouterInterface.sol";

error StakeMonitor__UpkeepNotNeeded();
error StakeMonitor__TransferFailed();
error StakingMonitor__UpperBond_SmallerThan_LowerBound();
error StakeMonitor__UserHasntDepositedETH();

struct userInfo {
    uint256 depositBalance;
    uint256 DAIBalance;
    uint256 priceLimit;
    uint256 percentageToSwap;
    uint256 balanceToSwap;
    uint256 latestBalance;
}

contract StakingMonitor is KeeperCompatibleInterface {
    mapping(address => userInfo) public s_userInfos;
    event Deposited(address indexed user);
    AggregatorV3Interface public priceFeed;

    uint256 public s_lowestPriceLimit;
    uint256 public lastTimeStamp;
    address[] public s_watchList;

    constructor(address _priceFeed) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getPrice() public view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer);
    }

    function deposit() external payable {
        // when user deposits the first time, we set last balance to their current balance...
        // not sure that's the best logic but let's see
        if (s_userInfos[msg.sender].depositBalance == 0) {
            s_userInfos[msg.sender].latestBalance = msg.sender.balance;
        }

        //TODO: somehow check if address is already watched
        s_watchList.push(msg.sender);
        s_userInfos[msg.sender].depositBalance =
            s_userInfos[msg.sender].depositBalance +
            msg.value;
        emit Deposited(msg.sender);
    }

    function withdrawETH(uint256 _amount) external {
        s_userInfos[msg.sender].depositBalance =
            s_userInfos[msg.sender].depositBalance -
            _amount;
        emit Deposited(msg.sender);
    }

    function getDepositBalance() external view returns (uint256) {
        return s_userInfos[msg.sender].depositBalance;
    }

    //function setPriceLimit(uint256 _priceLimit) external {
    //    // a user cannot set a price limit if they haven't deposited some eth
    //    if (s_userInfos[msg.sender].depositBalance == 0) {
    //        revert StakeMonitor__UserHasntDepositedETH();
    //    }
    //    s_userInfos[msg.sender].priceLimit = _priceLimit;
    //    setLowestPriceLimit(_priceLimit);
    //}

    function setLowestPriceLimit(uint256 _priceLimit) internal {
        // set lowest price limit across all users, to trigger upkeep if the lowest price limit is reached
        if ((s_lowestPriceLimit == 0) || (s_lowestPriceLimit > _priceLimit)) {
            s_lowestPriceLimit = _priceLimit;
        }
    }

    function setOrder(uint256 _priceLimit, uint256 _percentageToSwap) external {
        // a user cannot set a price limit if they haven't deposited some eth
        if (s_userInfos[msg.sender].depositBalance == 0) {
            revert StakeMonitor__UserHasntDepositedETH();
        }

        s_userInfos[msg.sender].percentageToSwap = _percentageToSwap;
        s_userInfos[msg.sender].priceLimit = _priceLimit;
        // we check if this new price limit becomes the new price limit
        setLowestPriceLimit(_priceLimit);
    }

    function setBalancesToSwap() external {
        for (uint256 idx = 0; idx < s_watchList.length; idx++) {
            // for each address in the watchlist, we check if the balance has increased.
            // if so, we are allowed to spend the difference between the new balance and the old one
            s_userInfos[s_watchList[idx]].balanceToSwap = (s_watchList[idx]
                .balance - s_userInfos[s_watchList[idx]].latestBalance);
        }
    }

    function checkLowestLimitUnderCurrentPrice() public view returns (bool) {
        uint price = getPrice();
        bool upkeepNeeded = (s_lowestPriceLimit < price);
        return upkeepNeeded;
    }

    function checkUpkeep(bytes calldata checkData)
        external
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = checkLowestLimitUnderCurrentPrice();

        // We don't use the checkData in this example
        // checkData was defined when the Upkeep was registered
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external override {
        // iterate over users price limits
        // trigger the sale if current ether price is above price limit for user

        // We don't use the performData in this example
        // performData is generated by the Keeper's call to your `checkUpkeep` function
        performData;
    }
}
