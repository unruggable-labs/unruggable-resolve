// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReverseName} from "../contracts/ReverseName.sol";
import "forge-std/Test.sol";

contract TestReverseName is Test {
    function test_default_reverse() external pure {
        assertEq(
            "d8da6bf26964af9d7eed9e03e53415d37aa96045.default.reverse",
            ReverseName.from(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045, 0)
        );
    }

    function test_addr_reverse() external pure {
        assertEq(
            "51050ec063d393217b436747617ad1c2285aeeee.addr.reverse",
            ReverseName.from(0x51050ec063d393217B436747617aD1C2285Aeeee, 1)
        );
    }

    function test_chain8543_reverse() external pure {
        assertEq(
            "b8c2c29ee19d8307cb7255e1cd9cbde883a267d5.8000215f.reverse",
            ReverseName.from(0xb8c2C29ee19D8307cb7255e1Cd9CbDE883A267d5, 8543)
        );
    }
}
