// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CCIPReader} from "./CCIPReader.sol";
import {IUR, Lookup, Response} from "./IUR.sol";

contract URCaller is CCIPReader {
    IUR public immutable ur;

    constructor(address ur_) {
        ur = IUR(ur_);
    }

    function callResolve(
        bytes memory dns,
        bytes[] memory calls,
        string[] memory gateways,
        bytes4 myCallback,
        bytes memory myCarry
    ) internal view returns (bytes memory v) {
        return ccipRead(
            address(ur),
            abi.encodeCall(IUR.resolve, (dns, calls, gateways)),
            this.callResolveCallback.selector,
            abi.encode(myCallback, myCarry)
        );
    }

    function callResolveCallback(bytes memory ccip, bytes memory carry) external view {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        (bytes4 mySelector, bytes memory myCarry) = abi.decode(carry, (bytes4, bytes));
        (bool ok, bytes memory v) = address(this).staticcall(abi.encodeWithSelector(mySelector, lookup, res, myCarry));
        if (ok) {
            assembly {
                return(add(v, 32), mload(v))
            }
        } else {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
    }
}
