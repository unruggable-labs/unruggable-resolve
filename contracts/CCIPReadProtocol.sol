// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// https://eips.ethereum.org/EIPS/eip-3668
error OffchainLookup(address sender, string[] urls, bytes request, bytes4 callback, bytes carry);

struct OffchainLookupTuple {
    address sender;
    string[] gateways;
    bytes request;
    bytes4 selector;
    bytes carry;
}

library CCIPReadProtocol {
    function decode(bytes memory v) internal pure returns (OffchainLookupTuple memory x) {
        v = abi.encodePacked(v); // make a copy
        assembly {
            mstore(add(v, 4), sub(mload(v), 4)) // drop selector
            v := add(v, 4)
        }
        (x.sender, x.gateways, x.request, x.selector, x.carry) =
            abi.decode(v, (address, string[], bytes, bytes4, bytes));
    }
}
