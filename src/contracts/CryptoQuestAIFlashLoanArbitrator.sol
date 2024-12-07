// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Importing necessary interfaces and contracts
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20FlashMintUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// Sample CryptoQuest Token Contract
contract CryptoQuestToken is ERC20Upgradeable {
    function initialize() public initializer {
        __ERC20_init("CryptoQuestToken", "CQT");
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

// Sample Game Mechanics Contract
contract GameMechanics {
    function executeGameLogic() external {
        // Game logic goes here
    }
}

// Combined CQAF Contract
contract CryptoQuestAIFlashLoanArbitrator is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20FlashMintUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Additional Contracts
    CryptoQuestToken public questToken; // Reference to CryptoQuestToken contract
    GameMechanics public gameMechanics; // Reference to GameMechanics contract

    // Existing CQAF Variables...
    IPoolAddressesProvider private _addressesProvider;
    IPool private _pool;
    ISwapRouter private _uniswapRouter;

    // Configurable Variables
    address private _treasuryWallet;
    uint256 private _feeRate;
    uint256 private _maxFeeRate = 200; // 2% max fee
    uint256 private _minFeeRate = 50;   // 0.5% min fee

    struct TokenPair {
        address token0;
        address token1;
        uint24 fee;
        bool isActive;
    }

    struct Strategy {
        string name;
        address targetContract;
        bytes data;
        bool isActive;
    }

    // Mappings
    mapping(string => TokenPair) private _tokenPairs;
    mapping(string => Strategy) private _strategies;
    mapping(address => mapping(address => uint256)) private _deposits; // User deposits
    mapping(address => uint256) private _totalDeposits;              // Total token deposits
    mapping(address => bool) private _isSupported;                   // Supported tokens

    struct InitializationParams {
        address defaultAdmin;
        address pauser;
        address upgrader;
        address operator;
        address uniswapRouter;
        address addressesProvider;
        address treasuryWallet;
        uint256 feeRate;
        address[] supportedTokens;
    }

    // Events
    event TokenPairAdded(string indexed pairName, address indexed token0, address indexed token1, uint24 fee);
    event StrategyExecuted(string strategyName, bool success);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FlashLoanExecuted(address indexed initiator, address[] tokens, uint256[] amounts, uint256 profit);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event GamePlayed(address indexed player);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitializationParams memory params) public initializer {
        __ERC20_init("CryptoQuestAIFlashLoanArbitrator", "CQAF");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("CryptoQuestAIFlashLoanArbitrator");
        __ERC20FlashMint_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdmin);
        _grantRole(PAUSER_ROLE, params.pauser);
        _grantRole(UPGRADER_ROLE, params.upgrader);
        _grantRole(OPERATOR_ROLE, params.operator);

        _addressesProvider = IPoolAddressesProvider(params.addressesProvider);
        _pool = IPool(_addressesProvider.getPool());
        _uniswapRouter = ISwapRouter(params.uniswapRouter);
        _treasuryWallet = params.treasuryWallet;
        _feeRate = params.feeRate;

        for (uint256 i = 0; i < params.supportedTokens.length; ++i) {
            _isSupported[params.supportedTokens[i]] = true;
        }

        // Initialize the additional contracts
        questToken = new CryptoQuestToken();
        gameMechanics = new GameMechanics();

        // Predefine token pairs
        _addTokenPair("CQT-WETH", 0x94ef57abfBff1AD70bD00a921e1d2437f31C1665, 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, 3000);
        _addTokenPair("CQT-WBTC", 0x94ef57abfBff1AD70bD00a921e1d2437f31C1665, 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, 3000);
        _addTokenPair("CQT-WMATIC", 0x94ef57abfBff1AD70bD00a921e1d2437f31C1665, 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, 3000);
    }

    function _addTokenPair(string memory pairName, address token0, address token1, uint24 fee) internal onlyRole(OPERATOR_ROLE) {
        require(!_tokenPairs[pairName].isActive, "Token pair already exists");
        _tokenPairs[pairName] = TokenPair(token0, token1, fee, true);
        emit TokenPairAdded(pairName, token0, token1, fee);
    }

    function addOrUpdateTokenPair(
        string memory pairName,
        address token0,
        address token1,
        uint24 fee
    ) external onlyRole(OPERATOR_ROLE) {
        _tokenPairs[pairName] = TokenPair(token0, token1, fee, true);
        emit TokenPairAdded(pairName, token0, token1, fee);
    }

    function deactivateTokenPair(string memory pairName) external onlyRole(OPERATOR_ROLE) {
        require(_tokenPairs[pairName].isActive, "Token pair is already inactive");
        _tokenPairs[pairName].isActive = false;
        emit TokenPairAdded(pairName, _tokenPairs[pairName].token0, _tokenPairs[pairName].token1, _tokenPairs[pairName].fee);
    }

    function executeFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        string[] calldata strategyNames
    ) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused {
        require(tokens.length <= 100, "Token array too large");
        require(tokens.length == amounts.length, "Length mismatch");
        require(strategyNames.length > 0, "No strategies provided");

        bytes memory params = abi.encode(tokens, amounts, strategyNames);
        _pool.flashLoan(
            address(this),
            tokens,
            amounts,
            new uint256[](tokens.length),
            address(this),
            params,
            0
        );
    }

    function executeOperation(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(_pool), "Unauthorized");

        // Decode params
        (, , string[] memory strategyNames) = abi.decode(params, (address[], uint256[], string[]));

        _executeStrategies(strategyNames);

        // Repay loans
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 repayment = amounts[i] + premiums[i];
            IERC20(tokens[i]).approve(address(_pool), repayment);
        }

        emit FlashLoanExecuted(initiator, tokens, amounts, 0);
        return true;
    }

    function _executeStrategies(string[] memory strategyNames) internal {
        uint256 length = strategyNames.length;
        for (uint256 i = 0; i < length; ++i) {
            Strategy memory strategy = _strategies[strategyNames[i]];
            require(strategy.isActive, "Inactive strategy");

            (bool success, ) = strategy.targetContract.call(strategy.data);
            emit StrategyExecuted(strategy.name, success);
        }
    }

    function updateDynamicFeeRate(uint256 utilizationRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(utilizationRate <= 100, "Utilization rate must be between 0 and 100");
        
        if (utilizationRate < 30) {
            _feeRate = _minFeeRate; // 0.5% fee
        } else if (utilizationRate < 70) {
            _feeRate = 100; // 1% fee
        } else {
            _feeRate = _maxFeeRate; // 2% fee
        }

        emit FeeRateUpdated(_feeRate, utilizationRate);
    }

    function updateFeeBounds(uint256 newMax, uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMin < newMax, "Invalid bounds");
        _maxFeeRate = newMax;
        _minFeeRate = newMin;
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        require(_isSupported[token], "Unsupported token");
        require(amount > 0, "Zero amount");

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        _deposits[msg.sender][token] += amount;
        _totalDeposits[token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        require(_deposits[msg.sender][token] >= amount, "Insufficient balance");

        _deposits[msg.sender][token] -= amount;
        _totalDeposits[token] -= amount;
        emit Withdraw(msg.sender, token, amount);

        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");
    }

    function playGame() external {
        gameMechanics.executeGameLogic();
        emit GamePlayed(msg.sender);
    }

    function rewardPlayer(address player, uint256 rewardAmount) external onlyRole(OPERATOR_ROLE) {
        require(rewardAmount > 0, "Invalid reward");
        questToken.transfer(player, rewardAmount);
    }

    function getPairDetails(string memory pairName) public view returns (TokenPair memory) {
        require(_tokenPairs[pairName].isActive, "Token pair not active");
        return _tokenPairs[pairName];
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {}

    // Override Functions
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }
}
