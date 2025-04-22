solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract LiquidityManagement is AccessControl, Pausable {
    using SafeMath for uint256;

    // Roles
    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");

    // Token Addresses
    IERC20 public growToken;
    IERC20 public farmToken;

    // Uniswap Router and Factory Addresses
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Factory public uniswapV2Factory;

    // Liquidity Pool Information
    struct LiquidityPool {
        address pairAddress;
        uint256 growReserve;
        uint256 otherReserve;
    }
    // token path to add liquidity
    mapping(address => address[]) public addPath;

    // Liquidity Pools
    mapping(address => LiquidityPool) public liquidityPools; // token address to liquidity pool
    address[] public liquidityPairs; // store token pairs address

    // Events
    event LiquidityAdded(address indexed token, uint256 amountToken, uint256 amountOther);
    event LiquidityRemoved(address indexed token, uint256 amountToken, uint256 amountOther);

    constructor(
        address _growTokenAddress,
        address _farmTokenAddress,
        address _uniswapV2RouterAddress,
        address _uniswapV2FactoryAddress
    ) {
        require(_growTokenAddress != address(0), "GROW Token address is the zero address");
        require(_farmTokenAddress != address(0), "FARM Token address is the zero address");
        require(_uniswapV2RouterAddress != address(0), "Uniswap Router address is the zero address");
        require(_uniswapV2FactoryAddress != address(0), "Uniswap Factory address is the zero address");

        growToken = IERC20(_growTokenAddress);
        farmToken = IERC20(_farmTokenAddress);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2RouterAddress);
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2FactoryAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIQUIDITY_MANAGER_ROLE, msg.sender);
        address weth = uniswapV2Router.WETH();
        // Add default path for grow token.
        addPath[address(growToken)] = [address(growToken),weth];
        // Add default path for farm token.
        addPath[address(farmToken)] = [address(farmToken),weth];
    }

     // Modifier
    modifier onlyValidToken(address token){
        require(token == address(growToken) || token == address(farmToken) || token == uniswapV2Router.WETH() , "invalid token");
        _;
    }

    // Function to add liquidity
    function addLiquidity(address token, uint256 amountToken, uint256 amountOther) external onlyRole(LIQUIDITY_MANAGER_ROLE) whenNotPaused onlyValidToken(token) {
        require(amountToken > 0 && amountOther > 0, "Amounts must be greater than zero");
        IERC20 tokenContract = IERC20(token);

        // Approve the router to spend the tokens
        tokenContract.approve(address(uniswapV2Router), amountToken);
         //check if the user is approved to use the weth token
        if(token != uniswapV2Router.WETH()){
            IERC20 weth = IERC20(uniswapV2Router.WETH());
            weth.approve(address(uniswapV2Router),amountOther);
        }
        // Add liquidity
        address pairAddress;
        if (token == uniswapV2Router.WETH()) {
             (uint amountA, uint amountB, uint liquidity) = uniswapV2Router.addLiquidityETH{value: amountOther}(
                address(growToken),
                amountToken,
                0,
                0,
                address(this),
                block.timestamp
            );
            pairAddress = uniswapV2Factory.getPair(address(growToken),address(uniswapV2Router.WETH()));
        } else {
            (uint amountA, uint amountB, uint liquidity) = uniswapV2Router.addLiquidity(
                token,
                uniswapV2Router.WETH(),
                amountToken,
                amountOther,
                0,
                0,
                address(this),
                block.timestamp
            );
             pairAddress = uniswapV2Factory.getPair(token,address(uniswapV2Router.WETH()));
        }

        
        if(liquidityPools[token].pairAddress == address(0)){
            liquidityPairs.push(token);
        }

        // Update liquidity pool information
        liquidityPools[token] = LiquidityPool({
            pairAddress: pairAddress,
            growReserve: amountToken,
            otherReserve: amountOther
        });
        emit LiquidityAdded(token, amountToken, amountOther);
    }

    // Function to remove liquidity
    function removeLiquidity(address token, uint256 liquidity) external onlyRole(LIQUIDITY_MANAGER_ROLE) whenNotPaused onlyValidToken(token){
        require(liquidity > 0, "Liquidity must be greater than zero");
        require(liquidityPools[token].pairAddress != address(0), "This token has no liquidity");
        // Get the pair address
        address pairAddress = liquidityPools[token].pairAddress;

        // Get the pair contract
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        // Approve the router to spend the liquidity
        pair.approve(address(uniswapV2Router), liquidity);

        // Remove liquidity
        if(token == uniswapV2Router.WETH()){
            (uint amountToken, uint amountETH) = uniswapV2Router.removeLiquidityETH(
                address(growToken),
                liquidity,
                0,
                0,
                address(this),
                block.timestamp
            );
              emit LiquidityRemoved(token, amountToken, amountETH);
        } else {
             (uint amountA, uint amountB) = uniswapV2Router.removeLiquidity(
                token,
                uniswapV2Router.WETH(),
                liquidity,
                0,
                0,
                address(this),
                block.timestamp
            );
              emit LiquidityRemoved(token, amountA, amountB);
        }
    }
    //update add liquidity path
    function updateAddPath(address token, address[] memory path) external onlyRole(DEFAULT_ADMIN_ROLE) onlyValidToken(token) {
        addPath[token] = path;
    }

    // Function to pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    // Function to unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
