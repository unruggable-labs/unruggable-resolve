// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";

import "forge-std/console2.sol";

contract ExtendedNameResolver is IExtendedResolver {
    mapping(string => string) _names;

    function supportsInterface(bytes4 x) external pure returns (bool) {
        return type(IExtendedResolver).interfaceId == x;
    }

    function resolve(bytes calldata dns, bytes calldata call) external view returns (bytes memory) {
        if (bytes4(call) == INameResolver.name.selector) {
            string memory label = string(dns[1:1 + uint8(dns[0])]);
            return abi.encode(_names[label]);
        } else {
            return new bytes(64);
        }
    }

    function set(string memory label, string memory name) external {
        _names[label] = name;
    }
}
