// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUR, Lookup, Response} from "./IUR.sol";
import {URCaller} from "./URCaller.sol";

contract WrappedUR is URCaller {
    constructor(address ur) URCaller(ur) {}

    function resolve(bytes memory dns, bytes[] memory calls, string[] memory gateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        lookup = ur.lookupName(dns);
        if (!lookup.ok) return (lookup, res);
        // extra logic goes here
        bytes memory v = callResolve(dns, calls, gateways, this.resolveCallback.selector, "");
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolveCallback(Lookup memory lookup, Response[] memory res, bytes memory /*carry*/ )
        external
        pure
        returns (Lookup memory, Response[] memory)
    {
        return (lookup, res);
    }
}
