// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ICHIManager.sol";
import "./libraries/YANGPosition.sol";

contract RewardPool is Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public rewardsToken;
    ICHIManager public chiManager;
    address public yangNFT;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration; // seconds
    uint256 public startTime;
    uint256 public lastUpdateTime;
    uint256 public rewardPerShareStored;

    mapping(address => uint256) public userRewardPerSharePaid;
    mapping(address => uint256) public rewards;

    constructor(
        address _rewardsToken,
        address _chiManager,
        address _yangNFT,
        uint256 _rewardsDuration
    )
    {
        rewardsToken = IERC20(_rewardsToken);
        chiManager = ICHIManager(_chiManager);
        rewardsDuration = _rewardsDuration;
        yangNFT = _yangNFT;
    }

    /// View
    function shares(uint256 yangId, uint256 chiId) public view returns (uint256) {
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, chiId));
        return chiManager.yang(positionKey);
    }

    function totalShares(uint256 chiId) public view returns (uint256) {
        (, , , , , , ,uint256 _totalShares) = chiManager.chi(chiId);
        return _totalShares;
    }

    function rewardPerShare(uint256 chiId) public view returns (uint256) {
        if (totalShares(chiId) == 0) {
            return rewardPerShareStored;
        }
        return
            rewardPerShareStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalShares(chiId))
            );
    }

    function earned(uint256 yangId, uint256 chiId, address account) public view returns (uint256) {
        require(IERC721(yangNFT).ownerOf(yangId) == account, 'Non owner of Yang');
        uint256 _shares = shares(yangId, chiId);
        return _shares
                .mul(rewardPerShare(chiId).sub(userRewardPerSharePaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function getReward(uint256 yangId, uint256 chiId)
        public
        nonReentrant
        checkStart
        updateReward(yangId, chiId, msg.sender)
    {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// Restricted

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    // End rewards emission earlier
    function updatePeriodFinish(uint256 timestamp) external onlyOwner updateReward(0, 0, address(0)) {
        periodFinish = timestamp;
    }

    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(0, 0, address(0))
    {
        require(reward > 0, 'reward not 0');
        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        rewardsToken.safeTransferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            rewardRate = reward.add(periodFinish.sub(block.timestamp).mul(rewardRate)).div(rewardsDuration);
        }

        startTime = block.timestamp;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);

        emit RewardAdded(reward);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(uint256 yangId, uint256 chiId, address account) {
        rewardPerShareStored = rewardPerShare(chiId);
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0) && yangId != 0 && chiId != 0) {
            rewards[account] = earned(yangId, chiId, account);
            userRewardPerSharePaid[account] = rewardPerShareStored;
        }
        _;
    }

    modifier checkStart(){
        require(startTime != 0 && (block.timestamp > startTime), "not start");
        _;
    }

    /// Event

    event RewardAdded(uint256 reward);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
}
