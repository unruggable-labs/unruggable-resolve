// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OffchainLookup, OffchainLookupTuple, CCIPReadProtocol} from "./CCIPReadProtocol.sol";

struct Carry {
    address target;
    bytes4 callback;
    bytes carry;
    bytes4 myCallback;
    bytes myCarry;
}

contract CCIPReader {
    function ccipRead(address target, bytes memory call, bytes4 mySelector, bytes memory myCarry)
        internal
        view
        returns (bytes memory v)
    {
        bool ok;
        (ok, v) = target.staticcall(call);
        if (!ok && bytes4(v) == OffchainLookup.selector) {
            OffchainLookupTuple memory x = CCIPReadProtocol.decode(v);
            if (x.sender == target) {
                revert OffchainLookup(
                    address(this),
                    x.gateways,
                    x.request,
                    this.ccipReadCallback.selector,
                    abi.encode(Carry(target, x.selector, x.carry, mySelector, myCarry))
                );
            }
        }
        if (ok) {
            (ok, v) = address(this).staticcall(abi.encodeWithSelector(mySelector, v, myCarry));
        }
        if (!ok) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
    }

    function ccipReadCallback(bytes memory ccip, bytes memory carry) external view {
        Carry memory state = abi.decode(carry, (Carry));
        bytes memory v = ccipRead(
            state.target, abi.encodeWithSelector(state.callback, ccip, state.carry), state.myCallback, state.myCarry
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }
}
