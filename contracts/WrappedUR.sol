// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// provided as an example for how to wrap the UR

import {CCIPReader} from "@unruggable/CCIPReader.sol/contracts/CCIPReader.sol";
import {IUR, Lookup, Response} from "./IUR.sol";

contract WrappedUR is CCIPReader {
    IUR public immutable ur;

    constructor(IUR _ur) {
        ur = _ur;
    }

    function resolve(bytes memory dns, bytes[] memory calls, string[] memory gateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        lookup = ur.lookupName(dns);
        if (lookup.resolver == address(0)) return (lookup, res);
        //
        // insert resolver based logic here
        //
        bytes memory v = ccipRead(
            address(ur), abi.encodeCall(IUR.resolve, (dns, calls, gateways)), this.resolveCallback.selector, ""
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolveCallback(bytes memory ccip, bytes calldata)
        external
        pure
        returns (Lookup memory, Response[] memory)
    {
        assembly {
            return(add(ccip, 32), mload(ccip)) // exact same return as UR
        }
    }
}
