// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import {IERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20FlashMintUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IDAOUpgradeable} from "./interfaces/IDAOUpgradeable.sol";
import {IStakingUpgradeable} from "./interfaces/IStakingUpgradeable.sol";
import {IFarmingUpgradeable} from "./interfaces/IFarmingUpgradeable.sol";
import {INFTMarketplaceUpgradeable} from "./interfaces/INFTMarketplaceUpgradeable.sol";
import {IGuildInteractionUpgradeable} from "./interfaces/IGuildInteractionUpgradeable.sol";
import {ICQTTokenSaleContract} from "./interfaces/ICQTTokenSaleContract.sol";
import {ICryptoQuestTheShardsOfGenesisNFTBook} from "./interfaces/ICryptoQuestTheShardsOfGenesisNFTBook.sol";
import {ICryptoQuestTheShardsOfGenesisBookNFTSalesContract} from "./interfaces/ICryptoQuestTheShardsOfGenesisBookNFTSalesContract.sol";
import {ICryptoQuestSwapContract} from "./interfaces/ICryptoQuestSwapContract.sol";

contract CryptoQuestAIFlashLoanArbitrator is 
    Initializable, 
    ERC20Upgradeable, 
    ERC20BurnableUpgradeable, 
    ERC20FlashMintUpgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable 
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // External contracts
    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    IERC721EnumerableUpgradeable public nftContract;
    IERC1155Upgradeable public nftContract1155;
    IERC20 public cqtToken;
    ISwapRouter public uniswapRouter;
    IDAOUpgradeable public daoContract;
    IStakingUpgradeable public stakingContract;
    IFarmingUpgradeable public farmingContract;
    INFTMarketplaceUpgradeable public nftMarketplaceContract;
    IGuildInteractionUpgradeable public guildInteractionContract;
    ICQTTokenSaleContract public cqtTokenSaleContract;
    ICryptoQuestTheShardsOfGenesisNFTBook public nftBookContract;
    ICryptoQuestTheShardsOfGenesisBookNFTSalesContract public nftBookSalesContract;
    ICryptoQuestSwapContract public swapContract;

    address public treasuryWallet;
    uint256 public feeRate;
    uint256 public constant MAX_FEE_RATE = 1000; // 10% max fee

    // Strategy tracking
    struct Strategy {
        uint8 strategyType;
        bool isActive;
        uint256 minProfitThreshold;
        bytes params;
    }

    mapping(uint256 => Strategy) public strategies;
    uint256 public strategyCount;

    mapping(address => bool) private whitelisted;
    mapping(address => uint256) public userProfits;
    
    // Modifiers
    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "Not whitelisted");
        _;
    }

    // Events
    event WhitelistUpdated(address indexed user, bool status);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeeRateUpdated(uint256 oldFeeRate, uint256 newFeeRate);
    event FlashLoanExecuted(address indexed initiator, address[] tokens, uint256[] amounts, uint256 profit);
    event ProfitDistributed(address indexed initiator, uint256 userProfit, uint256 fee);
    event StrategyExecuted(uint8 strategyType, uint256 profit);
    event StrategyAdded(uint256 indexed strategyId, uint8 strategyType);
    event StrategyUpdated(uint256 indexed strategyId, uint8 strategyType, bool isActive);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address upgrader,
        address provider,
        address nft721Address,
        address nft1155Address,
        address cqtTokenAddress,
        address uniswapRouterAddress,
        address daoAddress,
        address stakingAddress,
        address farmingAddress,
        address nftMarketplaceAddress,
        address guildInteractionAddress,
        address cqtTokenSaleContractAddress,
        address nftBookContractAddress,
        address nftBookSalesContractAddress,
        address swapContractAddress,
        address _treasuryWallet,
        uint256 _feeRate
    ) public initializer {
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_feeRate <= MAX_FEE_RATE, "Fee rate too high");
        require(provider != address(0), "Invalid provider address");

        __ERC20_init("CryptoQuestAIFlashLoanArbitrator", "CQAF");
        __ERC20Burnable_init();
        __ERC20FlashMint_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, defaultAdmin);

        addressesProvider = IPoolAddressesProvider(provider);
        pool = IPool(addressesProvider.getPool());
        nftContract = IERC721EnumerableUpgradeable(nft721Address);
        nftContract1155 = IERC1155Upgradeable(nft1155Address);
        cqtToken = IERC20(cqtTokenAddress);
        uniswapRouter = ISwapRouter(uniswapRouterAddress);
        daoContract = IDAOUpgradeable(daoAddress);
        stakingContract = IStakingUpgradeable(stakingAddress);
        farmingContract = IFarmingUpgradeable(farmingAddress);
        nftMarketplaceContract = INFTMarketplaceUpgradeable(nftMarketplaceAddress);
        guildInteractionContract = IGuildInteractionUpgradeable(guildInteractionAddress);
        cqtTokenSaleContract = ICQTTokenSaleContract(cqtTokenSaleContractAddress);
        nftBookContract = ICryptoQuestTheShardsOfGenesisNFTBook(nftBookContractAddress);
        nftBookSalesContract = ICryptoQuestTheShardsOfGenesisBookNFTSalesContract(nftBookSalesContractAddress);
        swapContract = ICryptoQuestSwapContract(swapContractAddress);
        treasuryWallet = _treasuryWallet;
        feeRate = _feeRate;
    }

    // Admin functions
    function updateTreasuryWallet(address newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newWallet != address(0), "Invalid wallet address");
        address oldWallet = treasuryWallet;
        treasuryWallet = newWallet;
        emit TreasuryWalletUpdated(oldWallet, newWallet);
    }

    function updateFeeRate(uint256 newFeeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeRate <= MAX_FEE_RATE, "Fee rate too high");
        uint256 oldFeeRate = feeRate;
        feeRate = newFeeRate;
        emit FeeRateUpdated(oldFeeRate, newFeeRate);
    }

    function updateWhitelist(address user, bool status) external onlyRole(OPERATOR_ROLE) {
        whitelisted[user] = status;
        emit WhitelistUpdated(user, status);
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    // Strategy management
    function addStrategy(
        uint8 strategyType,
        uint256 minProfitThreshold,
        bytes calldata params
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        strategyCount++;
        strategies[strategyCount] = Strategy({
            strategyType: strategyType,
            isActive: true,
            minProfitThreshold: minProfitThreshold,
            params: params
        });
        emit StrategyAdded(strategyCount, strategyType);
        return strategyCount;
    }

    function updateStrategy(
        uint256 strategyId,
        bool isActive,
        uint256 minProfitThreshold,
        bytes calldata params
    ) external onlyRole(OPERATOR_ROLE) {
        require(strategyId <= strategyCount, "Invalid strategy ID");
        Strategy storage strategy = strategies[strategyId];
        strategy.isActive = isActive;
        strategy.minProfitThreshold = minProfitThreshold;
        strategy.params = params;
        emit StrategyUpdated(strategyId, strategy.strategyType, isActive);
    }

    // Flash loan execution
    function executeFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        uint256[] calldata strategyIds
    ) external nonReentrant whenNotPaused onlyWhitelisted {
        require(tokens.length == amounts.length, "Array length mismatch");
        require(tokens.length == modes.length, "Array length mismatch");
        require(strategyIds.length > 0, "No strategies provided");

        for (uint256 i = 0; i < strategyIds.length; i++) {
            require(strategyIds[i] <= strategyCount, "Invalid strategy ID");
            require(strategies[strategyIds[i]].isActive, "Strategy not active");
        }

        // Execute flash loan
        bytes memory params = abi.encode(tokens, amounts, modes, strategyIds);
        pool.flashLoan(
            address(this),
            tokens,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }

    // Flash loan callback
    function executeOperation(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(pool), "Caller must be pool");
        
        (address[] memory _tokens, uint256[] memory _amounts, uint256[] memory _modes, uint256[] memory strategyIds) = 
            abi.decode(params, (address[], uint256[], uint256[], uint256[]));

        uint256 totalProfit = 0;

        // Execute strategies
        for (uint256 i = 0; i < strategyIds.length; i++) {
            Strategy storage strategy = strategies[strategyIds[i]];
            uint256 profit = executeStrategy(strategy.strategyType, _tokens[0], strategy.params);
            require(profit >= strategy.minProfitThreshold, "Profit below threshold");
            totalProfit += profit;
            emit StrategyExecuted(strategy.strategyType, profit);
        }

        // Repay flash loan
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amountOwed = amounts[i] + premiums[i];
            IERC20(tokens[i]).approve(address(pool), amountOwed);
        }

        // Distribute profits
        if (totalProfit > 0) {
            distributeProfits(initiator, totalProfit);
        }

        emit FlashLoanExecuted(initiator, tokens, amounts, totalProfit);
        return true;
    }

    // Strategy execution
    function executeStrategy(uint8 strategyType, address asset, bytes memory params) internal returns (uint256) {
        if (strategyType == 1) {
            return executeDEXTrade(asset, params);
        } else if (strategyType == 2) {
            return manageStaking(asset, params);
        } else if (strategyType == 3) {
            return manageFarming(asset, params);
        } else if (strategyType == 4) {
            return tradeNFT(asset, params);
        } else if (strategyType == 5) {
            return manageGuild(params);
        }
        revert("Invalid strategy type");
    }

    function executeDEXTrade(address asset, bytes memory params) internal returns (uint256) {
        (address[] memory path, uint256 minAmountOut) = abi.decode(params, (address[], uint256));
        uint256 amountIn = IERC20(asset).balanceOf(address(this));
        IERC20(asset).approve(address(swapContract), amountIn);

        uint256[] memory amounts = swapContract.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );

        return amounts[amounts.length - 1];
    }

    function manageStaking(address asset, bytes memory params) internal returns (uint256) {
        uint256 stakeAmount = abi.decode(params, (uint256));
        IERC20(asset).approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        stakingContract.claimRewards();
        stakingContract.unstake(stakeAmount);

        return stakingContract.getRewardsAvailable(address(this));
    }

    function manageFarming(address asset, bytes memory params) internal returns (uint256) {
        uint256 farmAmount = abi.decode(params, (uint256));
        IERC20(asset).approve(address(farmingContract), farmAmount);
        farmingContract.deposit(farmAmount);
        farmingContract.harvest();
        farmingContract.withdraw(farmAmount);

        return farmAmount;
    }

    function tradeNFT(address nftContractAddress, bytes memory params) internal returns (uint256) {
        (uint256 tokenId, uint256 maxPrice) = abi.decode(params, (uint256, uint256));
        uint256 listingPrice = nftMarketplaceContract.getListingPrice(nftContractAddress, tokenId);
        require(listingPrice <= maxPrice, "Price too high");

        nftMarketplaceContract.buyItem{value: listingPrice}(nftContractAddress, tokenId);
        nftMarketplaceContract.listItem(nftContractAddress, tokenId, listingPrice * 2);

        return listingPrice;
    }

    function manageGuild(bytes memory params) internal returns (uint256) {
        (uint8 action, uint256 guildId, uint256 questId) = abi.decode(params, (uint8, uint256, uint256));

        if (action == 1) {
            guildInteractionContract.joinGuild(guildId);
        } else if (action == 2) {
            guildInteractionContract.completeQuest(questId);
        } else {
            revert("Invalid guild action");
        }

        return guildInteractionContract.getPendingRewards(address(this));
    }

    // Profit distribution
    function distributeProfits(address initiator, uint256 totalProfit) internal {
        uint256 fee = (totalProfit * feeRate) / 10000;
        uint256 userProfit = totalProfit - fee;

        // Transfer fee to treasury
        if (fee > 0) {
            cqtToken.transfer(treasuryWallet, fee);
        }

        // Update user profits
        userProfits[initiator] += userProfit;
        
        emit ProfitDistributed(initiator, userProfit, fee);
    }

    // Withdraw profits
    function withdrawProfits() external nonReentrant {
        uint256 amount = userProfits[msg.sender];
        require(amount > 0, "No profits to withdraw");
        
        userProfits[msg.sender] = 0;
        cqtToken.transfer(msg.sender, amount);
    }

    // Required overrides
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Receive function
    receive() external payable {}
}
