// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";

library SafeDecoder {
    function decodeBytes(bytes memory v) internal pure returns (bytes memory ret) {
        uint256 size;
        assembly {
            size := add(32, mload(add(v, 32)))
        }
        if (size >= 64) {
            assembly {
                size := add(size, mload(add(v, size)))
            }
            if (v.length >= size) ret = abi.decode(v, (bytes));
        }
    }

    function decodeAddress(bytes4 selector, bytes memory v) internal pure returns (bytes memory ret) {
        if (selector == IAddressResolver.addr.selector) {
            ret = decodeBytes(v);
        } else if (selector == IAddrResolver.addr.selector) {
            address a = address(uint160(uint256(bytes32(v))));
            if (a != address(0)) ret = abi.encodePacked(a);
        }
    }

    // function isZeros(bytes memory v) internal pure returns (bool ret) {
    //     assembly {
    //         let p := add(v, 32)
    //         let e := add(p, mload(v))
    //         let x
    //         ret := 1
    //         for {} lt(p, e) {} {
    //             x := mload(p)
    //             p := add(p, 32)
    //             if x {
    //                 ret := 0
    //                 break
    //             }
    //         }
    //         if and(gt(p, e), iszero(ret)) { ret := iszero(shr(shl(3, sub(p, e)), x)) }
    //     }
    // }
}
