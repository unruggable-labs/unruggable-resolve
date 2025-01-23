// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUR, Lookup, Response} from "./IUR.sol";
import {OffchainLookup} from "./CCIPReadProtocol.sol";

contract WrappedUR {
    IUR immutable _ur;

    constructor(address ur) {
        _ur = IUR(ur);
    }

    function resolve(bytes memory name, bytes[] memory, string[] memory)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        lookup = _ur.lookupName(name);
        if (!lookup.ok) return (lookup, res);
        // registry checks go here
        return _wrap(msg.data);
    }

    function resolveCallback(bytes memory ccip, bytes memory carry)
        external
        view
        returns (Lookup memory, Response[] memory)
    {
        return _wrap(abi.encodeCall(IUR.resolveCallback, (ccip, carry)));
    }

    function _wrap(bytes memory call) internal view returns (Lookup memory, Response[] memory) {
        address ur = address(_ur);
        (bool ok, bytes memory v) = ur.staticcall(call);
        if (!ok && bytes4(v) == OffchainLookup.selector) {
            assembly {
                let ptr := add(v, 36)
                if eq(mload(ptr), ur) { mstore(ptr, address()) }
            }
        }
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
