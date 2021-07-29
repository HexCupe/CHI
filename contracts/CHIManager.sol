// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import "./libraries/YANGPosition.sol";

import "./interfaces/ICHIManager.sol";
import "./interfaces/ICHIVaultDeployer.sol";

contract CHIManager is
    ICHIManager,
    ReentrancyGuardUpgradeable,
    ERC721Upgradeable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using YANGPosition for mapping(bytes32 => YANGPosition.Info);
    using YANGPosition for YANGPosition.Info;
    // CHI ID
    uint176 private _nextId;

    /// YANG position
    mapping(bytes32 => YANGPosition.Info) public positions;

    // CHI data
    struct CHIData {
        address operator;
        address pool;
        address vault;
        bool paused;
        bool archived;
        bool equational;
    }

    /// @dev The token ID data
    mapping(uint256 => CHIData) private _chi;

    address public manager;
    address public v3Factory;
    address public yangNFT;
    address public deployer;
    bytes32 public merkleRoot;

    // initialize
    function initialize(
        uint176 _initId,
        address _v3Factory,
        address _yangNFT,
        address _deployer,
        bytes32 _merkleRoot,
        uint256 _vaultFee_
    ) public initializer {
        manager = msg.sender;
        v3Factory = _v3Factory;
        yangNFT = _yangNFT;
        deployer = _deployer;
        merkleRoot = _merkleRoot;
        _nextId = _initId;
        _vaultFee = _vaultFee_;
        __ERC721_init("YIN Uniswap V3 Positions Manager", "CHI");
    }

    modifier onlyYANG() {
        require(msg.sender == address(yangNFT), "y");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "manager");
        _;
    }

    modifier onlyGovs(bytes32[] calldata merkleProof) {
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "only govs");
        _;
    }

    uint256 private _tempChiId;
    modifier subscripting(uint256 chiId) {
        _tempChiId = chiId;
        _;
        _tempChiId = 0;
    }

    modifier onlyWhenNotPaused(uint256 tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        require(!_chi_.paused, "CHI Paused");
        _;
    }

    function chi(uint256 tokenId)
        external
        view
        override
        returns (
            address owner,
            address operator,
            address pool,
            address vault,
            uint256 accruedProtocolFees0,
            uint256 accruedProtocolFees1,
            uint256 fee,
            uint256 totalShares
        )
    {
        CHIData storage _chi_ = _chi[tokenId];
        require(_exists(tokenId), "Invalid token ID");
        ICHIVault _vault = ICHIVault(_chi_.vault);
        return (
            ownerOf(tokenId),
            _chi_.operator,
            _chi_.pool,
            _chi_.vault,
            _vault.accruedProtocolFees0(),
            _vault.accruedProtocolFees1(),
            _vault.protocolFee(),
            _vault.totalSupply()
        );
    }

    function updateMerkleRoot(bytes32 _merkleRoot) external onlyManager {
        merkleRoot = _merkleRoot;
    }

    uint256 private _vaultFee;

    function updateVaultFee(uint256 _vaultFee_) external onlyManager {
        _vaultFee = _vaultFee_;
    }

    function mint(MintParams calldata params, bytes32[] calldata merkleProof)
        external
        override
        onlyGovs(merkleProof)
        returns (uint256 tokenId, address vault)
    {
        address uniswapPool = IUniswapV3Factory(v3Factory).getPool(
            params.token0,
            params.token1,
            params.fee
        );

        require(uniswapPool != address(0), "Non-existent pool");

        vault = ICHIVaultDeployer(deployer).createVault(
            uniswapPool,
            address(this),
            _vaultFee
        );
        _mint(params.recipient, (tokenId = _nextId++));

        _chi[tokenId] = CHIData({
            operator: params.recipient,
            pool: uniswapPool,
            vault: vault,
            paused: false,
            archived: false,
            equational: true
        });

        emit Create(tokenId, uniswapPool, vault, _vaultFee);
    }

    function subscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        onlyYANG
        subscripting(tokenId)
        onlyWhenNotPaused(tokenId)
        nonReentrant
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        CHIData storage _chi_ = _chi[tokenId];
        (shares, amount0, amount1) = ICHIVault(_chi_.vault).deposit(
            yangId,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        positions[positionKey].shares = positions[positionKey].shares.add(
            shares
        );
    }

    function unsubscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        onlyYANG
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        CHIData storage _chi_ = _chi[tokenId];
        require(!_chi_.archived, "CHI Archived");

        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        YANGPosition.Info storage _position = positions[positionKey];
        require(_position.shares >= shares, "s");
        (amount0, amount1) = ICHIVault(_chi_.vault).withdraw(
            yangId,
            shares,
            amount0Min,
            amount1Min,
            yangNFT
        );
        _position.shares = positions[positionKey].shares.sub(shares);
    }

    function CHIDepositCallback(
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1
    ) external override {
        _verifyCallback(msg.sender);
        if (amount0 > 0) token0.transferFrom(yangNFT, msg.sender, amount0);
        if (amount1 > 0) token1.transferFrom(yangNFT, msg.sender, amount1);
    }

    function _verifyCallback(address caller) internal view {
        CHIData storage _chi_ = _chi[_tempChiId];
        require(_chi_.vault == caller, "callback fail");
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _;
    }

    function addRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    )
        external
        override
        isAuthorizedForToken(tokenId)
        onlyWhenNotPaused(tokenId)
    {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).addRange(tickLower, tickUpper);
        _chi_.equational = true;
    }

    function removeRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    )
        external
        override
        isAuthorizedForToken(tokenId)
        onlyWhenNotPaused(tokenId)
    {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).removeRange(tickLower, tickUpper);
        _chi_.equational = true;
    }

    function addAndRemoveRanges(
        uint256 tokenId,
        RangeParams[] calldata addRanges,
        RangeParams[] calldata removeRanges
    )
        external
        override
        isAuthorizedForToken(tokenId)
        onlyWhenNotPaused(tokenId)
    {
        CHIData storage _chi_ = _chi[tokenId];
        for (uint256 i = 0; i < addRanges.length; i++) {
            ICHIVault(_chi_.vault).addRange(
                addRanges[i].tickLower,
                addRanges[i].tickUpper
            );
        }
        for (uint256 i = 0; i < removeRanges.length; i++) {
            ICHIVault(_chi_.vault).removeRange(
                removeRanges[i].tickLower,
                removeRanges[i].tickUpper
            );
        }
        _chi_.equational = true;
    }

    function collectProtocol(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external override onlyManager onlyWhenNotPaused(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).collectProtocol(amount0, amount1, to);
    }

    // tickPercents for rangeSets
    mapping(address => mapping(uint256 => uint256)) public tickPercents;

    function addLiquidityAllToPosition(
        uint256 tokenId,
        uint256 amount0Total,
        uint256 amount1Total
    ) external override onlyManager onlyWhenNotPaused(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        uint256 count = ICHIVault(_chi_.vault).getRangeCount();
        if (_chi_.equational) {
            uint256 divideAmount0 = amount0Total.div(count);
            uint256 divideAmount1 = amount1Total.div(count);
            for (uint256 idx = 0; idx < count; idx++) {
                ICHIVault(_chi_.vault).addLiquidityToPosition(
                    idx,
                    divideAmount0,
                    divideAmount1
                );
            }
        } else {
            for (uint256 idx = 0; idx < count; idx++) {
                uint256 percent = tickPercents[_chi_.vault][idx];
                uint256 amount0Desired = amount0Total.mul(percent).div(100);
                uint256 amount1Desired = amount1Total.mul(percent).div(100);
                ICHIVault(_chi_.vault).addLiquidityToPosition(
                    idx,
                    amount0Desired,
                    amount1Desired
                );
            }
        }
    }

    function addLiquidityToPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external override onlyManager onlyWhenNotPaused(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).addLiquidityToPosition(
            rangeIndex,
            amount0Desired,
            amount1Desired
        );
    }

    function removeLiquidityFromPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint128 liquidity
    ) external override onlyManager {
        CHIData storage _chi_ = _chi[tokenId];
        require(!_chi_.archived, "CHI Archived");
        ICHIVault(_chi_.vault).removeLiquidityFromPosition(
            rangeIndex,
            liquidity
        );
    }

    function removeAllLiquidityFromPosition(uint256 tokenId, uint256 rangeIndex)
        external
        override
        onlyManager
    {
        CHIData storage _chi_ = _chi[tokenId];
        require(!_chi_.archived, "CHI Archived");
        ICHIVault(_chi_.vault).removeAllLiquidityFromPosition(rangeIndex);
    }

    function stateOfCHI(uint256 tokenId)
        external
        view
        override
        returns (bool isPaused, bool isArchived)
    {
        CHIData storage _chi_ = _chi[tokenId];
        isPaused = _chi_.paused;
        isArchived = _chi_.archived;
    }

    function pausedCHI(uint256 tokenId) external override {
        CHIData storage _chi_ = _chi[tokenId];
        require(
            _isApprovedOrOwner(msg.sender, tokenId) || msg.sender == manager,
            "Not approved"
        );
        _chi_.paused = true;
    }

    function unpausedCHI(uint256 tokenId) external override {
        CHIData storage _chi_ = _chi[tokenId];
        require(
            _isApprovedOrOwner(msg.sender, tokenId) || msg.sender == manager,
            "Not approved"
        );
        require(!_chi_.archived, "CHI archived");
        _chi_.paused = false;
    }

    function archivedCHI(uint256 tokenId) external override onlyManager {
        CHIData storage _chi_ = _chi[tokenId];
        require(_chi_.paused, "Not Paused");
        _chi_.archived = true;
    }

    function addTickPercents(uint256 tokenId, uint256[] calldata percents)
        external
        override
        isAuthorizedForToken(tokenId)
    {
        CHIData storage _chi_ = _chi[tokenId];
        uint256 rangeCount = ICHIVault(_chi_.vault).getRangeCount();
        require(rangeCount == percents.length, "Invalid percents");
        uint256 totalPercent = 0;
        for (uint256 idx = 0; idx < rangeCount; idx++) {
            tickPercents[_chi_.vault][idx] = percents[idx];
            totalPercent = totalPercent.add(percents[idx]);
        }
        require(totalPercent <= 100, "Exceed max percent");
        _chi_.equational = false;
    }

    function setDeployer(address _deployer) external onlyManager {
        deployer = _deployer;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable)
        returns (string memory)
    {
        require(_exists(tokenId));
        return "";
    }

    function baseURI() public pure override returns (string memory) {}

    /// @inheritdoc IERC721Upgradeable
    function getApproved(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable)
        returns (address)
    {
        require(
            _exists(tokenId),
            "ERC721Upgradeable: approved query for nonexistent token"
        );

        return _chi[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId)
        internal
        override(ERC721Upgradeable)
    {
        _chi[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
