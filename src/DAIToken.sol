//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {ERC20Mock} from "../lib/yield-utils-v2/src/mocks/ERC20Mock.sol";

contract DAIToken is ERC20Mock {
    bool public transferFail;

    constructor() ERC20Mock("DAI", "DAI") {
        transferFail = false;
    }

    function setFailTransfers(bool state_) public {
        transferFail = state_;
    }

    function _transfer(
        address src,
        address dst,
        uint wad
    ) internal override returns (bool) {
        if (transferFail) {
            return false;
        } else {
            return super._transfer(src, dst, wad);
        }
    }
}
