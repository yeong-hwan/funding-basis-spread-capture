// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ISwapRouter
/// @notice Uniswap V3 SwapRouter02 interface
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title IWETH
/// @notice WETH interface
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @title SpotLongVault
/// @notice Arbitrum에서 ETH Spot Long 포지션을 관리하는 Vault
/// @dev Uniswap V3를 통해 USDC ↔ ETH 스왑
contract SpotLongVault {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @dev Arbitrum WETH
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// @dev Arbitrum Native USDC
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @dev Uniswap V3 SwapRouter02
    address public constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    /// @dev WETH/USDC Pool Fee (0.05%)
    uint24 public constant POOL_FEE = 500;

    /// @dev 슬리피지 허용 범위 (0.5% = 50 basis points)
    uint256 public constant SLIPPAGE_BPS = 50;

    /// @dev USDC decimals
    uint8 public constant USDC_DECIMALS = 6;

    /// @dev WETH decimals
    uint8 public constant WETH_DECIMALS = 18;

    // ============ State ============

    /// @notice Owner (관리자)
    address public owner;

    /// @notice Vault 상태
    enum State {
        IDLE,       // 포지션 없음
        ACTIVE,     // ETH Long 활성화
        EXITING     // 청산 진행 중
    }

    State public state;

    /// @notice 보유 ETH 수량 (wei)
    uint256 public ethBalance;

    /// @notice 총 투자 USDC (6 decimals)
    uint256 public totalInvestedUsdc;

    /// @notice 마지막 리밸런싱 시각
    uint256 public lastRebalanceTime;

    /// @notice 목표 ETH 수량 (Keeper가 설정, wei)
    uint256 public targetEthAmount;

    // ============ Events ============

    event Deposited(address indexed user, uint256 usdcAmount);
    event Withdrawn(address indexed user, uint256 usdcAmount);
    event EthBought(uint256 usdcIn, uint256 ethOut, uint256 price);
    event EthSold(uint256 ethIn, uint256 usdcOut, uint256 price);
    event Rebalanced(uint256 oldEthBalance, uint256 newEthBalance);
    event StateChanged(State oldState, State newState);
    event TargetUpdated(uint256 oldTarget, uint256 newTarget);

    // ============ Errors ============

    error NotOwner();
    error InvalidState(State current, State required);
    error InsufficientBalance();
    error ZeroAmount();
    error SlippageExceeded();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier inState(State required) {
        if (state != required) revert InvalidState(state, required);
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
        state = State.IDLE;

        // Approve USDC and WETH for SwapRouter
        IERC20(USDC).approve(SWAP_ROUTER, type(uint256).max);
        IERC20(WETH).approve(SWAP_ROUTER, type(uint256).max);
    }

    // ============ View Functions ============

    /// @notice 현재 ETH 가치 (USD, 6 decimals)
    /// @dev Chainlink 또는 외부 오라클 필요 - 현재는 Keeper가 제공
    function getEthValueUsd() public view returns (uint256) {
        // TODO: Chainlink 연동 또는 Keeper 제공
        // 임시로 ethBalance 기준 계산 (외부에서 가격 제공 필요)
        return 0;
    }

    /// @notice USDC 잔고 조회
    function getUsdcBalance() public view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }

    /// @notice WETH 잔고 조회
    function getWethBalance() public view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
    }

    // ============ Owner Functions ============

    /// @notice USDC 예치
    /// @param amount USDC 금액 (6 decimals)
    function deposit(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        totalInvestedUsdc += amount;

        emit Deposited(msg.sender, amount);
    }

    /// @notice ETH 매수 (USDC → WETH)
    /// @param usdcAmount 사용할 USDC 금액 (6 decimals)
    /// @param minEthOut 최소 ETH 수량 (wei)
    function buyEth(uint256 usdcAmount, uint256 minEthOut) external onlyOwner {
        if (usdcAmount == 0) revert ZeroAmount();
        if (IERC20(USDC).balanceOf(address(this)) < usdcAmount) revert InsufficientBalance();

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: WETH,
            fee: POOL_FEE,
            recipient: address(this),
            amountIn: usdcAmount,
            amountOutMinimum: minEthOut,
            sqrtPriceLimitX96: 0
        });

        uint256 ethOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

        ethBalance += ethOut;

        // 가격 계산 (USDC per ETH, 6 decimals)
        uint256 price = usdcAmount * 1e18 / ethOut;

        if (state == State.IDLE) {
            _setState(State.ACTIVE);
        }

        emit EthBought(usdcAmount, ethOut, price);
    }

    /// @notice ETH 매도 (WETH → USDC)
    /// @param ethAmount 매도할 ETH 금액 (wei)
    /// @param minUsdcOut 최소 USDC 수량 (6 decimals)
    function sellEth(uint256 ethAmount, uint256 minUsdcOut) external onlyOwner {
        if (ethAmount == 0) revert ZeroAmount();
        if (IERC20(WETH).balanceOf(address(this)) < ethAmount) revert InsufficientBalance();

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(this),
            amountIn: ethAmount,
            amountOutMinimum: minUsdcOut,
            sqrtPriceLimitX96: 0
        });

        uint256 usdcOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

        ethBalance -= ethAmount;

        // 가격 계산
        uint256 price = usdcOut * 1e18 / ethAmount;

        emit EthSold(ethAmount, usdcOut, price);
    }

    /// @notice 전체 ETH 청산
    /// @param minUsdcOut 최소 USDC 수량
    function closePosition(uint256 minUsdcOut) external onlyOwner inState(State.ACTIVE) {
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance == 0) revert InsufficientBalance();

        _setState(State.EXITING);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(this),
            amountIn: wethBalance,
            amountOutMinimum: minUsdcOut,
            sqrtPriceLimitX96: 0
        });

        uint256 usdcOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

        uint256 price = usdcOut * 1e18 / wethBalance;
        emit EthSold(wethBalance, usdcOut, price);

        ethBalance = 0;
        _setState(State.IDLE);
    }

    /// @notice USDC 출금
    /// @param amount 출금 금액 (6 decimals)
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(USDC).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        IERC20(USDC).safeTransfer(msg.sender, amount);

        if (amount <= totalInvestedUsdc) {
            totalInvestedUsdc -= amount;
        } else {
            totalInvestedUsdc = 0;
        }

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice 목표 ETH 수량 설정 (Keeper용)
    /// @param newTarget 새 목표 (wei)
    function setTargetEthAmount(uint256 newTarget) external onlyOwner {
        emit TargetUpdated(targetEthAmount, newTarget);
        targetEthAmount = newTarget;
    }

    /// @notice 리밸런싱 (목표 수량에 맞춤)
    /// @param minAmountOut 최소 출력 금액 (방향에 따라 ETH 또는 USDC)
    function rebalance(uint256 minAmountOut) external onlyOwner inState(State.ACTIVE) {
        uint256 currentEth = IERC20(WETH).balanceOf(address(this));
        uint256 oldBalance = currentEth;

        if (currentEth < targetEthAmount) {
            // ETH 추가 매수
            uint256 deficit = targetEthAmount - currentEth;
            // 대략적인 USDC 필요량 계산 (실제로는 가격 조회 필요)
            // 여기서는 minAmountOut을 USDC 사용량의 힌트로 사용
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: minAmountOut, // USDC amount to use
                amountOutMinimum: deficit * 95 / 100, // 5% slippage
                sqrtPriceLimitX96: 0
            });

            ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
        } else if (currentEth > targetEthAmount) {
            // ETH 일부 매도
            uint256 excess = currentEth - targetEthAmount;

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: excess,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

            ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
        }

        ethBalance = IERC20(WETH).balanceOf(address(this));
        lastRebalanceTime = block.timestamp;

        emit Rebalanced(oldBalance, ethBalance);
    }

    /// @notice Owner 변경
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    // ============ Internal ============

    function _setState(State newState) internal {
        emit StateChanged(state, newState);
        state = newState;
    }

    // ============ Emergency ============

    /// @notice 긴급 토큰 회수
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(owner, balance);
        }
    }

    /// @notice ETH 수신 (WETH unwrap용)
    receive() external payable {}
}
