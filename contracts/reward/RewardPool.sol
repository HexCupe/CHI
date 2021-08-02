// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../interfaces/ICHIManager.sol";
import "../interfaces/IRewardPool.sol";
import "../libraries/YANGPosition.sol";

contract RewardPool is
    IRewardPool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
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
    mapping(uint256 => uint256) public lastUpdateTimes;
    mapping(uint256 => uint256) public rewardPerShareStored;

    mapping(uint256 => uint256) private _totalShares;
    mapping(uint256 => mapping(address => uint256)) private _shares;

    mapping(uint256 => mapping(address => uint256)) public rewards;
    mapping(uint256 => mapping(address => uint256))
        public userRewardPerSharePaid;

    // initialize
    function initialize(
        address _rewardsToken,
        address _chiManager,
        address _yangNFT,
        uint256 _rewardsDuration
    ) public initializer {
        rewardsToken = IERC20(_rewardsToken);
        chiManager = ICHIManager(_chiManager);
        rewardsDuration = _rewardsDuration;
        yangNFT = _yangNFT;
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// View
    function shares(uint256 yangId, uint256 chiId)
        public
        view
        override
        returns (uint256)
    {
        address account = IERC721(yangNFT).ownerOf(yangId);
        return _shares[chiId][account];
    }

    function totalShares(uint256 chiId) public view override returns (uint256) {
        return _totalShares[chiId];
    }

    function rewardPerShare(uint256 chiId) public view returns (uint256) {
        uint256 _totalShares_ = _totalShares[chiId];
        if (chiId == 0 || _totalShares_ == 0) {
            return uint256(0);
        }
        return
            rewardPerShareStored[chiId].add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTimes[chiId])
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalShares_)
            );
    }

    function earned(
        uint256 yangId,
        uint256 chiId,
        address account
    ) public view override returns (uint256) {
        require(
            IERC721(yangNFT).ownerOf(yangId) == account,
            "Non owner of Yang"
        );
        uint256 _share = _shares[chiId][account];
        return
            _share
                .mul(
                    rewardPerShare(chiId).sub(
                        userRewardPerSharePaid[chiId][account]
                    )
                )
                .div(1e18)
                .add(rewards[chiId][account]);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function updateRewardFromCHI(
        uint256 yangId,
        uint256 chiId,
        address account
    ) public override onlyChiManager updateReward(yangId, chiId, account) {
        (, , , , , , , uint256 _totalShares_) = chiManager.chi(chiId);
        _totalShares[chiId] = _totalShares_;
        _shares[chiId][account] = chiManager.yang(yangId, chiId);

        uint256 reward = earned(yangId, chiId, account);
        emit RewardUpdated(yangId, chiId, reward);
    }

    function getReward(uint256 yangId, uint256 chiId)
        public
        override
        nonReentrant
        checkStart
        updateReward(yangId, chiId, msg.sender)
    {
        uint256 reward = rewards[chiId][msg.sender];
        if (reward > 0) {
            rewards[chiId][msg.sender] = 0;
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
    function updatePeriodFinish(uint256 timestamp)
        external
        onlyOwner
        updateReward(0, 0, address(0))
    {
        periodFinish = timestamp;
    }

    function updateRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
    }

    function notifyRewardAmount(uint256 reward, uint256 _startTime)
        external
        onlyOwner
        updateReward(0, 0, address(0))
    {
        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        if (reward > 0) {
            rewardsToken.safeTransferFrom(msg.sender, address(this), reward);
        }

        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            rewardRate = reward
                .add(periodFinish.sub(block.timestamp).mul(rewardRate))
                .div(rewardsDuration);
        }

        if (_startTime == 0) {
            startTime = block.timestamp;
            periodFinish = block.timestamp.add(rewardsDuration);
        } else {
            startTime = _startTime;
            periodFinish = _startTime.add(rewardsDuration);
        }
        uint256 totalCHI = IERC721Enumerable(address(chiManager)).totalSupply();
        for (uint256 idx = 1; idx <= totalCHI; idx++) {
            lastUpdateTimes[idx] = startTime;
        }

        emit RewardAdded(reward);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(
        uint256 yangId,
        uint256 chiId,
        address account
    ) {
        if (chiId != 0) {
            rewardPerShareStored[chiId] = rewardPerShare(chiId);
            lastUpdateTimes[chiId] = lastTimeRewardApplicable();
        }
        if (account != address(0) && yangId != 0 && chiId != 0) {
            rewards[chiId][account] = earned(yangId, chiId, account);
            userRewardPerSharePaid[chiId][account] = rewardPerShareStored[
                chiId
            ];
        }
        _;
    }

    modifier checkStart() {
        require(startTime != 0 && (block.timestamp > startTime), "not start");
        _;
    }

    modifier onlyChiManager() {
        require(
            msg.sender == address(chiManager) || msg.sender == owner(),
            "only manager"
        );
        _;
    }
}
