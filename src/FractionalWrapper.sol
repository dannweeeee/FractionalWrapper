//SPDX-License-Identifer: MIT

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
}
