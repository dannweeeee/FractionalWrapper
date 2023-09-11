// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console2.sol";

import "src/FractionalWrapper.sol";
import "src/DAIToken.sol";
using stdStorage for StdStorage;

abstract contract StateZero is Test, FractionalWrapper {
    DAIToken public dai;
    FractionalWrapper public wrapper;

    address user;
    address deployer;
    uint userTokens;

    constructor() FractionalWrapper(IERC20(dai), "yvDAI", "yvDAI") {}

    function setUp() public virtual {
        dai = new DAIToken();
        vm.label(address(dai), "dai contract");

        wrapper = new FractionalWrapper(IERC20(dai), "yvDAI", "yvDAI");
        vm.label(address(wrapper), "wrapper contract");

        user = address(1);
        vm.label(user, "user");

        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        // mint and approve
        userTokens = 100 * 1e18;
        dai.mint(user, userTokens);
        vm.prank(user);
        dai.approve(address(wrapper), type(uint).max);
    }
}

contract StateZeroTest is StateZero {
    // Note: User interacts directly with Wrapper in this scenario; no intermediary parties.
    // deploy: user is both caller and receiver
    // withdraw: user is both the owner and receiver

    function testCannotWithdraw(uint amount) public {
        console2.log(
            "User should be unable to withdraw without any deposits made"
        );
        vm.assume(amount > 0 && amount < dai.balanceOf(user));
        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        wrapper.withdraw(amount, user, user);
    }

    function testCannotRedeem(uint amount) public {
        console2.log(
            "User should be unable to redeem without any deposits made"
        );
        vm.assume(amount > 0 && amount < dai.balanceOf(user));
        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        wrapper.redeem(amount, user, user);
    }

    function testUserCannotChangeRate() public {
        console2.log("Only Owner of contract can change exchange rate");
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setExchangeRate(0.5e27);
    }

    function testDeposit() public {
        console2.log("User deposits DAI into Fractional Wrapper");
        uint shares = convertToShares(userTokens / 2);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user, user, userTokens / 2, shares);

        wrapper.deposit(userTokens / 2, user);
        assertTrue(wrapper.balanceOf(user) == dai.balanceOf(user));
    }

    function testMint() public {
        console2.log("Test minting of shares to user");
        uint shares = convertToShares(userTokens / 2);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user, user, userTokens / 2, shares);

        wrapper.mint(userTokens / 2, user);
        assertTrue(wrapper.balanceOf(user) == dai.balanceOf(user));
    }

    function testAsset() public {
        assertTrue(wrapper.asset() == address(dai));
    }

    function testTotalAssets() public {
        assertTrue(wrapper.totalAssets() == 0);
    }
}

abstract contract StateDeposited is StateZero {
    function setUp() public virtual override {
        super.setUp();

        //user deposits into wrapper
        vm.prank(user);
        wrapper.deposit(userTokens / 2, user);
    }
}

contract StateDepositedTest is StateDeposited {
    function testCannotWithdrawInExcess() public {
        console2.log(
            "User cannot withdraw in excess of what was deposited - burn() will revert"
        );
        vm.prank(user);
        vm.expectRevert("ERC20: Insufficient balance");
        wrapper.withdraw(userTokens, user, user);
    }

    function testCannotRedeemInExcess() public {
        console2.log(
            "User cannot redeem in excess of what was deposited - burn() will revert"
        );
        vm.prank(user);
        vm.expectRevert("ERC20: Insufficient balance");
        // since ex_rate = 1 -> qty of userTokens as shares = qty of userTokens | trivial conversion
        wrapper.redeem(userTokens, user, user);
    }

    function testWithdraw() public {
        console2.log("User withdraws his deposit");
        uint shares = convertToShares(userTokens / 2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, userTokens / 2, shares);

        vm.prank(user);
        wrapper.withdraw(userTokens / 2, user, user);

        assertTrue(wrapper.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) == userTokens);
    }

    function testRedeem() public {
        console2.log("User redeems his shares, for his deposit");
        // since ex_rate = 1 -> qty of userTokens as shares = qty of userTokens | trivial conversion
        // meaning: assets == userTokens/2 == shares
        uint assets = convertToAssets(userTokens / 2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, assets, userTokens / 2);

        vm.prank(user);
        wrapper.redeem(assets, user, user);

        assertTrue(wrapper.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) == userTokens);
    }

    function testTotalAssets() public {
        assertTrue(wrapper.totalAssets() == userTokens / 2);
    }

    function testMaxWithdraw() public {
        assertTrue(
            wrapper.maxWithdraw(user) == convertToAssets(userTokens / 2)
        );
    }

    function testMaxRedeem() public {
        assertTrue(wrapper.maxRedeem(user) == userTokens / 2);
    }
}

abstract contract StateRateChanges is StateDeposited {
    function setUp() public virtual override {
        super.setUp();

        // change exchange rate
        wrapper.setExchangeRate(0.5e27);

        //vm.prank(address(deployer));
        //setExchangeRate(0.5e27);

        // vm.mockCall(address(this), abi.encodeWithSelector(StateZero.setExchangeRate.selector), 0.5e27);

        /*
       stdstore
        .target(address(this))
        .sig(address(this).setExchangeRate.selector)
        .checked_write(0.5e27);
        */
    }
}

contract StateRateChangesTest is StateRateChanges {
    // Regardless withdraw or redeem the same proportionality changes to wrapped and underlying tokens apply due to ex_rate changes
    function testCannotWithdrawOrRedeemSameAmount() public {
        console2.log(
            "Rate depreciates: User's shares are convertible for more than original deposit sum"
        );
        console2.log("1 yvDAI is convertible for 2 DAI");

        //Note: if proceed to actually withdraw from wrapper, "ERC20: Insufficient balance", as wrapper does not have additional DAI to payout.
        uint assets = wrapper.convertToAssets(wrapper.balanceOf(user));
        assertTrue(assets > userTokens / 2);
        assertTrue(assets == userTokens);
    }

    function testCannotDepositSameAmount() public {
        console2.log(
            "Rate depreciates: User's second deposit converts to fewer shares than before"
        );
        console2.log("1 DAI is convertible for 1/2 yvDAI");

        vm.prank(user);
        wrapper.deposit(userTokens / 2, user);

        assertTrue(dai.balanceOf(user) == 0);
        assertTrue(wrapper.balanceOf(user) < userTokens);

        // initial deposit of userTokens/2 @ ex_rate = 1 -> wrapper.balanceOf(user) == userTokens/2
        // second deposit iof userTokens/2 @ ex_rate = 0.5 ->  wrapper.balanceOf(user) == userTokens/4
        assertTrue(wrapper.balanceOf(user) == userTokens / 2 + userTokens / 4);
    }

    function testWithdrawRateChange() public {
        console2.log(
            "Rate depreciates: User withdraws his deposit of userTokens/2 | will have remainder shares"
        );

        // initialShares == userTokens/2
        uint initialShares = wrapper.balanceOf(user);
        uint sharesWithdrawn = wrapper.convertToShares(userTokens / 2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, userTokens / 2, sharesWithdrawn);

        vm.prank(user);
        wrapper.withdraw(userTokens / 2, user, user);

        assertTrue(wrapper.balanceOf(user) == initialShares - sharesWithdrawn);
        assertTrue(dai.balanceOf(user) == userTokens);
    }

    function testRedeemRateChange() public {
        console2.log(
            "Rate depreciates: User redeems userTokens/2 worth of SHARES | will gain ASSETS of a larger quantity"
        );
        console2.log("1 DAI is convertible for 1/2 yvDAI");

        // user withdraws userTokens/2 of worth of shares
        // @ new rate, share should be equivalent to userTokens due to depreciation
        uint assets = wrapper.convertToAssets(userTokens / 2);
        assertTrue(assets == userTokens);

        // inject extra DAI into Wrapper to simulate payout
        stdstore
        .target(address(dai))
        .sig(dai.balanceOf.selector).with_key(address(wrapper)).checked_write( //select balanceOf mapping
                10000 * 10 ** 18
            ); //set mapping key balanceOf(address(vault)) //data to be written to the storage slot -> balanceOf(address(vault)) = 10000*10**18

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, assets, userTokens / 2); //asset = 50000000000000000000  | shares = 50000000000000000000

        vm.prank(user);
        wrapper.redeem(userTokens / 2, user, user); //asset = 100000000000000000000 | shares = 50000000000000000000

        assertTrue(wrapper.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) == userTokens + userTokens / 2);
    }
}
