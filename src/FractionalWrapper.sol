//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {ERC20Mock} from "../lib/yield-utils-v2/src/mocks/ERC20Mock.sol";
import {IERC20} from "../lib/yield-utils-v2/src/token/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract FractionalWrapper is ERC20Mock, Ownable {
    // Exchange rate at inception: 1 underlying (DA) == 1 share (yvDAI) } Ex-rate: 1 DAI/yvDAI = 0.5 -> 1 DAI gets you 1/2 yvDAI
    uint exRate = 1e27;

    // For constant variables, the value has to be fixed at compile-time, while for immutable, it can still be assigned at construction time
    IERC20 public immutable underlying;

    // Emit event when ERC20 Tokens are deposited into Fractional Wrapper
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // Emit event when ERC20 Tokens are withdrawn from Fractional Wrapper
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(
        IERC20 underlying_,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20Mock(tokenName, tokenSymbol) {
        underlying = underlying_;
    }

    // Only the owner can call to modify exchange rate
    function setExchangeRate(uint256 exRate_) external onlyOwner {
        exRate = exRate_;
    }

    // Calculate how much yvDAI user should get based on exchange rate
    function convertToShares(
        uint256 assets
    ) public view returns (uint256 shares) {
        return (assets * exRate) / 1e27;
    }

    // Calculate how much DAI user should get based on exchange rate
    function convertToAssets(
        uint256 shares
    ) public view returns (uint256 assets) {
        return (shares * 1e27) / exRate;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        receiver = msg.sender;
        shares = convertToShares(assets);

        // Transfer DAI from user
        bool success = underlying.transferFrom(receiver, address(this), assets);
        require(success, "Deposit failed!");

        // Mint yvDAI to user
        bool sent = _mint(receiver, shares);
        require(sent, "Mint failed!");

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = convertToShares(assets);

        // MUST support a withdraw flow where the shares are burned from owner directly where owner is msg.sender,
        // OR msg.sender has ERC20 approval over the shares of owner
        if (msg.sender != owner) {
            uint allowedShares = _allowance[owner][receiver];
            require(allowedShares >= shares, "Allowance exceeded!");
            _allowance[owner][receiver] = allowedShares - shares;
        }

        // Burn wrapped tokens(shares) -> yvDAI
        burn(owner, shares);

        //transfer assets
        bool success = underlying.transfer(receiver, assets);
        require(success, "Transfer failed!");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        assets = convertToAssets(shares);

        // MUST support a redeem flow where the shares are burned from owner directly where owner is msg.sender,
        // OR msg.sender has ERC20 approval over the shares of owner
        if (msg.sender != owner) {
            uint allowedShares = _allowance[owner][receiver];
            require(allowedShares >= shares, "Allowance exceeded");
            _allowance[owner][receiver] = allowedShares - shares;
        }

        // Burn wrapped tokens(shares) -> yvDAI
        burn(owner, shares);

        // Transfer assets
        bool success = underlying.transfer(receiver, assets);
        require(success, "Transfer failed!");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function previewDeposit(
        uint256 assets
    ) external view returns (uint256 shares) {
        return convertToShares(assets);
    }

    function previewWithdraw(
        uint256 assets
    ) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    function asset() external view returns (address assetTokenAssets) {
        assetTokenAssets = address(underlying);
    }

    function totalAssets() external view returns (uint256 totalManagedAssets) {
        totalManagedAssets = underlying.balanceOf(address(this));
    }

    function maxDeposit() external view virtual returns (uint256 maxAssets) {
        maxAssets = type(uint256).max;
    }

    function maxMint() external view virtual returns (uint maxShares) {
        maxShares = type(uint256).max;
    }

    function previewMint(
        uint256 shares
    ) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        bool sent = underlying.transferFrom(msg.sender, address(this), assets);
        require(sent, "Transfer failed!");

        bool success = _mint(receiver, shares);
        require(success, "Mint failed!");
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function maxWithdraw(
        address owner
    ) external view returns (uint256 maxAssets) {
        maxAssets = convertToAssets(_balanceOf[owner]);
    }

    function maxRedeem(
        address owner
    ) external view returns (uint256 maxShares) {
        maxShares = _balanceOf[owner];
    }

    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }
}
